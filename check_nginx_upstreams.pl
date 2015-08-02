#!/usr/bin/perl -w
#
# The MIT License (MIT)

# Copyright (c) 2015 Nicolas Rodriguez (nrodriguez@jbox-web.com), JBox Web (http://www.jbox-web.com)

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# $Id: $

use strict;
use warnings;

use Locale::gettext;
use File::Basename;

use POSIX qw(setlocale);
use Time::HiRes qw(time);
use POSIX qw(mktime);

use Nagios::Plugin;

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Status;

use Data::Dumper;

my $PROGNAME = basename($0);

# Use The Revision from RCS/CVS/SVN
'$Revision: 1.0 $' =~ /^.*(\d+\.\d+) \$$/;

my $VERSION = $1;
my $DEBUG   = 0;
my $TIMEOUT = 9;

setlocale(LC_MESSAGES, '');
textdomain('nagios-plugins-perl');

my $np = Nagios::Plugin->new(
  version => $VERSION,
  blurb   => _gt('Plugin to check Nginx upstreams status'),
  usage   => "Usage: %s -u <url> [-t <timeout>] [-U <username>] [-P <password>] [ -c|--critical=<threshold> ] [ -w|--warning=<threshold> ] [ -d|--debug ]",
  timeout => $TIMEOUT + 1
);

$np->add_arg (
  spec    => 'debug|d',
  help    => _gt('Debug level'),
  default => 0,
);

$np->add_arg (
  spec     => 'username|U=s',
  help     => _gt('Username for HTTP Auth'),
  required => 0,
);

$np->add_arg (
  spec     => 'password|P=s',
  help     => _gt('Password for HTTP Auth'),
  required => 0,
);

$np->add_arg (
  spec    => 'w=f',
  help    => _gt('Warning request time threshold (in seconds)'),
  default => 2,
  label   => 'FLOAT'
);

$np->add_arg (
  spec    => 'c=f',
  help    => _gt('Critical request time threshold (in seconds)'),
  default => 10,
  label   => 'FLOAT'
);

$np->add_arg (
  spec     => 'url|u=s',
  help     => _gt('URL of the Nginx csv status page.'),
  required => 1,
);

# Get params
$np->getopts;

$DEBUG = $np->opts->get('debug');
my $username = $np->opts->get('username');
my $password = $np->opts->get('password');

# Thresholds :
my $warn_t = $np->opts->get('w');
my $crit_t = $np->opts->get('c');

# Nginx URL :
my $url = $np->opts->get('url');

# Create a LWP user agent object:
my $ua = new LWP::UserAgent(
  'env_proxy' => 0,
  'timeout'   => $TIMEOUT,
);

$ua->agent(basename($0));

# Workaround for LWP bug :
$ua->parse_head(0);

if (defined($ENV{'http_proxy'})) {
  # Normal http proxy :
  $ua->proxy(['http'], $ENV{'http_proxy'});
  # Https must use Crypt::SSLeay https proxy (to use CONNECT method instead of GET)
  $ENV{'HTTPS_PROXY'} = $ENV{'http_proxy'};
}

# Build and submit an http request :
my $request = HTTP::Request->new('GET', $url);

# Authenticate if username and password are supplied
if (defined($username) && defined($password)) {
  $request->authorization_basic($username, $password);
}

# Send request and time it
my $timer = time();
my $http_response = $ua->request($request);
$timer = time() - $timer;

my $status = $np->check_threshold(
  'check'    => $timer,
  'warning'  => $warn_t,
  'critical' => $crit_t
);

$np->add_perfdata(
  'label'     => 't',
  'value'     => sprintf('%.6f', $timer),
  'min'       => 0,
  'uom'       => 's',
  'threshold' => $np->threshold()
);

if ($status > OK) {
  $np->add_message($status, sprintf(_gt("Response time degraded: %.6fs !"), $timer));
}

my $message = 'msg';

if ($http_response->is_error()) {
  my $err = $http_response->code . " " . status_message($http_response->code) . " (" . $http_response->message . ")";
  $np->add_message(CRITICAL, _gt("HTTP error: ") . $err);
} elsif (!$http_response->is_success()) {
  my $err = $http_response->code . " " . status_message($http_response->code) . " (" . $http_response->message . ")";
  $np->add_message(CRITICAL, _gt("Internal error: ") . $err);
}

($status, $message) = $np->check_messages();

if ($http_response->is_success()) {
  # Get xml content ...
  my $stats = $http_response->content;

  if ($DEBUG) {
    print "------------------===http output===------------------\n$stats\n-----------------------------------------------------\n";
    print "t=" . $timer . "s\n";
  };

  my @fields = ('index', 'upstream', 'name', 'status', 'rise', 'fall', 'type', 'port');
  my @rows = split(/\n/, $stats);

  my %stats = ();
  for (my $y = 0; $y <= $#rows; $y++) {
    my @values = split(/\,/,$rows[$y]);

    if (!defined($stats{$values[1]})) {
      $stats{$values[1]} = {};
    }

    if (!defined($stats{$values[1]}{$values[2]})) {
      $stats{$values[1]}{$values[2]} = {};
    }

    for (my $x = 3; $x <= $#values; $x++) {
      $stats{$values[1]}{$values[2]}{$fields[$x]} = $values[$x];
    }
  }

  # print Dumper(\%stats);

  my $okMsg = '';

  foreach my $pxname (keys(%stats)) {
    foreach my $svname (keys(%{$stats{$pxname}})) {
      my $svstatus = $stats{$pxname}{$svname}{'status'} eq 'up';
      if ($stats{$pxname}{$svname}{'status'} eq 'up') {
        logD(sprintf(_gt("'%s' is UP on '%s' proxy."), $svname, $pxname));
      } elsif ($stats{$pxname}{$svname}{'status'} eq 'down') {
        $np->add_message(CRITICAL, sprintf(_gt("'%s' is DOWN on '%s' proxy !"), $svname, $pxname));
      }
    }
  }

  ($status, $message) = $np->check_messages('join' => ' ');

  if ($status == OK) {
    $message = $okMsg;
  }
}


$np->nagios_exit($status, $message);


sub logD {
  print STDERR 'DEBUG:   ' . $_[0] . "\n" if ($DEBUG);
}

sub logW {
  print STDERR 'WARNING: ' . $_[0] . "\n" if ($DEBUG);
}

# Gettext wrapper
sub _gt {
  return gettext($_[0]);
}


__END__

=head1 NAME

This Nagios plugins check upstreams status provided by Nginx upstream_check_module (https://github.com/yaoweibin/nginx_upstream_check_module).

=head1 NAGIOS CONGIGURATIONS

In F<checkcommands.cfg> you have to add :

  define command {
    command_name  check_nginx_upstreams
    command_line  $USER1$/check_nginx_upstreams.pl -u $ARG1$
  }


In F<services.cfg> you just have to add something like :

  define service {
    host_name             nginx.exemple.org
    normal_check_interval 10
    retry_check_interval  5
    contact_groups        linux-admins
    service_description   Nginx
    check_command         check_nginx_upstreams!http://nginx.exemple.org/status?format=csv
  }

=head1 AUTHOR

Nicolas Rodriguez <nrodriguez@jbox-web.com>

=cut
