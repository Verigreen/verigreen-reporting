#!/usr/bin/perl -w
#*******************************************************************************
# Copyright 2015 Hewlett Packard Enterprise Development Company, L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.
#*******************************************************************************
BEGIN {
  my @packages = qw(Getopt::Long XML::Simple File::Basename FindBin JSON JSON::Parse Mail::Sender);
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

use Getopt::Long;
use XML::Simple;
use File::Basename;
use Mail::Sender;
use FindBin qw($Bin);
use JSON;
use JSON::Parse 'parse_json';
use lib "$Bin/lib";
use Ebc; # common procedures
use VGS; # Verigreen-centric procedures
use strict;

#*******************************************************************************#
# VerigreenStats.pl - Show some stats on the Verigreen KPIs.                    #
# Written by Eitan Schichmanter, 03/2014.                                       #
# Who                 | Which | When       | What                               #
# ES                  | 1.0.0 | 26/03/2014 | Initial Version                    #
# ES                  | 2.0.0 | 10/05/2015 | Releasing to Open-Source           #
# ES                  | 2.0.1 | 31/05/2015 | Fixing cpan installation           #
#*******************************************************************************#
my $Version = '2.0.1';

my $debug    = 1;
my $customer = undef;
GetOptions('d|debug' => \$debug, 'c|customer:s' => \$customer);

my $level = $debug ? 'DEBUG' : 'INFO';
my $log   = &InitLogger(purge => 1);
$log->debug("Running in $level mode");
my $configData = &getConfig();
$log->info("$0 v$Version Starting...");
my $totalUsers         = 0;
my $totalCommits       = 0;
my $totalFailed        = 0;
my $totalCollectors    = 0;
my $lastCommit         = 0;
my $htmlData           = "";
my $htmlBrief          = "";
my $htmlCustomerHeader = "";
my $appName            = 'Verigreen';
&setHtmlHeader();
&showStats();
&sendEmail() unless defined $customer;

#*****************************************************************************#
# Subroutines                                                                 #
#*****************************************************************************#
sub getConfig {
  my $xml  = XML::Simple->new();
  my $data = $xml->XMLin(undef, ForceArray => ['Server']) or &Terminate($log, 'Error retrieving configuration data!');
  return $data;
}

#*****************************************************************************#
sub showStats {
  my $location = $configData->{InputFolder};

  $location =~ s/\//\\/g if ($^O =~ 'MSW'); # mostly for debugging on Windows...
  opendir D, $location;
  my $tickCnt = 1;
  foreach (readdir D) {
    next if /^..?$/; # ignore . and ..
    next if $_ !~ /\.json/i; # read ONLY json files
    next if -d "$location/$_"; # ignore sub directories
    my $displayName = basename($_, '.json');
    next if defined $customer && $displayName ne $customer; # run the report only for the specified customer if defined
    # TODO: Add multi-thread support so each call will be done in a seperate thread.
    
    # Getting the data for the specific server (username/token)
    my $serverData = &getServerData($displayName);
    $log->warn("Can't find data for $_. Skipping...") and next if !defined $serverData;
    $configData->{username} = $serverData->{username};
    $configData->{token}    = $serverData->{token};
    $configData->{auth}     = $serverData->{auth};
    my $file = "$location/$_";
    my $data = ();
    &GetFile($log, $file, \$data);

    my $customerReport = $htmlCustomerHeader; # this will hold the HTML data for the specific customer
    $log->info('*'x80);
    my $collectorVersion = defined $data->[0]->{CollectorVersion} ? $data->[0]->{CollectorVersion} : '';
    my $toDisplay        = $collectorVersion ? "Processing $displayName, version $collectorVersion:" : "Processing $displayName:";
    $log->info($toDisplay);
    my $customerData  = &getCustomerData($displayName);
    my $ui            = defined $customerData->{Address} ? "<a href=\"$customerData->{Address}\">$appName UI</a>" : '';
    $collectorVersion = "$appName Version " . $collectorVersion;
    my $str           = "<div onClick=\"openClose('$displayName')\" style=\"cursor:hand; cursor:pointer\"><font color=green><b>$displayName $collectorVersion</b></font><b><font color=purple><u>[click to expand]</u></font></b><br></div>\n";    
    $htmlData        .= $str;
    $str              = "<div><font color=green><b>$displayName $collectorVersion</b></font><br></div>\n";
    $customerReport  .= $str;
    $htmlBrief       .= $str;
    $str              = "<div id=\"$displayName\" class=\"texter\">\n";
    $htmlData        .= $str;
    $htmlData        .= "$ui<br>";
    $htmlBrief       .= $str;
    $tickCnt++;

    $configData->{SummaryDisplay}->{ShowSummary}       = 0 unless defined $configData->{SummaryDisplay}->{ShowSummary};
    $configData->{SummaryDisplay}->{ShowCommitHours}   = 0 unless defined $configData->{SummaryDisplay}->{ShowCommitHours};
    $configData->{SummaryDisplay}->{ShowCommitersData} = 0 unless defined $configData->{SummaryDisplay}->{ShowCommitersData};
    $configData->{SummaryDisplay}->{ShowBuildTimes}    = 0 unless defined $configData->{SummaryDisplay}->{ShowBuildTimes};

    &ShowTotals(log            => \$log,
                data           => \$data,
                config         => $configData,
                VUI            => $_,
                totalUsers     => \$totalUsers,
                totalCommits   => \$totalCommits,
                totalFailed    => \$totalFailed,
                lastCommit     => \$lastCommit,
                htmlData       => \$htmlData,
                htmlBrief      => \$htmlBrief,
                customerReport => \$customerReport,
                tickCnt        => \$tickCnt);
    $totalCollectors++;
    $log->info('*'x80);
    $customerReport .= "</body></html>\n";
    &sendEmail($displayName, $customerReport) if defined $customer; # send an individual report to the customer stakeholder    
  }
  &Epilogue(log => \$log,
            totalCollectors => \$totalCollectors,
            totalUsers      => \$totalUsers,
            totalCommits    => \$totalCommits,
            totalFailed     => \$totalFailed,
            lastCommit      => \$lastCommit,
            htmlData        => \$htmlData,
            htmlBrief       => \$htmlBrief);
  $htmlData .= "</body></html>\n";
}

#*****************************************************************************#
sub getServerData {
  my $name = shift;
  my $node = undef;
  foreach (@{$configData->{ServerData}->{Server}}) {
    if ($_->{Display} eq $name) {
      $node = $_;
      last;
    }    
  }
  return $node;
}

#*****************************************************************************#
sub setHtmlHeader
{
  my $cssFile = 'VerigreenStats.css';
  my $jsFile  = 'VerigreenStats.js';
  open(C, '<', $cssFile) or &Terminate($log, "Can't get CSS configuration at $cssFile. Please revise");
  my @css = <C>;
  close $cssFile;
  open(J, '<', $jsFile) or &Terminate($log, "Can't get JS configuration at $jsFile. Please revise");
  my @js = <J>;
  close J;
  $htmlData = <<"HTML";
<!DOCTYPE html>
<html lang=\"en\">
<head>
<style type=\"text/css\">
@css
</style>
<script language=\"JavaScript\" type=\"text/javascript\">
@js
</script>
</head>
<body>
HTML
my $now              = localtime time;
my $egs_Version      = "<h1>$appName Statistics v$Version Results [$now]:</h1>\n";
my $customerVersion  = "<h1>$appName Statistics [$now]:</h1>\n";
$htmlCustomerHeader  = $htmlData; # set the header for the customer report
$htmlCustomerHeader .= $customerVersion;

$htmlData .= $egs_Version;
$htmlData .= "<h2>Overall Statistics:</h2>\n";
$htmlData .= "<p>_OVERALL_SUMMARY<br></p>\n"; # this will be replaced in the end by the overall summary
$htmlData .= "<h3>Detailed information:</h3>\n<div>\n";
$htmlBrief = $htmlData;
}


#*****************************************************************************#
sub sendEmail
{
  my ($customer, $report) = @_;
  my $customerData = &getCustomerData($customer);
  my $mailServer   = $configData->{SMTP};
  my $domain       = $configData->{Domain};
  my $stakeHolders = defined $customerData ? $customerData->{Stakeholders} : $configData->{Stakeholders};
  my $toUsers      = '';
  foreach (split /;/, $stakeHolders)
  {
    my $email = /\@/ ? $_: $_ . '@' . $domain; # if a domain already exists, leave it as as.
    $toUsers .= $email . ',';
  }
  chop $toUsers; # remove last ','
  return if !$toUsers; # no need to send email if we don't have anyone to send to...

  my $output     = 'VerigreenStats.html';
  my $outputData = $htmlData;
  my $msg        = $htmlBrief;
  my $subject    = "$appName Statistics";
  if (defined $customerData) {
    $output     = "$customer.html";
    $outputData = $report;
    $msg        = "Hello,<br>Please see the attached report for more details<br>Have an <font color=green><b>$appName</b></font> Day!<br><br>BR,<br>The $appName Reporter\n";
    $msg       .= "<br>(You can see the status of your $appName <a href=\"$customerData->{Address}\">here</a>)" if defined $customerData->{Address};
    $subject    = "$appName Statistics for $customer";
  }
  
  open(H, ">", $output);
  print H $outputData; # output to screen the entire html data gathered.
  print "$outputData\n" if $debug;
  close H;
  if (!$customerData) {
    my $ret = `cp $output $configData->{InputFolder}`; # Copy the report to the shared location to be used there (by the dashboard initiative)
    if ($ret) {
      $log->error("Coludn't copy $output to $configData->{InputFolder}: $!");
    }    
  }
  
  
  my $sender = new Mail::Sender
  {smtp => $mailServer . '.' . $domain, from => 'verigreen.stats@' . $domain};
  if ($Mail::Sender::Error) {
    $log->warn("Error creating mail object: $Mail::Sender::Error");
    return;
  }

  $sender->MailFile({
    to      => $toUsers,
    subject => $subject,
    b_ctype => 'text/html',
    msg     => $msg,
    file    => $output});    
  $log->info('Done');
  unlink $output;
}

#*****************************************************************************#
sub getCustomerData
{
  my $customer = shift;
  return undef if !defined $customer;
  foreach (@{$configData->{ServerData}->{Server}})
  {
    if ($_->{Display} eq $customer) {
      return $_;
    }    
  }
  return undef;
}

#*****************************************************************************#
__END__