#*******************************************************************************
# Copyright 2015 Hewlett-Packard Development Company, L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.
#******************************************************************************#
package VGS;
BEGIN {
  my @packages = qw(JSON JSON::Parse LWP::Simple XML::Simple);
  foreach (@packages){
    unless (eval "use $_; 1") {
      print "$_ not installed... Installing: $_";
      # CPAN needs to be configured to accept silent installation options.
      # More info here: http://stackoverflow.com/questions/1039107/how-can-i-check-if-a-perl-module-is-installed-on-my-system-from-the-command-line      
      # You need to give sudo permissions to run cpan to the user running this script.
      my $ret = `sudo cpan $_`; 
      if ($?) {
        print "Error installing $_: $!\n";
        exit 7;
      }
    }
  }
}

use JSON;
use JSON::Parse 'parse_json';
use LWP::Simple;
use XML::Simple;
use strict;
use warnings;
#*******************************************************************************
# VGS - Verigreen Stats - Common operations for Verigreen.                      #
# Written by Eitan Schichmanter, 03/2014.                                       #
# Who                 | Which | When       | What                               #
# ES                  | 1.0.0 | 30/03/2014 | Initial Version                    #
# ES                  | 1.1.0 | 10/04/2014 | Adding more capabilities           #
# ES                  | 1.1.1 | 11/04/2014 | Some bug fixes                     #
# ES                  | 1.1.2 | 02/06/2014 | Fixed bug of non-existing Build    #
# ES                  | 1.1.3 | 02/06/2014 | Fixed aggregation data defects     #
# ES                  | 1.1.4 | 15/06/2014 | Default to totalNum of commits     #
# ES                  | 1.1.5 | 20/08/2014 | Adding prerequisites check         #
# ES                  | 1.1.6 | 02/09/2014 | Remove division-by-zero exception  #
# ES                  | 1.1.7 | 02/09/2014 | Remove division-by-zero exception  #
# ES                  | 1.2.0 | 02/09/2014 | Adding GetFile with JSON           #
# ES                  | 1.2.1 | 28/10/2014 | Adding Last commit time. Auth for  #
#                                            Jenkins >1.565.2 (applicative)     #
# ES                  | 1.3.0 | 30/11/2014 | Adding HTML output capabilities    #
# ES                  | 1.3.1 | 10/12/2014 | Adding GetCollectorVersion         #
# ES                  | 1.3.2 | 11/12/2014 | Adding commit times                #
# ES                  | 1.3.3 | 16/12/2014 | Adding counterstart everywhere     #
# ES                  | 1.3.4 | 17/12/2014 | Fixing REST compatibility with     #
#                                            collector >=1.2.1 (committer)      #
# ES                  | 1.3.5 | 01/01/2015 | Adding individual customer reports #
# ES                  | 1.4.0 | 16/04/2015 | Rebranding to Verigreen            #
# ES                  | 2.0.0 | 10/05/2015 | Releasing to Open-Source           #
# ES                  | 2.0.1 | 21/05/2015 | Fixing bug with over-peak hours    #
# This module requires cURL installed and on path to work correctly             #
#*******************************************************************************#
my $Version      = '2.0.1';

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(ShowTotals
                 GetJenkinsData
                 GetFile
                 SaveFiles
                 GetCollectorVersion
                 Epilogue
                );

# these are "global" parameters to be used throughout this module.
my $ms = 1000; # a MiliSecond converted to second
#*****************************************************************************#
sub ShowTotals {
  my %params = @_;
  my $data   = ${$params{data}};

  # give some defaults
  $params{totalNum}     = defined $data->[0]->{CollectorVersion} ? scalar @$data - 1: scalar @$data;
  $params{earliestTime} = time;
  $params{latestTime}   = 0;
  
  &gatherData(\%params); # analyze the data recieved and disect it
  &ShowSummary(\%params)       if $params{config}->{SummaryDisplay}->{ShowSummary};
  &ShowCommitHours(\%params)   if $params{config}->{SummaryDisplay}->{ShowCommitHours};  
  &ShowCommitersData(\%params) if $params{config}->{SummaryDisplay}->{ShowCommitersData};
  &ShowBuildTimes(\%params)    if $params{config}->{SummaryDisplay}->{ShowBuildTimes};
}

