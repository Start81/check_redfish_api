#!/usr/bin/perl -w
#================================================================================
# Script Name   : check_redfish_api.pl
# Usage Syntax  : check_redfish_api.pl -H <hostname> -p <port>  -u <User> -P <password> [-t <timeout>] [-a <apiversion>] [-S] [-T <sensor_list_and_threshold>]
# Version       : 2.0.2
# Last Modified : 22/11/2022
# Modified By   : Start81 J DESMAREST
# Description   : Nagios check hardware health via redfish API
# Depends On    : Monitoring::Plugin, Data::Dumper, MIME::Base64, JSON, REST::Client, LWP::UserAgent
# 
# Changelog: 
#    Legend: 
#       [*] Informational, [!] Bugfix, [+] Added, [-] Removed 
#  - 17/06/2022 | 1.0.0 | [*] First release
#  - 22/06/2022 | 1.1.0 | [*] Rework on temperature checking now the check get ans compare the sensor named in the parameters of the script
#  - 06/07/2022 | 1.2.0 | [*] Handle when there are no psu fan and drive on a controller
#  - 19/07/2022 | 1.3.0 | [*] Add --chassis to check only Temperature psu and Fans
#  - 21/07/2022 | 1.3.1 | [*] Refactoring
#  - 21/07/2022 | 2.0.0 | [+] now the script can check a list of temp sensor
#  - 14/11/2022 | 2.0.1 | [*] Change the temp separator from ; to @ this for improve Monioring tools compatibility
#  - 22/11/2022 | 2.0.2 | [*] Update powersupply json parsing
#===============================================================================

use strict;
use IO::Socket::SSL qw( SSL_VERIFY_NONE );
use warnings;
use Monitoring::Plugin;
use Data::Dumper;
use REST::Client;
use JSON;
use utf8; 
use MIME::Base64;
use LWP::UserAgent;
use Readonly;
use File::Basename;
Readonly our $VERSION => '2.0.2';
my $o_verb;
sub verb { my $t=shift; if ($o_verb) {print $t,"\n"}  ; return 0}
my $np = Monitoring::Plugin->new(
    usage => "Usage: %s -H <hostname> -p <port>  -u <User> -P <password> [-t <timeout>] [-a <apiversion>] [-S] [-T <sensor_list_and_threshold>] \n",
    plugin => basename($0),
    shortname => 'check_redfish_api',
    blurb => 'Nagios check hardware health via redfish API',
    version => $VERSION,
    timeout => 30
);
$np->add_arg(
    spec => 'host|H=s',
    help => "-H, --host=STRING\n"
          . '   Hostname',
    required => 1
);
$np->add_arg(
    spec => 'port|p=i',
    help => "-p, --port=INTEGER\n"
          . '   Port Number',
    required => 1,
    default => "443"
);
$np->add_arg(
    spec => 'apiversion|a=s',
    help => "-a, --apiversion=string\n"
          . '   The redfish API version',
    required => 1,
    default => 'v1'
);
$np->add_arg(
    spec => 'user|u=s',
    help => "-u, --user=string\n"
          . '   User name for api authentication',
    required => 1,
);
$np->add_arg(
    spec => 'Password|P=s',
    help => "-P, --Password=string\n"
          . '   User password for api authentication',
    required => 1,
);

$np->add_arg(
    spec => 'ssl|S',
    help => "-S, --ssl\n"  
         . '  The mamagement card use ssl',
    required => 0
);
$np->add_arg(
    spec => 'chassis|C',
    help => "-C, --chassis\n"  
         . '  Check Temp psu and fan only',
    required => 0
);
$np->add_arg(
    spec => 'temp|T=s',
    help => '-T, --temp="probe1_name,warning,critical@probe2_name,warning2,critical2"' . "\n"
         . '  Check some temperature sensor' . "\n" 
         . '   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.',
    required => 0
);

