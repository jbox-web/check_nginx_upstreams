## check_nginx_upstreams

[![GitHub license](https://img.shields.io/github/license/jbox-web/check_nginx_upstreams.svg)](https://github.com/jbox-web/check_nginx_upstreams/blob/master/LICENSE)

This Shinken/Nagios plugin check upstreams status provided by Nginx upstream_check_module (https://github.com/yaoweibin/nginx_upstream_check_module).

## Installation

In ```checkcommands.cfg``` you have to add :

```sh
define command {
  command_name  check_nginx_upstreams
  command_line  $USER1$/check_nginx_upstreams.pl -u $ARG1$
}
```

In ```services.cfg``` you just have to add something like :

```sh
define service {
  host_name             nginx.exemple.org
  normal_check_interval 10
  retry_check_interval  5
  contact_groups        linux-admins
  service_description   Nginx
  check_command         check_nginx_upstreams!http://nginx.exemple.org/status?format=csv
}
```

## Usage

```sh
check_nginx_upstreams.pl -u <url> [-t <timeout>] [-U <username>] [-P <password>] [ -c|--critical=<threshold> ] [ -w|--warning=<threshold> ] [ -d|--debug ]
```