#*****************************************************************************#
sub gatherData {
  my $params     = shift;
  my $data       = ${$params->{data}};
  my $log        = ${$params->{log}};
  my $changed    = 0;
  my $countStart = defined $data->[0]->{CollectorVersion} ? 1 : 0; # if the version exists, skip this element
  for (my $i = $countStart; $i < @$data; $i++) {
    
    # remove running status commits as we can't tell their status - they're off the statistics.
    $params->{totalNum}-- if (defined $data->[$i]->{status} && $data->[$i]->{status} eq 'RUNNING');
    next if (defined $data->[$i]->{status} && $data->[$i]->{status} eq 'RUNNING'); # we'll skip the running types altogether.
    
    # if the status is not defined, add it as "empty"
    defined $data->[$i]->{status} ? $params->{statuses}->{$data->[$i]->{status}}++ : $params->{statuses}->{EMPTY}++;
    
    if (defined $data->[$i]->{creationTime}) {
      my $creationTime         = $data->[$i]->{creationTime} / $ms;
      $params->{earliestTime}  = $creationTime if $creationTime  < $params->{earliestTime};
      $params->{latestTime}    = $creationTime if $creationTime >= $params->{latestTime};
      ${$params->{lastCommit}} = $creationTime if $creationTime >= ${$params->{lastCommit}};

      my ($ss, $mm, $hh, $day, $month, $year, $zone) = localtime $creationTime;
      $year  += 1900;
      $month += 1;
      $month = '0'. $month if 10 > $month;
      $day   = '0'. $day if 10 > $day;
      $hh    = '0' . $hh if 0 < $hh && 10 > $hh;
      my $identifier = $year . $month . $day . '@' . $hh . '00';
      $params->{commitHours}->{$identifier}++;
    }  
    if (defined $data->[$i]->{runTime}) {
      my $startTime = $data->[$i]->{runTime} / $ms; # it's in ms so we're dividing by $ms to get to seconds
      my $endTime   = $data->[$i]->{endTime} / $ms if defined $data->[$i]->{endTime}; # it's in ms so we're dividing by $ms to get to seconds
      $data->[$i]->{buildTimeInMinutes} = int (($endTime - $startTime) / 60) if defined $endTime; # Dividing into hours and rounding to an integer
    }
    
    &GetJenkinsData($i, $params, \$changed);

    # Fixing a REST change in Collector 1.2.1 which changed 'commiter' to 'committer'. For backward compatibility we need to support both.
    if (defined $data->[$i]->{branchDescriptor}->{commiter} || defined $data->[$i]->{branchDescriptor}->{committer}) {
      my $committer = $data->[$i]->{branchDescriptor}->{commiter} || $data->[$i]->{branchDescriptor}->{committer};
      $params->{committers}->{$committer}++;
    }
  }
  
  # Only if the data has changed we'll overwrite the files with the new data
  my $file = $params->{config}->{InputFolder} . '/' . $params->{VUI};
  &SaveFiles($file, \$data)  if $changed;  
}

#*****************************************************************************#
sub GetFile {
  my ($log, $file, $rData) = @_;
  open (F, '<', $file) or &$log->warn("Can't open file $file") && next;
  my $fData = <F>;
  close F;
  $$rData = parse_json ($fData) or $log->warn("Error retrieving data from $file") and next;
  for (my $i = 0; $i < @$$rData; $i++)
  { # remove any undefined entries
    delete $$rData->[$i] if !defined $$rData->[$i];
  }
}