$np->getopts;
my $o_host = $np->opts->host;
my $o_login = $np->opts->user;
my $o_pwd = $np->opts->Password;
my $o_apiversion = $np->opts->apiversion;
my $o_port = $np->opts->port;
my $o_use_ssl = 0;
# my $o_warning = $np->opts->warning;
# my $o_critical = $np->opts->critical;
my $o_temperature = $np->opts->temp;
my $o_chassis = $np->opts->chassis;
$o_use_ssl = $np->opts->ssl if (defined $np->opts->ssl);
$o_verb = $np->opts->verbose;
my $o_timeout = $np->opts->timeout;
if ($o_timeout > 60){
    $np->plugin_die("Invalid time-out");
}
my $i = 0;
my $j = 0;
my $k = 0;
my @criticals = ();
my @warnings = ();
my @ok = ();
my $nb_drive_ok = 0;
my $msg;
my $hw_rep;
my $id;
my $hardware;
my $system;
my $url_system;
my $cpu;
my $memory;
my $url_strorages_list;
my $url_strorage;
my $storage_rep;
my $storages_list;
my $storage;
my $storage_name;
my $url_drive;
my $drive_rep;
my $drive;
my $url_psu;
my $psu_rep;
my $psu; 
my $nb_psu_ok;
my $psu_redundancy = 0 ;
my $url_chassis_thermal;
my $chassis_rep;
my $chassis;
my $nb_fans_ok;
my $compare_status;
my $instance_found = 0;
my @instance_list = ();
my $client = REST::Client->new();
alarm($o_timeout);
my $url = "http://";
my $base_url ;
$client->addHeader('Content-Type', 'application/json');
$client->addHeader('Accept', 'application/json');
$client->addHeader('Accept-Encoding',"gzip, deflate, br");
if ($o_use_ssl) {
    my $ua = LWP::UserAgent->new(
        timeout  => $o_timeout,
        ssl_opts => {
            verify_hostname => 0,
            SSL_verify_mode => SSL_VERIFY_NONE
        },
    );
    $url = "https://";
    $client->setUseragent($ua);
}

