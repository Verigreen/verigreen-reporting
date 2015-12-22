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
#******************************************************************************#
package Ebc;                         # Extended Base Classes - common methods in regular use
BEGIN {
  my @packages = qw(Log::Log4perl Log::Log4perl::Appender::Screen File::Basename);
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

use Log::Log4perl qw(:easy);         # Logging facilities
use Log::Log4perl::Appender::Screen; # show the log output on the screen
use File::Basename;
use strict;
use warnings;
#******************************************************************************#
# Ebc - Extended Base Classes - Common methods in regular use                  #
# Written by Eitan Schichmanter (mailto:eitans@hp.com), June 2012              #
# Who                 | Which | When       | What                              #
# Eitan Schichmanter  | 1.0.0 | 03/06/2012 | Initial Version                   #
# Eitan Schichmanter  | 1.1.0 | 08/08/2012 | Adding SizeToHuman and SizeToPC   #
# Eitan Schichmanter  | 1.1.1 | 03/09/2012 | Enhancing InitLogger to accept no #
#                                            param and default to $0.log       #
# Eitan Schichmanter  | 1.1.2 | 05/03/2013 | Adding $logLevel for additional   #
#                                            robustness with Log init.         #
# Eitan Schichmanter  | 1.1.3 | 06/03/2013 | Removed the $debug for InitLogger #
# Eitan Schichmanter  | 1.1.4 | 12/12/2013 | Adding $fLogLevel and $sLogLevel  #
#                                            for fine-grained file/screen      #
#                                            logging options.                  #
# Eitan Schichmanter  | 1.2.0 | 16/12/2013 | Revising InitLogger to support a  #
#                                            hash input and optional rotation. #
#                                            Adding Terminate sub to handle    #
#                                            graceful logged termination.      #
# Eitan Schichmanter  | 1.2.1 | 13/03/2014 | Giving Terminate an exit code.    #
# Eitan Schichmanter  | 1.2.2 | 20/08/2014 | Adding prerequisites check        #
#******************************************************************************#

use base 'Exporter';
our @ISA    = qw(Exporter);
our @EXPORT = qw(InitLogger
                 SizeToHuman
                 SizeToPC
                 Terminate
                 );

my $VERSION = '1.2.2';

#******************************************************************************#
# InitLogger - enables Log::Log4perl logging facilities. Creates a config that #
# writes to a file (and optionally to the screen).                             #
# INPUT: [Opt] %params - optional parameters in a hash form. Supports:         #
#              $params{logfile} - The logfile name to use. If not specified,   #
#              will default to $0.log (without the original extension).        #
#              $params{purge} - remove existing log file from previous runs.   #
#              $params{disableScreen} - output messages to the screen.         #
#              If false or upspecified, will attach a screen appender as well. #
#              $params{fileLevel} - Sets the File log level (INFO).            #
#              $params{screenLevel} - Sets the Screen logging level (INFO).    #
#              $params{mode} - Supports 'clobber' or 'append' (default)        #
#              $params{size} - Set the max size for a log file.                #
#              [TBD] $params{date} - Set the date rotation for a log file.     #
#              $params{max} - Set the log rotation. Will retain {max} files of #
#              size $params{size} or last $params{date} (retain last 24 hrs).  #
# OUTPUT: $log - returns the handle for the log object to use in the calling   #
#         script.                                                              #
#******************************************************************************#
sub InitLogger
{
  my (%params) = @_;
  $Log::Log4perl::LOGEXIT_CODE = 7;
  $params{logfile} = fileparse($0, qr/\.[^.]*$/) . '.log' if !$params{logfile}; # remove the original extension
  unlink $params{logfile} if -e $params{logfile} and $params{purge}; # purge old file
  $params{fileLevel}   = 'INFO' if !$params{fileLevel};
  $params{screenLevel} = 'INFO' if !$params{screenLevel};
  my $appendersList = $params{fileLevel} ? $params{fileLevel} . ', File' : 'INFO, File';
  $appendersList   .= ', Screen' if !$params{disableScreen};

  my $layoutPat   = '[%d][%p] %m%n';
  my $layoutClass = 'Log::Log4perl::Layout::PatternLayout';
  # basic params
  my %logParams =
  (
    'log4perl.category.log'                           => $appendersList,
    'log4perl.appender.File'                          => 'Log::Log4perl::Appender::File',
    'log4perl.appender.File.filename'                 => $params{logfile},
    'log4perl.appender.File.mode'                     => 'append' || $params{mode},
    'log4perl.appender.File.layout'                   => $layoutClass,
    'log4perl.appender.File.layout.ConversionPattern' => $layoutPat,
    'log4perl.appender.File.Threshold'                => $params{fileLevel},
  );

  # Optional log rotation by size
  if ($params{size})
  {
    $logParams{'log4perl.appender.File'}                = 'Log::Dispatch::FileRotate';
    $logParams{'log4perl.appender.File.size'}           = $params{size};
    $logParams{'log4perl.appender.File.max'}            = $params{max} if $params{max}; # if not specified, will roll at size
  }
  
  
  if (!$params{disableScreen})
  { # add the screen appender to output messages to the screen as well
    $logParams{'log4perl.appender.Screen.Threshold'}                = $params{screenLevel};
    $logParams{'log4perl.appender.Screen'}                          = 'Log::Log4perl::Appender::Screen';
    $logParams{'log4perl.appender.Screen.stderr'}                   = 0;
    $logParams{'log4perl.appender.Screen.layout'}                   = $layoutClass;
    $logParams{'log4perl.appender.Screen.layout.ConversionPattern'} = $layoutPat;
  }

  Log::Log4perl->init_once(\%logParams) or die "Can't create a log file handle: $!\n";  
  my $log   = Log::Log4perl->get_logger('log');
  my $level = &getLevel($params{fileLevel}) <= &getLevel($params{screenLevel}) ? $params{fileLevel} : $params{screenLevel};
  $log->level($level);
  $log->debug("Ebc, v$VERSION"); # adds Ebc version if debugging is enabled
  return $log;
}

#******************************************************************************#
sub getLevel
{
  my $level = shift;
  my %levels = (0 => 'ALL', 1 => 'TRACE', 2 => 'DEBUG', 3 => 'INFO', 4 => 'WARN', 5 => 'ERROR', 6 => 'FATAL');
  foreach (keys %levels)
  {
    if ($levels{$_} =~ /$level/i)
    {
      return $_;
    }    
  }
  return -1; # couldn't find a correct level
}

#******************************************************************************#
# Terminate - enables graceful termination of a logged application             #
# INPUT: [Mand] $log - A Log::Log4perl log handle (hopefully created by        #
#               InitLogger above...                                            #
#               $msg - The message to log and die with (fataly)                #
# OUTPUT: None.                                                                #
#******************************************************************************#
sub Terminate
{
  my ($log, $msg) = @_;
  $log->logdie($msg); # will output [FATAL] $msg and exit with $Log::Log4perl::LOGEXIT_CODE = 7.
}

#******************************************************************************#
# SizeToHuman - Converts a size in bytes into a human-readable format          #
# INPUT: [Req] $size - The size to convert.                                    #
# OUTPUT: size in appropriate human size (KB, MB, GB and so on)                #
#******************************************************************************#
sub SizeToHuman
{
  my $size = shift;

  if ($size =~ /[^\d*]/)
  {
    return 0;
  }
  
  my $multiplier = 1024;
  my $KB         = $multiplier;
  my $MB         = $KB * $multiplier; # MegaByte
  my $GB         = $MB * $multiplier; # GigaByte
  my $TB         = $GB * $multiplier; # TeraByte
  my $PB         = $TB * $multiplier; # PetaByte
  my $EB         = $PB * $multiplier; # ExaByte
  my $ZB         = $EB * $multiplier; # ZetaByte
  my $YB         = $ZB * $multiplier; # YottaByte
  
  my $retSize = 0;
  my $postFix = '';
  my $format  = "%.2f";

  if ($size < $KB)
  {
    $retSize = (sprintf $format, $size);
  }
  elsif ($size < $MB and $size >= $KB)
  {
    $retSize = (sprintf $format, $size / $KB);
    $postFix = 'KB';
  }
  elsif ($size < $GB and $size >= $MB)
  {
    $retSize = (sprintf $format, $size / $MB);
    $postFix = 'MB';
  }
  elsif ($size < $TB and $size >= $GB)
  {
    $retSize = (sprintf $format, $size / $GB);
    $postFix = 'GB';
  }
  elsif ($size < $TB and $size >= $PB)
  {
    $retSize = (sprintf $format, $size / $TB);
    $postFix = 'TB';
  }
  elsif ($size < $PB and $size >= $EB)
  {
    $retSize = (sprintf $format, $size / $PB);
    $postFix = 'PB';
  }
  elsif ($size < $EB and $size >= $ZB)
  {
    $retSize = (sprintf $format, $size / $EB);
    $postFix = 'EB';
  }
  elsif ($size < $ZB and $size >= $YB)
  {
    $retSize = (sprintf $format, $size / $ZB);
    $postFix = 'ZB';
  }
  elsif ($size >= $YB)
  {
    $retSize = (sprintf $format, $size / $YB);
    $postFix = 'YB';
  }
  return "$retSize $postFix";
}

#******************************************************************************#
# SizeToPC - Converts a human-readable size into bytes                         #
# INPUT: [Req] $size - The size to convert.                                    #
# OUTPUT: $retSize - size in bytes                                             #
#******************************************************************************#
sub SizeToPC
{
  my $size = shift;
  
  my $multiplier = 1024;
  my $KB         = $multiplier;
  my $MB         = $KB * $multiplier; # MegaByte
  my $GB         = $MB * $multiplier; # GigaByte
  my $TB         = $MB * $multiplier; # TeraByte
  my $PB         = $TB * $multiplier; # PetaByte
  my $EB         = $PB * $multiplier; # ExaByte
  my $ZB         = $EB * $multiplier; # ZetaByte
  my $YB         = $ZB * $multiplier; # YottaByte

  my $retSize = 0;
  if ($size =~ /^([\d\.?]*)(\s*)?(\w+)$/i)
  {
    return $size if !$1;
    my $hSize = $1;
    if ($3 =~ /K/i)
    {
      $retSize = $hSize * $KB;
    }
    elsif ($3 =~ /M/i)
    {
      $retSize = $hSize * $MB;      
    }
    elsif ($3 =~ /G/i)
    {
      $retSize = $hSize * $GB;
    }
    elsif ($3 =~ /T/i)
    {
      $retSize = $hSize * $TB;
    }
    elsif ($3 =~ /P/i)
    {
      $retSize = $hSize * $PB;
    }
    elsif ($3 =~ /E/i)
    {
      $retSize = $hSize * $EB;
    }
    elsif ($3 =~ /Z/i)
    {
      $retSize = $hSize * $ZB;
    }
    elsif ($3 =~ /Y/i)
    {
      $retSize = $hSize * $YB;
    }
    else
    {
      $retSize = $hSize; # return as it is since it's in bytes without a postfix.
    }
  }
  return int $retSize; # return as integer.
}

#******************************************************************************#

1;