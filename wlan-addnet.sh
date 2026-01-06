#!/bin/bash

# Add a new wlan cell section to wpa_supplicant.conf
# Version 1.1, gs, 20130409
# Version 1.2, gs, 20140121: allow spaces in SSID or passphrase
# Version 1.3, gs, 20140421: Translate boxes
# Version 1.4, gs, 20140731: Speed optimization for adding a new wifi connection: stop after unsuccessfully connecting to a cell with temporary wpa_supplicant and check with wpa_cli instead of iwlist whether connected or not. Refactoring: moved functions into wlan-function.sh
# Version 1.5, gs, 20141007: wlan-addnet.sh: ignore _PASSWORD_SET_ string for password, so we are a bit faster, when selecting a already configured cell
# Version 1.6, gs, 20150327: First adaptions for the new wl18xx wifi chipset
# Version 1.7, gs, 20150330: Improve support for wl18xx wifi chipset
# Version 1.8, gs, 20150417: remove whitespaces / call ifup/ifdown instead of extra code before and after testing config of new password / add special handling for wl18xx
# Version 1.9: gs, 20150420:  Fix addnet: check return code of dhclient
# Version 1.10: gs, 20150421: Fix adhoc with wl18xx /  fix wlan-addnet for already given password
# Version 1.11, gs, 20150520: wlan-addnet.sh Fix for crashing wl18 chipset: Detect when there are weired logs in dmesg and restart device before scan.
# Version 1.12, gs, 20151026: Fix for bug #4313: Check first length of essid if > 32 chars and bring message
# Version 1.13, gs, 20151203: Fix of fix of bug #4313: if ssid is too long: fake running script, so we have to touch the pid-file and remove it after a sleep.
# Version 1.14, gs, 20161111:  is_wlan_up checks no if configured, not if modules load / remove some loops / add more states in output as result of the scan
# Version 1.15, gs, 20161116: avoid resetting chipset /  speedup add password for wlan
# Version 1.16, gs, 20170125: Fix wlan with empty password function -> bring message instead of adding it for now
# Version 1.17, gs, 20180417: add select_essid_by_list and some wpa enterprise support functions, change return code of wait_for_wpa_supplicant
# Version 1.18, gs, 20241203: see bug 12809

# switch on for testing:
#set -e

# debugging
echo `date`:  $0 $1 $2 

POBINDIR=/home/plusoptix/plusoptix/program
. ${POBINDIR}/functions.sh
. ${POBINDIR}/wlan-functions.sh

# Call this to set WIFIDRIVER and WIFIMODULES variables
detect_wlan_chipset || true
# Call this to set IWLISTOUT and IWCONFIGOUT variables
detect_wlan_toolset

# debugging:
#set -xv

ESSID=
PASSWD=
LOGIN="__UNSET__"
TYPE="PSK"

parse_wlan_addnet_args "${1}" "${2}" "${3}" "${4}"
retwith=$?

PIDFILE=/var/run/wlan-addnet.pid
SETUP_LOG=/tmp/wlan-error-`date +%Y%m%d-%H%M%S`.log
echo "------- START "`date +%Y%m%d-%H%M%S`"---------" >> $SETUP_LOG
MSGTXTFILE=/tmp/wlan-addnet-msg.txt


if [ ${retwith} == 0 ] && [ ! -f $PIDFILE ]; then
    echo $$ > $PIDFILE
    # DEBUGGING
    if [ ${TYPE} == "PSK" ] ; then 
	echo "PSK \"${ESSID}\" \"${PASSWD}\" "
    elif [ ${TYPE} == "SAE" ] ; then
	echo "SAE \"${ESSID}\" \"${PASSWD}\" "
    elif [ ${TYPE} == "EAP" ] ; then
	echo "EAP \"${ESSID}\" \"${PASSWD}\" \"${LOGIN}\""
    fi
    # END DEBUGGING
    if test_new_wpa_pw "${ESSID}" "${PASSWD}" "${LOGIN}" "${TYPE}" >> $SETUP_LOG
    then
  	debugout "Carrier is up"
        ${prgdir}/wfd_hook wlan0
	echo "SUCCESS - connected to ${ESSID}" > ${MSGTXTFILE}
    else
	echo "wpa_supplicant failed: `wpa_cli_status_cmd`" >> $SETUP_LOG 	
	do_error_log  $SETUP_LOG > ${MSGTXTFILE}
	retwith=1
    fi 
    rm $PIDFILE
elif [ -f ${PIDFILE} ]; then
    if ! ps --pid $(cat $PIDFILE) -o pid=,comm=
    then
 	echo "Please try again" > ${MSGTXTFILE}
 	echo "Last setup was aborted" >> ${MSGTXTFILE}
 	echo "Please note: " >> ${MSGTXTFILE}
 	echo "Do not remove the USB drive while the setup is running." >> ${MSGTXTFILE}
	rm $PIDFILE
	retwith=6
    else
	echo Another instance of this script still running, doing nothing. >> ${MSGTXTFILE}
	retwith=7
    fi
elif [ ${retwith} == 2 ]; then
    echo "Parameter missing: 1: ${ESSID}, 2: ${PASSWD} . aborting!" > ${MSGTXTFILE}
    sleep 4
elif [ ${retwith} == 3 ]; then
    echo "WLAN network with empty password not supported. Ignoring..." > ${MSGTXTFILE}
    sleep 4
elif [ ${retwith} == 4 ]; then
    echo "WLAN connection failed. " > ${MSGTXTFILE}
    echo "WLAN passphrase with ${#PASSWD} characters too short."  >> ${MSGTXTFILE}
    echo "Please provide a password with at least 8 characters." >> ${MSGTXTFILE}
    sleep 4
elif [ ${retwith} == 5 ]; then
    echo "WLAN connection failed."  > ${MSGTXTFILE}
    echo "ESSID / WLAN name:" >> ${MSGTXTFILE}
    echo "${ESSID}" >> ${MSGTXTFILE}
    echo "must not exceed 31 characters, but has length ${#ESSID}" >> ${MSGTXTFILE}
    sleep 4
elif [ ${retwith} == 10 ]; then
    echo "update ESSID ${ESSID}"
    update_existing_passwd_in_wpa_supplicant "${ESSID}" "${TYPE}"
    network_stop
    /etc/init.d/networking start
    wait_for_ip_no_restart_dhcp
    ${prgdir}/wfd_hook wlan0
    retwith=0
elif [ ${retwith} == 11 ]; then
    echo "remove all ESSIDs from cfg and restart network"
    network_stop
    head -9 /etc/wpa_supplicant_po.conf > /tmp/wpac
    mv /tmp/wpac /etc/wpa_supplicant_po.conf
    /etc/init.d/networking start
    #ip address flush wlan0
    retwith=0
else
    echo "$0 uncatched case"
    retwith=1
fi


if [ $retwith -ge 3 ] &&  [ $retwith -le 5 ]
then
	PoDialog --no-cancel --textbox ${MSGTXTFILE} -1 -1 & 
fi

if [ $retwith -gt 1 ]
then
   #ignore error state (1), that will be shown as icon at the gui.
   debugout "`cat $SETUP_LOG`"
   echo "return value: $retwith" >> ${MSGTXTFILE}
fi
cat ${MSGTXTFILE} >> $SETUP_LOG

# At the moment we cannot handle non-0 values in our software, so don't exit with $retwith !
exit 0 