#get systems list
my $main_url;
$base_url = "$url$o_host:$o_port";
verb("print base url $base_url");
my $url_systems = "$base_url/redfish/$o_apiversion/Systems";
my $url_chassis = "$base_url/redfish/$o_apiversion/Chassis";
if (!($o_chassis)) {
    $main_url = $url_systems;
    verb("full url : $main_url");
    $client->addHeader('Authorization', 'Basic ' . encode_base64("$o_login:$o_pwd"));
    $client->GET($main_url);
    if($client->responseCode() ne '200'){
        $np->plugin_exit('UNKNOWN', "response code : " . $client->responseCode() . " Message : Error when getting items systems list  $main_url" . $client->{_res}->decoded_content );
    }
    my $rep = $client->{_res}->decoded_content;
    my $items = from_json($rep);
    while (exists ($items->{'Members'}->[$i])){
        $id = $items->{'Members'}->[$i]->{'@odata.id'};
        $url_system = "$url$o_host:$o_port$id";
        $client->GET($url_system);
        # if($client->responseCode() ne '200'){
           # $np->plugin_exit('UNKNOWN', "response code : " . $client->responseCode() . " Message : Error when getting systems $i ". $client->{_res}->decoded_content );
        # }
        if($client->responseCode() eq '200'){
            $hw_rep = $client->{_res}->decoded_content;
            $hardware = from_json($hw_rep);
            verb(Dumper($hardware->{'ProcessorSummary'}));
            #System global
            $system = $hardware->{'Model'} . " SKU " . $hardware->{'SKU'};
            verb ($system);
            if (defined ($hardware->{'Status'}->{'HealthRollup'}) and (length ($hardware->{'Status'}->{'HealthRollup'})) >= 2){
                if ($hardware->{'Status'}->{'HealthRollup'} eq "OK") {
                    push(@ok,  $system) 
                } else {
                     push(@criticals,  $system ." state is " . ($hardware->{'Status'}->{'HealthRollup'}))
                }
            } else
            {
                $np->plugin_exit('UNKNOWN', "Empty system info" );
            }
            #cpu / memory
            $cpu = $hardware->{'ProcessorSummary'}->{'Model'} . " qty : " . $hardware->{'ProcessorSummary'}->{'Count'}; 
            if (defined ($hardware->{'ProcessorSummary'}->{'Status'}->{'HealthRollup'}) and (length ($hardware->{'ProcessorSummary'}->{'Status'}->{'HealthRollup'})) >= 2) {
                if ($hardware->{'ProcessorSummary'}->{'Status'}->{'HealthRollup'} eq "OK") {
                    push(@ok,  $cpu) ;
                } else {
                    push(@criticals,  $cpu . " state is " . ($hardware->{'ProcessorSummary'}->{'Status'}->{'HealthRollup'}));
                }
            }
            verb(Dumper($hardware->{'MemorySummary'}));
            $memory = "Memory qty " . $hardware->{'MemorySummary'}->{'TotalSystemMemoryGiB'} . " GiB";
            if (defined  ($hardware->{'MemorySummary'}->{'Status'}->{'HealthRollup'}) and (length ($hardware->{'MemorySummary'}->{'Status'}->{'HealthRollup'})) >= 2) {
                if ($hardware->{'MemorySummary'}->{'Status'}->{'HealthRollup'} eq "OK") {
                    push(@ok,  $memory)
                } else {
                    push(@criticals,  $memory ." state is " . ($hardware->{'MemorySummary'}->{'Status'}->{'HealthRollup'}))
                }
            }
            #Storage
            $url_strorages_list = "$url_system/Storage";
            verb($url_strorages_list);
            $client->GET($url_strorages_list);
            if($client->responseCode() ne '200'){
               $np->plugin_exit('UNKNOWN', "response code : " . $client->responseCode() . " Message : Error when getting storage list for systems $i ". $client->{_res}->decoded_content );
            }
            $storage_rep = $client->{_res}->decoded_content;
            $storages_list = from_json($storage_rep);
            verb(Dumper($storages_list));
            $j = 0;
            while (exists ($storages_list->{'Members'}->[$j])){
                $id = $storages_list->{'Members'}->[$j]->{'@odata.id'};
                $url_strorage = "$base_url$id";
                verb($url_strorage);
                $client->GET($url_strorage);
                if($client->responseCode() ne '200'){
                   $np->plugin_exit('UNKNOWN', "response code : " . $client->responseCode() . " Message : Error when getting systems $i storage $j ". $client->{_res}->decoded_content );
                }
                $storage_rep = $client->{_res}->decoded_content;
                $storage = from_json($storage_rep);
                if (exists $storage->{'Drives@odata.count'}) {
                    if ($storage->{'Drives@odata.count'} != 0) {
                        $storage_name = $storage->{'Name'};
                        if (defined ($storage->{'Status'}->{'HealthRollup'}) and (length (($storage->{'Status'}->{'HealthRollup'}))) >= 2) {
                            if  ($storage->{'Status'}->{'HealthRollup'} eq "OK") {
                                push(@ok,  $storage_name)
                            } 
                            else {
                                push(@criticals, $storage_name  ." state is " . ($storage->{'Status'}->{'HealthRollup'}));
                            }
                        }
                        #Disques
                        $nb_drive_ok=0;
                        $k = 0;
                        while (exists ($storage->{'Drives'}->[$k])){
                            $id=$storage->{'Drives'}->[$k]->{'@odata.id'};
                            $url_drive = "$base_url$id";
                            verb($url_drive);
                            $client->GET($url_drive);
                            if($client->responseCode() ne '200'){
                               $np->plugin_exit('UNKNOWN', "response code : " . $client->responseCode() . " Message : Error when getting drive information $id ". $client->{_res}->decoded_content );
                            }
                            $drive_rep = $client->{_res}->decoded_content;
                            $drive = from_json($drive_rep);
                            verb($drive->{'Id'}. " " .$drive->{'Status'}->{'Health'});
                            if (defined  ($drive->{'Status'}->{'Health'}) and (length ($drive->{'Status'}->{'Health'})) >= 2){
                                if (($drive->{'Status'}->{'Health'}) eq "OK") {
                                    $nb_drive_ok = $nb_drive_ok + 1 ;
                                } else {
                                    push(@criticals, "Drive " .  $drive->{'Id'} ." state is " . ($drive->{'Status'}->{'Health'}));
                                }
                            }
                           $k = $k + 1;
                        }
                        push(@ok, "$nb_drive_ok Drive  OK ");
                    }
                }
                $j = $j + 1;
                
            }
        }
        $i = $i + 1
    }
} 
$i = 0;
my %temps;
$main_url = $url_chassis;

