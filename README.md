# verigreen-reporting
Reporting facilities to Verigreen. Allows data mining on a running instance and later show statistics based on it.

This is a set of Perl scripts written to mine data from running VG instances, gather statistics (in JSON format) and create comprehenisve reports to show:
- Total number of commits
- Success Rate
- Interception Rate
  - Errors
- Peak hours
- Committers data:
  - Per-Committer total number of commits, success, interception rate
  - Average build time and success build time
  
## Prerequisites
Perl (>5.10 is recommended and was tested on)
### Packages (will try to install missing ones, but requires permissions for it)
- Getopt::Long (parse command line parameters)
- XML::Simple (parse configuration files)
- File::Basename (filename manipulation)
- FindBin (working with local library folders)
- JSON (output to JSON format)
- JSON::Parse (parse JSON into Perl constructs)
- Mail::Sender (send mail to stakeholders)
- LWP::Simple (query Jenkins for extra data)
- Log::Log4perl (loggging facilities)
- Log::Log4perl::Appender::Screen (output log messages to the screen while running)

## Contents
- FetchWebUiData.pl - Query the running instance
- FetchWebUiData.xml - Configuration file to define the parameters of VG
- VerigreenStats.css - CSS definitions for the output report (HTML)
- VerigreenStats.js - JavaScript method to allow exapnd/collapse of blocks
- VerigreenStats.pl - Create report from the gathered data in FetchWebUiData.pl
- VerigreenStats.xml - Configuration file to define parameters for reporting
- lib/Ebc.pm - Extended Base Classes. Gives some service utilities (like logging, humand/PC file size format etc.)
- lib/VGS - VeriGreen Statistics helper classes. Does the reporting computation

## Usage
Define a VG instance you wish to get data from in the FetchWebUiData.xml file, run the FetchWebUiData.pl file and the data will be stored (and added every run) to the JSON file.
Define the stakeholders you wish to send the report to in VerigreenStats.xml, and run VerigreenStats.pl file to generate a report.
