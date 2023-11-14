## check redfish api

Nagios check hardware health via  [redfish API](https://en.wikipedia.org/wiki/Redfish_(specification)) has been tested on lenovo xcc, dell idrac. It may work on other brand.

### prerequisites

This script uses theses libs : REST::Client,Data::Dumper, Monitoring::Plugin, MIME::Base64; JSON, LWP::UserAgent, Readonly

to install them type :

```
sudo cpan REST::Client Data::Dumper Monitoring::Plugin MIME::Base64 JSON LWP::UserAgent Readonly
```

### Use case

```bash
./check_redfish_api.pl 2.0.0

This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
It may be used, redistributed and/or modified under the terms of the GNU
General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).

Nagios check hardware health via redfish API

Usage: ./check_redfish_api.pl -H <hostname> -p <port>  -u <User> -P <password> [-t <timeout>] [-a <apiversion>] [-S] [-T <sensor_list_and_threshold>]

 -?, --usage
   Print usage information
 -h, --help
   Print detailed help screen
 -V, --version
   Print version information
 --extra-opts=[section][@file]
   Read options from an ini file. See https://www.monitoring-plugins.org/doc/extra-opts.html
   for usage and examples.
 -H, --host=STRING
   Hostname
 -p, --port=INTEGER
   Port Number
 -a, --apiversion=string
   The redfish API version
 -u, --user=string
   User name for api authentication
 -P, --Password=string
   User password for api authentication
 -S, --ssl
  The mamagement card use ssl
  -C, --chassis
  Check Temp psu and fan only
 -T, --temp="probe1_name,warning,critical@probe2_name,warning2,critical2"
  Check some temperature sensor
   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.
 -t, --timeout=INTEGER
   Seconds before plugin times out (default: 30)
 -v, --verbose
   Show details for command-line debugging (can repeat up to 3 times)
```

Sample without temperature sensor:

```bash
 check_redfish_api.pl -H <IP> -p 443 -S -u <user@domain> -P <password> -t 40
```

Sample to list temperature sensor

```bash
 check_redfish_api.pl-H <IP> -p 443 -S -u <user@domain> -P <password> -T "wtf,0,0" 
```

Sample with two temperatures sensor

```bash
 check_redfish_api.pl-H <IP> -p 443 -S -u <user@domain> -P <password> -T "Ambient Temp,25,29@CPU1 Temp,55,60" -t 40
```

Sample with --chassis

```bash
check_redfish_api.pl -H <IP> -p 443 -S -u <user@domain> -P <password> -T "Ambient Temp,25,29@CPU1 Temp,55,60"  -t 40 -C
```

You may get :

```bash
#Sample without temperature sensor

check_redfish OK - ThinkAgile HX3321 Node SKU 7Y89CTO3WW, Intel(R) Xeon(R) Silver 4210R CPU @ 2.40GHz qty : 2, Memory qty 768 GiB, RAID Storage, 10 Drive  ok , M.2 Storage, 2 Drive  ok , 2 psu  ok , Redundancy Enabled, 14 Fans OK

#list temperature sensor

check_redfish_api UNKNOWN - wtf not found on <IP> available sensor(s) are :DIMM 17 Temp, Exhaust Temp, PCH Temp, CPU1 Temp, DIMM 3 Temp, DIMM 24 Temp, CPU2 Temp, Ambient Temp, DIMM 20 Temp, DIMM 5 Temp, DIMM 13 Temp, DIMM 1 Temp, DIMM 12 Temp, CPU2 DTS, DIMM 10 Temp, CPU1 DTS, DIMM 22 Temp, DIMM 8 Temp, DIMM 15 Temp

#Sample with two temperatures sensor

check_redfish OK - ThinkAgile HX3321 Node SKU 7Y89CTO3WW, Intel(R) Xeon(R) Silver 4210R CPU @ 2.40GHz qty : 2, Memory qty 768 GiB, RAID Storage, 10 Drive  ok , M.2 Storage, 2 Drive  ok , 2 psu  ok , Redundancy Enabled, 14 Fans OK, Ambient Temp is 23C, CPU1 Temp is 50C | Ambient_Temp=23C;25;29 CPU1_Temp=50C;55;60

#Sample with --chassis
check_redfish_api OK - 2 psu  ok , Redundancy Enabled, 14 Fans OK, Ambient Temp is 23C, CPU1 Temp is 50C | Ambient_Temp=23C;25;29 CPU1_Temp=50C;55;6
```