#*****************************************************************************#
sub SaveFiles {
  my ($file, $rData) = @_;
  my $jsonFile  = $file;
  my $json_text = to_json($$rData);
  open(my $J, '>', $jsonFile); # overwrite the file with the latest data
  print $J $json_text;
  close $J;  
}
#*****************************************************************************#
sub GetJenkinsData {
  my ($i, $params, $rChanged) = @_;
  return if !&isValidBuildUrl($i, $params);
  
  my $rData = ${$params->{data}};
  return if defined $rData->[$i]->{jenkinsData}->{duration} && defined $rData->[$i]->{jenkinsData}->{timestamp}; # no need to redo something we've already got
  
  my $log          = ${$params->{log}};
  my $url          = $rData->[$i]->{buildUrl};
  my $baseUrl      = $url;
  $baseUrl         =~ s/(.*)\/(.*)\/$/$1/;
  my $currentBuild = $2;

  return if !defined $currentBuild;
  $log->info("\tQuerying Jenkins for info on build $currentBuild...");
  my $jXmlData     = &getUrlData($url, $params);
  $log->warn("Can't access Jenkins Data") && return if !defined $jXmlData;
  my $rJenkinsData = $params->{jenkinsData};
  for (my $j = 0; $j < @{$rJenkinsData->{baseUrls}}; $j++) {
    if (lc $baseUrl eq lc $rJenkinsData->{baseUrls}->[$j]->{baseUrl}) {
      $rData->[$i]->{jenkinsData}->{duration}  = $jXmlData->{duration}  if defined $jXmlData->{duration};
      $rData->[$i]->{jenkinsData}->{timestamp} = $jXmlData->{timestamp} if defined $jXmlData->{timestamp}; # StartTime. We'll compare this with JB's ts to see the Verigreen footprint in terms of time
    }
    $$rChanged = 1 if defined $rData->[$i]->{jenkinsData}->{duration};
  }
  $log->info("\tDone");
}

#*****************************************************************************#
sub isValidBuildUrl {
  my ($i, $params) = @_;
  my $rData        = ${$params->{data}};
  my $baseUrl      = $rData->[$i]->{buildUrl};
  return 0 if !defined $baseUrl;
  
  $baseUrl         =~ s/(.*)\/(.*)\/$/$1/;
  my $currentBuild = $2;
  if (!defined $params->{jenkinsData}->{baseUrls}) {
    my $jXmlData = &getBaseUrlData($baseUrl, $params);
    return defined $jXmlData->{firstBuild}->{number} ? ($jXmlData->{firstBuild}->{number} <= $currentBuild) : 0;
  }
  
  my $exist = 0;
  for (my $i = 0; $i < @{$params->{jenkinsData}->{baseUrls}}; $i++) {
    $exist = 1 if ($params->{jenkinsData}->{baseUrls}->[$i]->{baseUrl} eq $baseUrl);
    
    if (defined $params->{jenkinsData}->{baseUrls}->[$i]->{baseUrl} && lc $params->{jenkinsData}->{baseUrls}->[$i]->{baseUrl} eq lc $baseUrl) {
      return defined $params->{jenkinsData}->{baseUrls}->[$i]->{firstBuild}->{number} ? $params->{jenkinsData}->{baseUrls}->[$i]->{firstBuild}->{number} <= $currentBuild : 0;
    }
  }
  if (!$exist) {
    my $jXmlData = &getBaseUrlData($baseUrl, $params);
    return defined $jXmlData->{firstBuild}->{number} ? ($jXmlData->{firstBuild}->{number} <= $currentBuild) : 0;
  }
  
  return 0; # if you got here - this is not a valid URL so we need to add it
}

#*****************************************************************************#
sub getBaseUrlData {
  my ($baseUrl, $params) = @_;
  my $jXmlData = &getUrlData($baseUrl, $params);
  my $d        = {baseUrl => $baseUrl};

  $d->{firstBuild} = $jXmlData->{firstBuild};
  push @{$params->{jenkinsData}->{baseUrls}}, $d;
  return $jXmlData;
}