verb("full url : $main_url");
$client->addHeader('Authorization', 'Basic ' . encode_base64("$o_login:$o_pwd"));
$client->GET($main_url);
if($client->responseCode() ne '200'){
    $np->plugin_exit('UNKNOWN', "response code : " . $client->responseCode() . " Message : Error when getting items chassis list  $main_url". $client->{_res}->decoded_content );
}
my $rep = $client->{_res}->decoded_content;
my $items = from_json($rep);
if (exists ($items->{'Members'}->[$i])){ #On ne check que le premier chassis
#while (exists ($items->{'Members'}->[$i])){
    $id = $items->{'Members'}->[$i]->{'@odata.id'};
    $url_psu = "$url$o_host:$o_port$id/Power";
    $client->GET($url_psu);
    verb($url_psu);
    if($client->responseCode() eq '200'){
        $psu_rep = $client->{_res}->decoded_content;
        $psu = from_json($psu_rep);
        verb(Dumper($psu));
        $j = 0;
        $nb_psu_ok = 0;
        while (exists ($psu->{'PowerSupplies'}->[$j])){
            if (defined  ($psu->{'PowerSupplies'}->[$j]->{'Status'}->{'Health'}) and (length ($psu->{'PowerSupplies'}->[$j]->{'Status'}->{'Health'})) >= 2) {
                if ($psu->{'PowerSupplies'}->[$j]->{'Status'}->{'Health'} eq "OK") {
                    $nb_psu_ok = $nb_psu_ok + 1;
                } else {
                    push(@criticals,  $psu->{'PowerSupplies'}->[$j]->{'Name'} ." state is " . $psu->{'PowerSupplies'}->[$j]->{'Status'}->{'Health'} );
                }
            }
            $j = $j + 1;
        }
        push(@ok, "$nb_psu_ok psu  OK ") if ($nb_psu_ok > 0);
        $j = 0;
        $psu_redundancy = 0 ;
        while (exists ($psu->{'Redundancy'}->[$j])){
            verb(Dumper($psu->{'Redundancy'}->[$j]));
            if (exists ($psu->{'Redundancy'}->[$j]->{'Status'})) {
                if (($psu->{'Redundancy'}->[$j]->{'Status'}->{'Health'} eq "OK") && ($psu->{'Redundancy'}->[$j]->{'Status'}->{'State'} eq 'Enabled') ) {
                    $psu_redundancy = $psu_redundancy + 1;
                } else {
                    push(@criticals, $psu->{'Redundancy'}->[$j]->{'Name'} ." State " . $psu->{'Redundancy'}->[$j]->{'Status'}->{'State'} . " Health " . $psu->{'Redundancy'}->[$j]->{'Status'}->{'Health'} );
                }
            }
            $j = $j + 1;
        }
        push(@ok,"Redundancy OK") if ($psu_redundancy > 0);
    }
    $url_chassis_thermal = "$url$o_host:$o_port$id/Thermal";
    verb($url_chassis_thermal);
    $client->GET($url_chassis_thermal);
    $chassis_rep = $client->{_res}->decoded_content;
    $chassis = from_json($chassis_rep);
    #verb(Dumper($chassis));
    $j = 0;
    $nb_fans_ok = 0;
    while (exists ($chassis->{'Fans'}->[$j])){
        #verb (Dumper($chassis->{'Fans'}->[$j]));
        if (defined  ($chassis->{'Fans'}->[$j]->{'Status'}->{'Health'}) and (length ($chassis->{'Fans'}->[$j]->{'Status'}->{'Health'})) >= 2) {
            if (($chassis->{'Fans'}->[$j]->{'Status'}->{'Health'}) eq 'OK'){
                $nb_fans_ok = $nb_fans_ok + 1;
            } else {
                push(@criticals, ($chassis->{'Fans'}->[$j]->{'Name'}) . " State is " . ($chassis->{'Fans'}->[$j]->{'Status'}->{'Health'}))
            }
        }
        $j = $j + 1;
    }
    push(@ok, "$nb_fans_ok Fans OK") if ($nb_fans_ok != 0);
    if ($o_temperature) {
        my @expanded_line;
        my @temp_probe;
        my @probe_not_found;
        my $probe_name;
        $j = 0;
        while (exists ($chassis->{'Temperatures'}->[$j])){
            verb($chassis->{'Temperatures'}->[$j]->{'Name'} ." ". abs(int($chassis->{'Temperatures'}->[$j]->{'ReadingCelsius'})) );
            $temps{"$chassis->{'Temperatures'}->[$j]->{'Name'}"} = abs(int($chassis->{'Temperatures'}->[$j]->{'ReadingCelsius'})); 
            $j = $j + 1;
        }
        $j = 0;
        @expanded_line = split("@",$o_temperature);
        while (exists ($expanded_line[$j])){
            @temp_probe = split(",",$expanded_line[$j]);
            if (scalar @temp_probe != 3 ){
                $np->plugin_exit('UNKNOWN', "Unable to parse temperature probe list " . $expanded_line[$j]);
            }
            $probe_name = $temp_probe[0];
            $probe_name =~ s/ /_/g;
            if (exists $temps{$temp_probe[0]}){
                if ($temp_probe[1] && $temp_probe[2]) {
                    $np->set_thresholds(warning => $temp_probe[1], critical => $temp_probe[2]);
                    $compare_status = $np->check_threshold($temps{$temp_probe[0]});
                    $np->add_perfdata(label => $probe_name, value => $temps{$temp_probe[0]}, uom => "C", warning => $temp_probe[1], critical => $temp_probe[2]);
                    if ($compare_status == 0){
                        push(@ok, $temp_probe[0]. " is ". $temps{$temp_probe[0]}.'C');
                    } else {
                        if ($compare_status == 1) {
                            push(@warnings, $temp_probe[0] . " is " . $temps{$temp_probe[0]}.'C');
                        } else {
                            push(@criticals, $temp_probe[0] . "  is " . $temps{$temp_probe[0]}.'C');
                        }
                    }
                } else {
                    $np->add_perfdata(label => $probe_name, value => $temps{$temp_probe[0]}, uom => "C");
                    push(@ok, $temp_probe[0]. " is ". abs(int($chassis->{'Temperatures'}->[$k]->{'ReadingCelsius'})).'C');
                }
            } else {
                push(@probe_not_found,$temp_probe[0]);
            }
            $j = $j + 1; 
        }
        if (scalar @probe_not_found > 0){
            $msg = join(", ", @probe_not_found) . " not found on " . $o_host . " available sensor(s) are :";
            my @keys = keys %temps;
            $msg =  $msg . join(", ", @keys);
            $np->plugin_exit('UNKNOWN', $msg);
        }
    };
    #$i = $i + 1;
}
$np->plugin_exit('CRITICAL', join(', ', @criticals)) if (scalar @criticals > 0);
$np->plugin_exit('WARNING', join(', ', @warnings)) if (scalar @warnings > 0);
$np->plugin_exit('OK', join(', ', @ok) ) if (scalar @ok > 0);
$np->plugin_exit('UNKNOWN', " Nothing to check" );
