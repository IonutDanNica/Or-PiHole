#!/bin/bash

# Packages needed for the script to work:
#sudo apt-get install telnet nmap

#Variables that need to be available in the conf script: 
#DNS_SERVER_WANTED=
#ORBI_USR=
#ORBI_PWD=
#ORPI_IP=

COOKIE_FILE=/tmp/orbi.cookies
SH_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
SH="$(basename $0)"
CONF=$SH_PATH/.${SH/.sh/.conf}

#Functions start
function log () {
  echo `date +[%Y-%m-%d" "%H:%M:%S" "%:z]`" - $1"
}

function log_error_and_exit () {
  log "$1 - Exiting"
  exit 1
}

function check_return_code () {
  if [ $? -ne 0 ]
  then
    log_error_and_exit "$1"
  fi
}

function get_dns () {
  log "Checking the dns server reported by dhcp server"
  OUTPUT=$(sudo nmap -sU -p 67 --script=dhcp-discover $ORPI_IP)
  check_return_code "Error getting namp info"

  DHCP_DNS=$(echo "$OUTPUT" | grep "Domain Name Server" | awk {'print $5'})
  log "DNS returned by DHCP server is $DHCP_DNS"
}

function change_telnet () {
  log "Making login request to get ts var"
  OUTPUT=$(wget -q --user "$ORBI_USR" --password "$ORBI_PWD"  http://$ORPI_IP/debug_detail.htm --save-cookies=$COOKIE_FILE --keep-session-cookies -O-)
  check_return_code "Something wrong in getting ts variable from ORBI. Ouptut was: $OUTPUT"

  ts=$(echo "$OUTPUT" | grep "^var ts" | sed 's/var ts="\(.*\)";/\1/g')
  re='^[0-9]+$'
  if ! [[ "$ts" =~ $re ]]
  then
    log_error_and_exit "ts variable is not number"
  fi
  log "Making API call and changing enable-telnet=$1"
  OUTPUT=$(wget -q --user "$ORBI_USR" --password "$ORBI_PWD" --post-data "ts_name=debug_info&enable-telnet=$1&rpc_name=debug-info" "http://$ORPI_IP/rpc.cgi?%20timestamp=$ts" -O-)
  check_return_code "Error while enabling telnet on ORBI"
}
#Functions end

if [ -f $CONF ]
then
  source $CONF
else
  log_error_and_exit "CRITICAL FAILURE: Conf file $CONF does not exit."
fi

[ -z "$ORBI_USR" ] && log_error_and_exit "CRITICAL FAILURE: ORBI_USR variable not defined in conf file"
[ -z "$ORBI_PWD" ] && log_error_and_exit "CRITICAL FAILURE: ORBI_PWD variable not defined in conf file"
[ -z "$ORPI_IP" ] && log_error_and_exit "CRITICAL FAILURE: ORPI_IP variable not defined in conf file"
[ -z "$DNS_SERVER_WANTED" ] && log_error_and_exit "CRITICAL FAILURE: DNS_SERVER_WANTED variable not defined in conf file"

log "Starting script execution"

if [ $(crontab -l | grep "$SH_PATH/$SH" -c) -gt 0 ]
then
  log "Already added to cron"
else
  crontab -l | { cat; echo "0 * * * * $SH_PATH/$SH"; } | crontab -
  log "Added script to cron"
fi

if [ $(ip addr | grep -c "inet 192.168.") -eq 0 ]
then
  log_error_and_exit "Host does not have valid ip"
fi

get_dns
if [ "$DHCP_DNS" = "$DNS_SERVER_WANTED" ]
then
  log "DNS server is ok. Nothing to do."
  exit 0
fi

log "Enabling telnet on ORBI"
change_telnet 1

(echo "open $ORPI_IP"
sleep 1
echo "$ORBI_USR"
sleep 1
echo "$ORBI_PWD"
sleep 1
echo "sed -i 's/"option dns "$lan_ip/"option dns "${DNS_SERVER_WANTED}/g' /etc/init.d/dhcpd.init"
sleep 1
echo '/etc/init.d/dhcpd.init reload'
sleep 1
echo 'grep "option dns" /tmp/udhcpd.conf'
sleep 1
echo exit) | telnet $ORPI_IP

get_dns
if [ "$DHCP_DNS" = "$DNS_SERVER_WANTED" ]
then
  log "DNS server is ok. Nothing to do."
fi

log "Disabling telnet on ORBI"
change_telnet 0

log "Execution finished"