#*****************************************************************************#
sub getUrlData {
  my ($url, $params) = @_;
  my $log      = ${$params->{log}};
  my $username = $params->{config}->{username};
  my $password = $params->{config}->{token};
  my $auth     = $params->{config}->{auth};
  my $xmlUrl   = $url . '/api/xml';
  $log->debug("Retrieving data from: $xmlUrl");
  my $cmd      = "curl --silent";
  $cmd .= " --insecure --user \"$username:$password\"" if $auth =~ /yes/i; # this is required for Jenkins > 1.565.2 which doesn't allow applicative users
  $cmd .= " -X POST $xmlUrl";
  $log->debug("$cmd");
  my $jData    = `$cmd`;
  $log->debug('Done');
  $log->debug("Dumping jData:\n\n");
  $log->debug("$jData");
  if ($jData =~ /Error Report/i) {
    return undef;
  }
  
  my $jXmlData = XML::Simple::XMLin($jData) if $jData;
  $log->debug("jData is defined") if $jData;
  return $jXmlData;
}

#*****************************************************************************#
sub ShowSummary {
  my $params = shift;
  my $sT     = localtime $params->{earliestTime};
  my $lT     = localtime $params->{latestTime};
  my $log    = ${$params->{log}};

  ${$params->{totalCommits}} += $params->{totalNum};
  my $str    = sprintf "[%i] commits passed through Verigreen since %s", $params->{totalNum}, $sT;
  $log->info($str);
  $str = "<p id=\"pHeader\">$str<br>\n";
  &updateHtml($params->{htmlData}, $str);
  &updateHtml($params->{htmlBrief}, $str);
  &updateHtml($params->{customerReport}, $str);
  $str    = sprintf "Last commit was made on %s", $lT;
  &updateHtml($params->{htmlData}, "$str<br>\n");
  &updateHtml($params->{htmlBrief}, "$str<br>\n");
  &updateHtml($params->{customerReport}, "$str<br>\n");
  $log->info($str);
  my $passedByChiled  = $params->{statuses}->{PASSED_BY_CHILD} || 0;
  my $passedAndPushed = $params->{statuses}->{PASSED_AND_PUSHED} || 0;
  my $success         = $passedByChiled + $passedAndPushed;
  ${$params->{totalFailed}} += $params->{totalNum} - $success;
  my $succssfrac      = $params->{totalNum} ? $success / $params->{totalNum} : 0; # the fraction of the success
  my $successP        = sprintf "%.2f%%", $succssfrac * 100; # the success percentage
  my $failP           = sprintf "%.2f%%", (1 - $succssfrac) * 100; # the failure percentage
  $str                = "Overall Success Rate: $successP";
  $log->info($str);
  &updateHtml($params->{htmlData}, "$str<br>\n");
  &updateHtml($params->{htmlBrief}, "$str<br>\n");
  &updateHtml($params->{customerReport}, "$str<br>\n");
  $str                = "Overall Failure Rate: $failP";
  $log->info($str);
  &updateHtml($params->{htmlData}, "$str<br>\n");
  &updateHtml($params->{htmlBrief}, "$str<br>\n");
  &updateHtml($params->{customerReport}, "$str<br>\n");

  # Control the verbosity of the detailed data to display  
  $params->{config}->{SummaryDisplay}->{ShowDetailedData} = 0 unless defined $params->{config}->{SummaryDisplay}->{ShowDetailedData};
  if ($params->{config}->{SummaryDisplay}->{ShowDetailedData}) {
    my $str = "Detailed data:";
    $log->info($str);
    &updateHtml($params->{htmlData}, "$str<br>\n");
    &updateHtml($params->{htmlBrief}, "$str<br>\n");
    &updateHtml($params->{customerReport}, "$str:<br>\n");
    foreach (keys %{$params->{statuses}}) {
      my $percentage = $params->{totalNum} ? sprintf "%.2f%%", $params->{statuses}->{$_} / $params->{totalNum} * 100 : 0;
      my $str = "\t$_: $percentage";
      $log->info($str);
      &updateHtml($params->{htmlData}, "$str<br>\n");
      &updateHtml($params->{htmlBrief}, "$str<br>\n");
      &updateHtml($params->{customerReport}, "$str<br>\n");
    }  
  }
  my $div = '*'x40;
  $log->info($div);
}

