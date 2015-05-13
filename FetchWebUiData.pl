#!/usr/bin/perl -w
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
#*******************************************************************************
BEGIN {
  my @packages = qw(XML::Simple LWP::Simple JSON JSON::Parse FindBin);
  foreach (@packages){
    unless (eval "use $_; 1") {
      print "$_ not installed... Installing: $_";
      my $ret = `cpan install $_`;
      if ($?) {
        print "Error installing $_: $!\n";
        exit 7;
      }
    }
  }
}

use XML::Simple;
use LWP::Simple;
use JSON;
use JSON::Parse 'parse_json';
use FindBin qw($Bin);
use lib "$Bin/lib";
use Ebc;
use VGS;
use strict;

#******************************************************************************#
# FetchWebUiData.pl - Fetch JSON data from Verigreen UI and store diffs.       #
# Written by Eitan Schichmanter, 03/2014.                                      #
# ES                  | 1.1.0 | 10/04/2014 | Adding Jenkins crawling           #
# ES                  | 1.2.0 | 27/05/2014 | Multiple Collectors support       #
# ES                  | 1.2.1 | 20/08/2014 | Adding prerequisites check        #
# ES                  | 1.2.2 | 02/09/2014 | Saving new configuration          #
# ES                  | 1.3.0 | 07/10/2014 | Dumping storable, moving to JSON  #
# ES                  | 1.3.1 | 27/10/2014 | Fixing curl access issues         #
# ES                  | 1.4.0 | 16/04/2015 | Rebranding to Verigreen           #
# ES                  | 2.0.0 | 10/05/2015 | Releasing to Open-Source          #
#******************************************************************************#
my $Version      = '2.0.0';

my $log        = &InitLogger();
my $configData = &getConfig();
$log->info("$0 v$Version Starting...");
&processServers();
$log->info('Done');

#*****************************************************************************#
# Subroutines                                                                 #
#*****************************************************************************#
sub getConfig {
  my $xml  = XML::Simple->new();
  my $data = $xml->XMLin(undef, ForceArray => [ 'Server' ]) or &Terminate($log, 'Error retrieving configuration data!');
  return $data;
}

#*****************************************************************************#
sub processServers {
  my $param                = $configData->{Params}->{Rest};
  my $restCollectorVersion = $configData->{Params}->{Version};
  my $outputDir            = $configData->{Params}->{OutputRoot};
  foreach my $server (@{$configData->{ServerList}->{Server}}) {
    my $display = $outputDir . '/' . $server->{Display} . '.json';
    my $d       = undef;
    $display =~ s/\//\\/g if ($^O =~ 'MSW'); # mostly for debugging on Windows...
    
    $log->info("Accessing $display...");
    &GetFile($log, $display, \$d) if -e $display;
    my $collectorVersion = &GetCollectorVersion(log => \$log, restCall => "$server->{Address}/$restCollectorVersion", initialVer =>$configData->{Params}->{FirstSupporttedVersion});
    my $changed          = 0;
    if (!defined $d->[0]->{CollectorVersion}) { # no version at all
      splice @$d, 0, 0, {CollectorVersion => $collectorVersion};
      $changed = 1;
    }
    if (defined $d->[0]->{CollectorVersion} && $d->[0]->{CollectorVersion} ne $collectorVersion) { # version has changed
      $d->[0]->{CollectorVersion} = $collectorVersion;
      $changed = 1;
    }

    # This is a commented-out section to remove any empty hash references - this needs to be investigated as a potential bug in the UI system.
    #my @del_indexes = reverse(grep { !defined $d->[$_] } 0..$#$d);
    #foreach my $item (@del_indexes) {splice (@$d, $item, 1);}

    my $cmd = "curl --silent --GET $server->{Address}/$param";
    $log->debug("Qyerying: $cmd");
    my $data      = `$cmd`;
    $log->warn("Error accessing the $display collector. Please check connectivity") and next if $data =~ /(The Web Server may be down|Connection refused)/i;
    my $perl      = parse_json ($data) if defined $data;
    $log->info("$display [$server->{Address}] Has no data. Continuing...") and next if !defined $perl or scalar @$perl == 0;
    $log->warn("Can't parse $display [$server->{Address}] for data...") and next if !$perl;

    my @additions = ();
    my $exists    = 0;
    for (my $i = 0; $i < @$perl; $i++) {
      my $pCommitId = $perl->[$i]->{branchDescriptor}->{commitId};
      $log->warn("Can't get commit ID from server") if !defined $pCommitId;
      $exists = 0;
      if ($d) {
        my $countStart = defined $d->[0]->{CollectorVersion} ? 1 : 0; # if the version exists, skip this element
        for (my $j = $countStart; $j < @$d; $j++) {
          if (!defined $d->[$j]->{branchDescriptor}->{commitId}) {
            delete $d->[$j];
            next;
          }
  
          my $dCommitId = $d->[$j]->{branchDescriptor}->{commitId};
          my $state     = $d->[$j]->{status};
          if (defined $state and $state eq 'RUNNING') { # we'll ignore all the running states and for now the EMPTY ones as well...
            delete $d->[$j];
            next;
          }          
          $exists = 1 if ((defined $dCommitId && defined $pCommitId) and ($dCommitId eq $pCommitId));
        }
      }
      
        if (!$exists) {
        my $creationTime = $perl->[$i]->{creationTime};
        $log->warn("Can't retrieve creation time") and next if !defined $creationTime;
        my $ts = localtime ($creationTime / 1000); # since time is in ms I divide by 1000
        $log->info("Discovered new Commit ID: $pCommitId, from $ts");
        $changed = 1;
        push @additions, $i;
      }    
    }
    
    for (@additions) {
      &GetJenkinsData($_, {log => \$log, data => \$perl, config => $server, VUI => $display}, \$changed);
      push @$d, $perl->[$_];
    }    
    &SaveFiles($display, \$d) if $changed || !$exists; # exists denotes a new configuration added
  }  
}

#*****************************************************************************#

__END__