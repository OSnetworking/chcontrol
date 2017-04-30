#!/usr/bin/perl

#
# ============================== SUMMARY =====================================
#
# Program   : notify_sms.pl
# Version   : 1.2
# Date      : 22 Oct 2015
# Author    : Rex Wickham / TwentytwentyMedia Ltd
# Copyright : TwentytwentyMedia Ltd 2014 All rights reserved.
# Based on work by    : Martin Steel / Mediaburst Ltd
# Based on work by    : Mediaburst Ltd 2012 All rights reserved.
# Summary   : This plugin sends SMS alerts through the Nexmo SMS API
# License   : ISC
#
# =========================== PROGRAM LICENSE =================================
#
# Copyright (c) TwentytwentyMedia Ltd 2014 <hello@2020media.com>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
# ============================= MORE INFO ======================================
# 
# As released this plugin requires a Nexmo account to send text
# messages.  To setup a Nexmo account visit:
#   http://www.nexmo.com
#
#
# ============================= SETUP NOTES ====================================
# 
# Copy this file to your Nagios plugin folder
# On a Centos install this is typically /usr/lib/nagios/libexec (32 bit) 
# or /usr/lib64/nagios/libexec (64 bit) other distributions may vary.
# Make sure you have SSL enabled. Run this otherwise:
# perl -MCPAN -e 'install Crypt::SSLeay'
# Testing. From the command line in the plugin folder run:
# ./notify-sms.pl -k yourkey -s yoursecret -t yournumber -f Nagios -m "bodge"
# replacing yourkey, yoursecret and yournumber with the appropriate values.
# 
#
# NAGIOS SETUP
#
# 1. Create the SMS notification commands.  (Commonly found in commands.cfg)
#    Don't forget to add your Nexmo API Key and Secret. These can be placed 
#    in your commands instead of the API_KEY and API_SECRET given below
#    -f Nagios - you can change Nagios to a different "from" if you want.
#
# define command{
#       command_name    service-notify-by-sms
#       command_line    $USER1$/notify_sms.pl -k API_KEY -s API_SECRET -t $CONTACTPAGER$ -f Nagios -m "Service: $SERVICEDESC$\\nHost: $HOSTNAME$\\nAddress: $HOSTADDRESS$\\nState: $SERVICESTATE$\\nInfo: $SERVICEOUTPUT$\\nDate: $LONGDATETIME$"
# }
#
# define command{
#       command_name    host-notify-by-sms
#       command_line    $USER1$/notify_sms.pl -k API_KEY -s API_SECRET -t $CONTACTPAGER$ -f Nagios -m "Host $HOSTNAME$ is $HOSTSTATE$\\nInfo: $HOSTOUTPUT$\\nTime: $LONGDATETIME$"
# }
#
# 2. In your nagios contacts (Commonly found on contacts.cfg) add 
#    the SMS notification commands:
#
#    service_notification_commands      service-notify-by-sms
#    host_notification_commands         host-notify-by-sms
#
# 3. Add a pager number to your contacts, make sure it has the international 
#    prefix, e.g. 44 for UK or 1 for USA, without a leading 00 or +.
#
#    pager      447700900000  
#


use strict;
use Getopt::Long;
use LWP;
use URI::Escape;

my $version = '1.0';
my $verbose = undef; # Turn on verbose output
my $key = undef;
my $secret = undef;
my $to = undef;
my $from = "Nagios";
my $message = undef;

sub print_version { print "$0: version $version\n"; exit(1); };
sub verb { my $t=shift; print "VERBOSE: ",$t,"\n" if defined($verbose) ; }
sub print_usage {
        print "Usage: $0 [-v] -k <key> -t <to> [-f <from>] -m <message>\n";
}

sub help {
        print "\nNotify by SMS Plugin ", $version, "\n";
        print " Nexmo - http://www.nexmo.com/\n\n";
        print_usage();
        print <<EOD;
-h, --help
        print this help message
-V, --version
        print version
-v, --verbose
        print extra debugging information
-k, --key=KEY
        Nexmo API Key
-s, --secret=SECRET
        Nexmo API Secret
-t, --to=TO
        mobile number to send SMS to in international format
-f, --from=FROM (Optional)
        string to send from (max 11 chars)
-m, --message=MESSAGE
        content of the text message
EOD
        exit(1);
}

sub check_options {
        Getopt::Long::Configure ("bundling");
        GetOptions(
                'v'     => \$verbose,           'verbose'       => \$verbose,
                'V'     => \&print_version,     'version'       => \&print_version,
                'h'     => \&help,              'help'          => \&help,
                'k=s'   => \$key,               'key=s'         => \$key,
                's=s'   => \$secret,            'secret=s'      => \$secret,
                't=s'   => \$to,                'to=s'          => \$to,
                'f=s'   => \$from,              'from=s'        => \$from,
                'm=s'   => \$message,           'message=s'     => \$message
        );

        if (!defined($key))
                { print "ERROR: No API Key defined!\n"; print_usage(); exit(1); }
        if (!defined($secret))
                { print "ERROR: No API Secret defined!\n"; print_usage(); exit(1); }
        if (!defined($to))
                { print "ERROR: No to defined!\n"; print_usage(); exit(1); }
        if (!defined($message))
                { print "ERROR: No message defined!\n"; print_usage(); exit(1); }

        if($to!~/^\d{7,15}$/) {
                { print "ERROR: Invalid to number!\n"; print_usage(); exit(1); }
        }
        verb "key = $key";
        verb "secret = $secret";
        verb "to = $to";
        verb "from = $from";
        verb "message = $message";
}

sub SendSMS {
        my $key = shift;
        my $secret = shift;
        my $to = shift;
        my $from = shift;
        my $message = shift;

        # Convert "\n" to real newlines (Nagios seems to eat newlines).
        $message=~s/\\n/\n/g;

        # URL Encode parameters before making the HTTP POST
        $key        = uri_escape($key);
        $secret     = uri_escape($secret);
        $to         = uri_escape($to);
        $from       = uri_escape($from);
        $message    = uri_escape($message);

        my $result;
        my $server = 'https://rest.nexmo.com/sms/json';
        my $post = 'api_key=' . $key;
        $post .= '&api_secret='.$secret;
        $post .= '&to='.$to;
        $post .= '&from='.$from;
        $post .= '&text='.$message;

        verb("Post Data: ".$post);

        my $ua = LWP::UserAgent->new();
        $ua->timeout(30);
        $ua->agent('Nagios-SMS-Plugin/'.$version);
        my $req = HTTP::Request->new('POST',$server);
        $req->content_type('application/x-www-form-urlencoded');
        $req->content($post);
        my $res = $ua->request($req);

        verb("POST Status: ".$res->status_line);
        verb("POST Response: ".$res->content);

        if($res->is_success) {
                if($res->content=~/error/i) {
                        print $res->content;
                        $result = 1;
                } else {
                        $result = 0;
                }
        } else {
                $result = 1;
                print $res->status_line;
        }

        return $result;
}


check_options();
my $send_result = SendSMS($key, $secret, $to, $from, $message);

exit($send_result);