#*****************************************************************************#
sub ShowCommitHours {
  my $params      = shift;
  my $log         = ${$params->{log}};
  
  my $all         = 0;
  my $counter     = 0;
  my $biggestEver = 0;
  my $biggestId   = 0;
  my $overPeak    = 0;
  my $peak        = 10;
  foreach (keys %{$params->{commitHours}}) {
    $all        += $params->{commitHours}->{$_};
    $biggestId   = $_ if $params->{commitHours}->{$_} > $biggestEver;
    if ($params->{commitHours}->{$_} > $biggestEver) {
      $biggestEver = $params->{commitHours}->{$_};
      $overPeak++;
    }
    #print "Over $peak commits @ $data->{$_} @ $_\n" if $data->{$_} > $peak;
    #$overPeak++ if $params->{commitHours}->{$_} > $overPeak;
    $counter++;
  }
  
  my $percentage = $counter ? $overPeak / $counter * 100 : 0;
  my $str = sprintf "Total times over $biggestEver commits per hour: $overPeak (out of $counter possible hours) - %.2f%%\n", $percentage;
  $log->info($str);
  $str .= "<br>\n";
  &updateHtml($params->{htmlData}, $str);
  &updateHtml($params->{htmlBrief}, $str);
  &updateHtml($params->{customerReport}, $str);
  my $average = $counter ? $all / $counter : 0;
  $str = sprintf "The average rate of commits per hour is %.2f\n", $average;
  $log->info($str);
  $str .= "<br>\n";
  &updateHtml($params->{htmlData}, $str);
  &updateHtml($params->{htmlBrief}, $str);
  &updateHtml($params->{customerReport}, $str);
  my (undef, $year, $month, $day, $hh) = split /([0-9]{4})([0-9]{2})([0-9]{2})\@([0-9]{2})/, $biggestId;
  $str = "The busiest hour for commits was $month/$day/$year at $hh:00 [$biggestEver commits]";
  $log->info($str);
  $str .= "<br>\n";

  &updateHtml($params->{htmlData}, $str);
  &updateHtml($params->{htmlBrief}, $str);
  &updateHtml($params->{customerReport}, $str);
  $str = '*'x40;
  $log->info($str);
  my $paragraph = "</p>\n";
  &updateHtml($params->{htmlData}, $paragraph);
  &updateHtml($params->{htmlBrief}, "$paragraph</div>\n</div>\n<hr />\n");
  &updateHtml($params->{customerReport}, $paragraph);

}

