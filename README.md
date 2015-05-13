# verigreen-reporting
Reporting facilities for Verigreen. Allows data mining on running instance(s) and later show statistics based on it.

This is a set of Perl scripts written to mine data from running VG instances, gather statistics (in JSON format) and create comprehenisve reports to show:
- Total number of committers
- Total number of commits
- Last commit timestamp (show activity)
- Overall intercpetion rate
  - Detailed date on different statuses
- Peak hours
- Average rate of commits per hour
- Committers data:
  - Per-Committer total number of commits, success, interception rate
  - Average build time and success build time
  
## Prerequisites
Perl (>5.10 is recommended and was tested on)
### Packages
The script will try to install missing ones, but requires cpan installation permissions for it
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
- FetchWebUiData.sample.xml - Configuration file to define the parameters of VG [Needs to be edited and renamed to FetchWebUiData.xml]
- VerigreenStats.css - CSS definitions for the output report (HTML)
- VerigreenStats.js - JavaScript method to allow exapnd/collapse of blocks
- VerigreenStats.pl - Create report from the gathered data in FetchWebUiData.pl
- VerigreenStats.sample.xml - Configuration file to define parameters for reporting [Needs to be edited and renamed to VerigreenStats.xml]
- lib/Ebc.pm - Extended Base Classes. Gives some service utilities (like logging, humand/PC file size format etc.)
- lib/VGS - VeriGreen Statistics helper classes. Does the reporting computation

## Usage
Rename FetchWebUiData.sample.xml and  VerigreenStats.sample.xml to FetchWebUiData.xml and VerigreenStats.xml (respectively).
Define a VG instance you wish to get data from in the FetchWebUiData.xml file, run the FetchWebUiData.pl file and the data will be stored (and aggregated every run) to the JSON file.
Define the stakeholders you wish to send the report to in VerigreenStats.xml, and run VerigreenStats.pl file to generate a report.
VerigreenStats.pl can generate a report on all instances defined in the .xml file. If you wish to genereate a specific report, you can run it as:

    VerigreenStats.pl -c [Display]
Where [Display] is the one appearing in the VerigreenStats.xml file corresponding to the specific instance you wish to generate a report for.

## License
This project is released under Apache v2.0 license
http://www.apache.org/licenses/LICENSE-2.0.html