#*****************************************************************************#
sub ShowCommitersData {
  my $params   = shift;
  my $data     = ${$params->{data}};
  my $log      = ${$params->{log}};
  my $distinct = scalar keys %{$params->{committers}};
  ${$params->{totalUsers}} += $distinct;
  my $tC = ${$params->{tickCnt}};
  my $str = "<div onClick=\"openClose(\'tick$tC\')\" style=\"cursor:hand; cursor:pointer\"><b><font color=purple> <u>Even More...</u> </font></b><br></div>\n<div id=\"tick$tC\" class=\"texter\">\n";
  ${$params->{tickCnt}}++;
  &updateHtml($params->{htmlData}, $str);
  &updateHtml($params->{customerReport}, $str);
  $str = "Total of $distinct distinct committers participated:";
  $log->info($str);
  $str = "<br>$str<br>\n";
  &updateHtml($params->{htmlData}, $str);
  &updateHtml($params->{customerReport}, $str);
  foreach (keys %{$params->{committers}}) {
    my $committer = $_;
    my $builds    = $params->{committers}->{$committer};
    $committer    =~ s/([\w\-]*).?([\w\-]*)\@.*/\u$1 \u$2/gi;
    $log->info("\t" . '*'x80);
    my $str = "$committer [$builds]";
    $log->info("\t$str");
    $str = "<p id=\"Committer\">$str</p>\n<table>\n";
    &updateHtml($params->{htmlData}, $str);
    &updateHtml($params->{customerReport}, $str);
    my $committerSuccess     = 0;
    my $committerTotal       = 0;
    my $committerTimeTotal   = 0;
    my $committerTime        = 0;
    my $committerTimeSuccess = 0;
    my $format               = "| %-25s | %-40s | %-17s | %-8s | %-83s |";
    my $lineLen              = 186;
    my $line                 = sprintf($format, 'Original Push Time', 'Commit ID', 'Status', 'Duration', 'URL');
    $str = "<tr>\n<td id=\"tHeader\">Original Push Time</td><td id=\"tHeader\">Commit ID</td><td id=\"tHeader\">Status</td><td id=\"tHeader\">Duration</td><td id=\"tHeader\">URL</td>\n</tr>\n";
    &updateHtml($params->{htmlData}, $str);
    &updateHtml($params->{customerReport}, $str);
    $log->info("\t$line") if $params->{config}->{SummaryDisplay}->{ShowDetailedData};
    $log->info("\t" . '-'x$lineLen) if $params->{config}->{SummaryDisplay}->{ShowDetailedData};
    my $countStart = defined $data->[0]->{CollectorVersion} ? 1 : 0; # if the version exists, skip this element
    for (my $i = $countStart; $i < @$data; $i++) {
      my $committer = defined $data->[$i]->{branchDescriptor}->{committer} ? $data->[$i]->{branchDescriptor}->{committer} : $data->[$i]->{branchDescriptor}->{commiter};
      next if !$committer;      
      if ($_ eq $committer) {
        my $commitId      = $data->[$i]->{branchDescriptor}->{commitId};
        my $status        = $data->[$i]->{status};
        my $creationTime  = 0 || $data->[$i]->{creationTime};
        my $startTime     = 0;
        my $endTime       = 0;
        my $duration      = 0;
        my $durationInMin = 0;
        $committerTotal++;
        if (defined $data->[$i]->{jenkinsData}->{duration}) { # we'll try to determine the data from the Verigreen UI itself
          $startTime     = $data->[$i]->{jenkinsData}->{timestamp} / $ms;
          $duration      = $data->[$i]->{jenkinsData}->{duration} / $ms;
          $durationInMin = sprintf ("%.2f", $duration / 60);
        } else { # try to get the data not from Jenkins
          $startTime     = $data->[$i]->{creationTime} / $ms;
          $endTime       = $data->[$i]->{endTime} / $ms if defined $data->[$i]->{endTime};
          $duration      = $endTime ? $endTime - $startTime : 0;
          $durationInMin = sprintf ("%.2f", $duration / 60);            
        }
        $committerTime += $durationInMin;
        if ($status =~ /PASSED/i) {
          $committerSuccess++;
          $committerTimeSuccess += $durationInMin;          
        }
        $committerTimeTotal++;
        my $commitTime = $creationTime / 1000;
        $commitTime    = localtime $commitTime;
        my $buildUrl   = defined $data->[$i]->{buildUrl} ? $data->[$i]->{buildUrl} : '<NONE>';
        my $line       = sprintf($format, $commitTime, $commitId, $status, $durationInMin, $buildUrl);
        if ($params->{config}->{SummaryDisplay}->{ShowDetailedData})
        {
          $str = "<tr>\n<td>$commitTime</td><td>$commitId</td><td>$status</td><td>$durationInMin</td><td><a href=\"$buildUrl\">$buildUrl</a></td>\n</tr>\n";
          &updateHtml($params->{htmlData}, $str);
          &updateHtml($params->{customerReport}, $str);
          $log->info("\t$line");          
        }
      }
    }
    $str = "</table>\n";
    &updateHtml($params->{htmlData}, $str);
    &updateHtml($params->{customerReport}, $str);
    $log->info("\t" . '-'x$lineLen) if $params->{config}->{SummaryDisplay}->{ShowDetailedData};
    my $committerSuccessPct     = sprintf("%.2f", $committerSuccess / $committerTotal * 100) if $committerTotal;
    my $committerTimeStr        = sprintf("%.2f", $committerTime / $committerTimeTotal) if $committerTimeTotal;
    my $committerSuccessTimeStr = sprintf("%.2f", $committerTimeSuccess / $committerSuccess) if $committerSuccess;
    &updateStatusOf($committerSuccessPct, "Committer Success: $committerSuccessPct%", $params) if $committerSuccessPct;
    &updateStatusOf($committerTime,       "Total Average Time to build: $committerTimeStr minutes", $params) if $committerTime;
    &updateStatusOf($committerSuccess,    "Average Success Time to build: $committerSuccessTimeStr minutes", $params) if $committerSuccess;
  }
  $log->info('*'x40);
}

#*****************************************************************************#
sub updateStatusOf {
  my ($item, $msg, $params) = @_;
  my $log = ${$params->{log}};
    if ($item)
    {
      my $str = $msg;
      &updateHtml($params->{htmlData}, "$str<br>");
      &updateHtml($params->{customerReport}, "$str<br>");
      $log->info("\t  $str");      
    }  
}

#*****************************************************************************#
sub ShowBuildTimes {
  my $params         = shift;
  my $data           = ${$params->{data}};
  my $log            = ${$params->{log}};
  my $totalBuildTime = 0;
  my $totalBuilds    = 0;
  my $countStart     = defined $data->[0]->{CollectorVersion} ? 1 : 0; # if the version exists, skip this element
  for (my $i = $countStart; $i < @$data; $i++) {
    if (defined $data->[$i]->{jenkinsData}->{duration}) {
      my $startTime     = $data->[$i]->{jenkinsData}->{timestamp} / $ms;
      my $sTstr         = localtime $startTime;
      my $duration      = $data->[$i]->{jenkinsData}->{duration} / $ms;
      my $buildDuration = $duration / 60;
      $totalBuildTime+= $buildDuration;
      $totalBuilds++;
    }
  }
  my $avg = $totalBuilds ? sprintf("%.2f", $totalBuildTime / $totalBuilds) : 0; # Avoid division-by-zero exception
  my $str = "Average Build Time: $avg minutes";
  $log->info($str);
  $str = "$str<br><br></p>\n</div>\n</div>\n<hr />\n";
  &updateHtml($params->{htmlData}, $str);
  &updateHtml($params->{customerReport}, $str);
}

#*****************************************************************************#
sub Epilogue {
  my %params = @_;
  my $log    = ${$params{log}};
  my $lT     = localtime ${$params{lastCommit}};
  my $lTStr  = sprintf "Last commit was made on %s", $lT;
  my $avFail = ${$params{totalCommits}} ? ${$params{totalFailed}} / ${$params{totalCommits}} * 100 : 0;
  my $avgStr = sprintf "Overall failure rate intercepted by Verigreen: %%%.2f", $avFail;

  my $epilogueStr .= "Overall ${$params{totalUsers}} Verigreen users\n";
  $epilogueStr .= "Overall ${$params{totalCommits}} commits\n";
  $epilogueStr .= "$lTStr\n";
  $epilogueStr .= "Total of ${$params{totalCollectors}} collectors deployed\n";
  $epilogueStr .= "$avgStr\n";
  $log->info("\n$epilogueStr");

  $epilogueStr =~ s/\n/\<br\>/g; # /r will retain the original $epilogueStr
  ${$params{htmlData}}  =~ s/_OVERALL_SUMMARY/$epilogueStr/; #replace the template string with the $html data
  ${$params{htmlBrief}} =~ s/_OVERALL_SUMMARY/$epilogueStr/; #replace the template string with the $html data
}

#*****************************************************************************#
sub GetCollectorVersion
{
  my %params           = @_;
  my $restCall         = $params{restCall};
  my $log              = ${$params{log}};
  my $collectorVersion = "curl --silent --GET $restCall";
  my $version          = `$collectorVersion`;
  if ($version =~ /^\<HTML\>/i) {
    return "N/A";
  }
  
  my $parsedVersion    = parse_json $version if $version;
  if (defined $parsedVersion->[0]->{_collectorVersion})
  {
    my $ver = $parsedVersion->[0]->{_collectorVersion};
    $log->info("Collector version: $ver");
    return $ver;
  }
  else
  {
    $log->info("Collector version < $params{initialVer}");
    return "< $params{initialVer}";
  }
}

#*****************************************************************************#
sub updateHtml {
  my ($rHtml, $str) = @_;
  $$rHtml .= $str;
}

#*****************************************************************************#
1;