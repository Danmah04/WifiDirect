#!/bin/bash
# Container with some functions for wlan 
# Version 1.0 gs, simple init version
# Version 1.1 gs, 2015-03-27: added some functions from wlan-scan.sh, add wl18xx / iw utils / nl80211 

. /home/plusoptix/plusoptix/program/functions.sh
. /home/plusoptix/plusoptix/program/pathhandler.sh

setPdfDevice

# Some variables
WPA_CONF=/etc/wpa_supplicant_po.conf
WPA_TEMP_CONF=/tmp/wpa_supplicant_temp.conf
WPA_TEMP_LOG=/tmp/wpa_supplicant_temp.log
WPA_DUP_CONF=/tmp/wpa_supplicant_rm_duplicate.conf
WPA_OUT=/tmp/wpa-out
NL80211=0
WLANINTERFACENAME="wlan0"
NL80211_SYSFS=/sys/class/net/${WLANINTERFACENAME}/phy80211/
WIFIDRIVER=
WIFIMODULES=
MODPARAMETERS=
BOARDREVISION="G"
OURNET=
CURRENT_NW_IF=lo
XDIALOG_INPUT=/tmp/xdialog_input
REVISION_DISTINCTION_FILE=/home/plusoptix/plusoptix/data/module-revision

# Switch on debugging...
DEBUG=0
#set -x 
#set -v

# small helper for debug output
function debugout () {
    if [[ $DEBUG == 1 ]]
    then
	echo "$@"
    fi
}


# Detect which interface we are using
# Needs a call of detect_wlan_chipset before for correct ${WLANINTERFACENAME}
function detect_wlan_toolset () {
    if [ -f /usr/sbin/iw ]; 
    then 
	IWLISTOUT=/tmp/iw-scan
	IWCONFIGOUT=/tmp/iw-link
	CELL_STATUS_CMD="iw dev ${WLANINTERFACENAME} link"
	LIST_CMD="iw dev ${WLANINTERFACENAME} scan"
	NL80211=1
	debugout iw utils
    else
	IWLISTOUT=/tmp/iwlist-scan
	IWCONFIGOUT=/tmp/iwconfig-out
	CELL_STATUS_CMD="iwconfig ${WLANINTERFACENAME}"
	LIST_CMD="iwlist ${WLANINTERFACENAME} scanning"
	debugout wireless extension
    fi 
}
# Detect which chipset and which driver we need.
# returns 0 if could be detected, > 0 else
function detect_wlan_chipset () {
    ret=0
    # original 
    #IGEPHW=`dmesg | grep "IGEP3: Hardware Rev." `
    # see bug #4004: 
    hwrevfile=/var/earlyboot/hardware-revision
    if [ -f ${hwrevfile} ]
    then
	IGEPHW=`cat ${hwrevfile}`
    else
	if ! isUpdateMode; then 
	    PoDialog --msgbox "Breadcrumbs not up-to-date! ${hwrevfile} missing" 0 0 &
	fi
	ret=1
    fi
    if [ "`echo ${IGEPHW} | grep "Rev. E"`" ]
    then
	#WIFIDRIVER="wext" # old libertas module
	WIFIMODULES="libertas_sdio libertas"
	MODPARAMETERS=
	WIFIDRIVER="nl80211" # new libertas module
	#WIFIMODULES="libertas_tf_sdio libertas_tf"
	BOARDREVISION="E"
    elif [ "`echo ${IGEPHW} | grep "Rev. G"`" ]
    then
	[[ -f ${REVISION_DISTINCTION_FILE} ]] && IGEP_REV_GH=$(cat ${REVISION_DISTINCTION_FILE})
	
	if [[ ${IGEP_REV_GH} == "Rev. H" ]]; then
	    WIFIDRIVER="nl80211"
	    WIFIMODULES="moal"
	    MODPARAMETERS="mod_para=nxp/wifi_mod_para_sd8987.conf"
	    BOARDREVISION="H"
	else
	    WIFIDRIVER="nl80211"
	    WIFIMODULES="wlcore_sdio wl18xx"
	    MODPARAMETERS=
	    BOARDREVISION="G"
	fi
    elif [ "`echo ${IGEPHW} | grep "FireSTORM-y"`" ]
    then
	WIFIDRIVER="nl80211"
	WIFIMODULES="wlcore_sdio wl18xx"
	MODPARAMETERS=
	BOARDREVISION="G"
    elif [ "`echo ${IGEPHW} | grep "Raspberry"`" ]
    then
	WIFIDRIVER="nl80211"
	WIFIMODULES="brcmfmac"
	MODPARAMETERS=
	BOARDREVISION="RPI10"
    else
	#PoDialog --msgbox "Hardware detection failed! Assuming Revision E (libertas)" 0 0 &
	hwdetlogfile=${HOME}/plusoptix/log/wlan-hw-detection-failed-`date +%Y%m%d-%H%M`.log
	echo "Hardware detection failed! Assuming Revision E (libertas)" >> ${hwdetlogfile}
	dmesg | grep IGEP >>  ${hwdetlogfile}
	## For testing with "old" kernel, later set to libertas!
	WIFIDRIVER="nl80211"
	#WIFIMODULES="wlcore_sdio wl18xx"
	#BOARDREVISION="G"
	#WIFIDRIVER="wext"
	MODPARAMETERS=""
	WIFIMODULES="libertas_sdio libertas"
	BOARDREVISION="E"
	ret=2
    fi
    debugout detect_wlan_chipset returns with $ret
    return $ret
}
# Get in which mode we are and return 
# 0 if not connected
# 1 if managed
# 2 if ad hoc
function get_mode () {
    if [ -z ${OURNET} ]
    then
	return 0
    elif [ "$OURNET" != "zebra" ]
    then
	# managed
	return 1
    elif [ "$OURNET" == "zebra" ]
    then
	# ad-hoc / zebra
	return 2
    else
	# else
	return 0
    fi
}
# Detect which device is configured
function detect_current_nw_if ()  {
    detect_wlan_chipset
    DEVS="eth0 ${WLANINTERFACENAME}"
    for if in $DEVS
    do
	if  grep "iface $if"  /etc/network/interfaces >/dev/null
	then 
	    CURRENT_NW_IF=$if
	    return 0
	fi
    done
    return 1
}
# Small helper to get if we have an IP
# Return 0 if not, else 1
function is_carrier_up () {
    if detect_current_nw_if
    then
    #if [ ! -z "`ifconfig| grep ${CURRENT_NW_IF} -A 1 | grep "inet addr:"`" ]
	if [ ! -z "`ip link show ${CURRENT_NW_IF}|grep "NO-CARRIER"`" ]
	then
  	    debugout is_carrier_up: NO-CARRIER 
	    return 1
	elif [ ! -z "`ip link show ${CURRENT_NW_IF}|grep "UP"`" ]
	then
	    debugout is_carrier_up: LINK UP 
	    return 0
	else
	    debugout is_carrier_up: UNDEFINED  	
	    return 2
	fi
    else
	debugout is_carrier_up No network device configured
	return 3
    fi
}
# Helper to detect, if we have an IP already (returns true) or not (false) and echos IP (so you can do a ip=`have_ip`)
function have_ip () {
    if detect_current_nw_if
    then
	ip="`ifconfig ${CURRENT_NW_IF} | grep "inet addr"|cut -d ":" -f 2| cut -d " " -f 1`" 
	if [ $? ]
	then
	    if [ ! -z "${ip}" ]
	    then
		echo $ip
		return 0
	    else
		return 1
	    fi
	else
	    return 3
	fi
    else
	return 2
    fi
}

function static_ip () {
    if [ -f /etc/network/static_ip.conf ]
    then
	return 0
    else
	return 1
    fi
}
# Wrap wpa_cli status command
# wpa_cli cannot run without wpa_supplicant
# So check if that service is running
function wpa_cli_status_cmd () {
    detect_wlan_chipset
    if ! wpa_cli -i${WLANINTERFACENAME} status 2>/dev/null
    then
	local RV=$?
	if ! ps -C "wpa_supplicant" -o pid=
	then
	    echo "INTERNAL ERROR: interface not ready, ret=$RV, maybe wpa_supplicant not running"
	    echo " wpa_state=WPA_SUPPLICANT_NOT_RUNNING"
	    return 1
	else
	    echo "INTERNAL ERROR: interface not ready - wpa_cli failed with $RV"
	    echo "wpa_state=WPA_CLI_ERROR"
	    return 2
	fi
    else
	return 0
    fi
}
# Is called by the settingsManualIP widget to set a static ip or dhcp while device running.
function restart_dhcp () {
    if detect_current_nw_if
    then
	#echo "++   Restart dhcpcd on ${CURRENT_NW_IF}   ++" 
	if ! static_ip 
	then
	    if  ip address show dev ${CURRENT_NW_IF} | grep inet | grep -v dynamic; then
		echo cleanup left over static addresses
		ip address flush ${CURRENT_NW_IF}
	    fi
	    dhcpcd ${CURRENT_NW_IF} || dhcpcd -N ${CURRENT_NW_IF} 
	else
	    static_ip_setup
	fi
	return 0
    else
	return 1
    fi
}


function static_ip_setup () {
    if detect_current_nw_if
    then
	#echo "++   Restart dhcpcd on ${CURRENT_NW_IF}   ++" 
	if static_ip ; 	then
            if  ip address show dev ${CURRENT_NW_IF} | grep inet | grep dynamic; then 
                echo cleanup left over dynamic addresses
		retries=0
		while ! dhcpcd -kw ${CURRENT_NW_IF} && [ ${retries} -lt 10 ] ; do
		    sleep 1;
		    ((retries++));
		    echo "Tried $retries to finish dhcpcd unsuccessfully";
		done
                ip address flush ${CURRENT_NW_IF}
            fi     
	    address=$(grep address /etc/network/static_ip.conf| cut -f 2 -d " ")
	    netmask=$(grep netmask /etc/network/static_ip.conf| cut -f 2 -d " ")
	    gateway=$(grep gateway /etc/network/static_ip.conf| cut -f 2 -d " ")
	    dns=$(grep dns- /etc/network/static_ip.conf| cut -f 2 -d " ")
	    ifconfig ${CURRENT_NW_IF} $address netmask $netmask 
	    route del default
	    route add default gw $gateway ${CURRENT_NW_IF}
	    echo "domain plusoptix.local" > /etc/resolv.conf
	    echo "search plusoptix.local" >> /etc/resolv.conf
	    echo "nameserver $dns" >> /etc/resolv.conf
	fi
	return 0
    else
	return 1
    fi


}
# Beginning with yocto 4.1 ifupdown scripts do not shutdown network devices correctly
# To fix this, we shutdown manually
# This method may become obsolete, in the case the scripts will be fixed. 
function force_shutdown_network (){
    local IF=${CURRENT_NW_IF}
    if [ ! -z $1 ]; then IF=$1; fi
    dhcpcd -x || killall dhcpcd || true
    killall wpa_supplicant || true
    ifconfig ${IF} down       
    ip address flush dev ${IF}
}
# Wrapper for /etc/init.d/networking stop
function network_stop () {
    /etc/init.d/networking stop
    if detect_current_nw_if; then
	force_shutdown_network ${CURRENT_NW_IF}
    fi
}

# Adjust the config file for networking and make the change persistant.
# Is called by the settingsManualIP widget when setting static ip or dhcp. 
function modify_interfaces_static_dhcp () {
    IF_FILE=/etc/network/interfaces
    STATIC_CONF=/etc/network/static_ip.conf
    
    if static_ip ; then
        grep "address\|nameserver\|netmask\|gateway" ${IF_FILE} > ${IF_FILE}_bak
        if  ! grep "iface.*inet static" ${IF_FILE}; then
           mv ${IF_FILE} ${IF_FILE}_bak
           sed -i s/"iface\(.*\)inet dhcp"/"iface\1inet static"/ ${IF_FILE}_bak
           grep -v "^$" ${IF_FILE}_bak > ${IF_FILE}
           cat ${STATIC_CONF} >> ${IF_FILE}
           rm ${IF_FILE}_bak
           echo "$0 Switch from dhcp to static - $MODE - $METHOD - $IFACE"
        elif ! diff ${STATIC_CONF} ${IF_FILE}_bak; then
	   grep -v "address\|nameserver\|netmask\|gateway" ${IF_FILE} > ${IF_FILE}_bak
	   grep -v "^$" ${IF_FILE}_bak > ${IF_FILE} 
  	   cat ${STATIC_CONF} >> ${IF_FILE}
	   rm ${IF_FILE}_bak
	   echo "$0 Updated static setup - $MODE - $METHOD - $IFACE"
        else 
           echo "$0 nothing to do - static config changed but to the same values"
        fi
    elif ! static_ip && grep "iface.*inet static" ${IF_FILE}; then
        grep -v "address\|nameserver\|netmask\|gateway" ${IF_FILE} > ${IF_FILE}_bak  
        sed -i s/"iface\(.*\)inet static"/"iface\1inet dhcp"/ ${IF_FILE}_bak
        mv ${IF_FILE}_bak ${IF_FILE} 
        echo "$0 Switch from static to dhcp - $MODE - $METHOD - $IFACE"
	#else
        #echo "$0 nothing to do (default)"
    fi
}

# Check if we have an IP. On init, dhclient takes a while, so we have
# to wait, else we get an warning sign of no network
function wait_for_ip () {
     try=0
     if have_ip 
     then
	 return 0
     else
	 restart_dhcp
	 sleep 1
	 while [ ${try} -lt 30 ] && ! have_ip
	 do
	     sleep 0.5
	     ((try++))
	     if have_ip
	     then
		 return 0
	     fi
	 done
     fi
     return $try
}
# Same as wait_for_ip, but without restart dhcp
function wait_for_ip_no_restart_dhcp () {
   try=0
   if detect_current_nw_if && [ ${CURRENT_NW_IF} == "wlan0" ] &&  configured_cells ; then
      echo "Unconfigured wlan - do not wait for ip"
   else 
	   while ! have_ip && [ $try -lt 30 ]	
	   do 
	       debugout "Waiting for IP - try $try"
	       sleep 0.5
	       ((try++))
	   done
	   have_ip
	fi	
}
function wait_for_carrier () {
    local try=0
    while ! is_carrier_up && [ $try -lt 10 ]; do  
       echo "Waiting for carrier...($try)" 
       wpa_cli_status_cmd
       sleep 1                                    
       ((try++))                                         
    done
    is_carrier_up 
}


# Short cut for reset the wlan chip 
# return true (0) if successfull, else false
function reset_wlan_chip () {
    if is_wlan_up && [ ${BOARDREVISION} == "G" ] 
    then
	if [ -e /sys/class/gpio/gpio139/value ]
	then
            echo 0 > /sys/class/gpio/gpio139/value
	    echo 1 > /sys/class/gpio/gpio139/value
	    return 0
	else
	    debugout "reset_wlan_chip(): Unable to find gpio, unimplemented in kernel v4.x"
	    return 1
	fi
    else
	debugout "WLAN down or not Board revision G"
	return 2
    fi
}
# see bug #7918 - we have to switch to an old wpa_supplicant version for rev. E devices. 
function fix_wpa_supplicant_version () {
  if [ ${BOARDREVISION} == "E" ]
  then                                            
      wpa_supp_fn=`which wpa_supplicant`
      if [ ! -h ${wpa_supp_fn} ] && [ -f ${wpa_supp_fn}26 ]
      then                                                 
	  echo "fix_wpa_supplicant_version: fixing for rev: ${BOARDREVISION} " 
   	  mv ${wpa_supp_fn} ${wpa_supp_fn}_default                
   	  ln -s ${wpa_supp_fn}26 ${wpa_supp_fn}                   
      elif [ ! -h ${wpa_supp_fn} ] && [ ! -f ${wpa_supp_fn}26 ]
      then                                                                        
   	  PoDialog --msgbox "Failed to set wpa_supplicant,\n version 2.6 as default because of missing file."  0 0 &
      #else	
	 #echo "fix_wpa_supplicant_version: Nothing to do - link already set."
      fi
  #else
      #echo "fix_wpa_supplicant_version: Not a Rev E device (${BOARDREVISION})"                                                                                                     
  fi 
}

# We need to reset the WiFi chipset data for some misdetected Komitec modules (see Bug #10794)
function reset_revision_data () {
    rm ${REVISION_DISTINCTION_FILE}
    rmmod ${WIFIMODULES}
    /etc/init.d/wlan_revision_distinction.sh start
    sleep 2
    prestart_network ${WLANINTERFACENAME}
}

# Before calling start_network_managed or _adhoc call prestart_network
# to load drivers
function prestart_network () {
    IFACE=$1
    if [ ! -z $IFACE ]
    then
	detect_wlan_chipset
	if [ $IFACE == "${WLANINTERFACENAME}" ] 
	then
	    alreadyload=0
	    for m in ${WIFIMODULES}
	    do
		if [ -z "`lsmod | grep $m`" ]
		then
		    modprobe $m ${MODPARAMETERS}
		    let loaddrivers=$loaddrivers+1
		    # We have to reset wrong detected module revision (see Bug #10794)
		    if  ([[ ${BOARDREVISION} == "G" ]] || [[ ${BOARDREVISION} == "H" ]]) && [[ ${loaddrivers} -le 1 ]]  && ! ifconfig ${WLANINTERFACENAME}; then
			reset_revision_data
			return 0
		    fi
		fi
	    done
	    if [ ${BOARDREVISION} == "G" ]
	    then
		sleep 2
		reset_wlan_chip
	    elif [ ${BOARDREVISION} == "E" ]
	    then
		fix_wpa_supplicant_version
		try=0
		ifconfig ${WLANINTERFACENAME}         
		while [ $? != 0 ] && [ $try -lt 100 ]
		do                                  
		    debugout Device still not ready, waiting...
		    sleep 0.2
		    let try=${try}+1
		    ifconfig ${WLANINTERFACENAME}
		done 
	    fi
	    debugout prestart_network: Have to reload drivers: $alreadyload : ${WIFIMODULES}
	elif [ $IFACE == "eth0" ]
	then
	    # Pin mac address to smsc95xx chip on first run
	    if isX16 ;then
		if [ ! -f /etc/network/mac_eth0 ]
  		then
		    MAC=$(ifconfig eth0 | grep HWaddr | awk '{print $5}')
		    if [ ! -z "${MAC}" ]
		    then
			echo "${MAC}" > /etc/network/mac_eth0
		    fi
		fi
		if [ -f /etc/network/mac_eth0 ] && [ ! -z "$(cat /etc/network/mac_eth0)" ] && ! ifconfig eth0 | grep HWaddr | grep "$(cat /etc/network/mac_eth0)"
		then
		    echo "Set MAC address to $(cat /etc/network/mac_eth0)"
		    ifconfig $IFACE down 
		    ifconfig $IFACE hw ether $(cat /etc/network/mac_eth0)
		fi
		ip link set $IFACE up
		ip address flush $IFACE
		if [ ! -b ${USBBOOTDEV} ]; then
		    # see bug 9263 - in the case no usb drive is connected, we have to asure, the samba service is started.
 		    sleep 3
		fi
		# makes no sense here: module is built-in: 
		#modprobe smsc95xx || true
	    fi
	fi
    fi
}
# Cleanup all possible leftover dhcp clients and wpa_supplicant before restart
function cleanup_network_managed () {
    detect_wlan_chipset
    #PIDFILES="/var/run/dhclient.pid /var/run/udhcpc.${WLANINTERFACENAME}.pid"
    #TOKILL="dhclient udhcpc"
    PIDFILES="/var/run/udhcpc.${WLANINTERFACENAME}.pid"
    TOKILL="udhcpc"
    if [ x$1 == "xALL" ]
    then
	PIDFILES="$PIDFILES /var/run/wpa_supplicant*.pid /var/run/dhcpcd/*.pid /var/run/wpa_supplicant_${WLANINTERFACENAME}_temp"
        TOKILL="$TOKILL wpa_supplicant dhcpcd"
        debugout "cleanup: kill $TOKILL"
    fi
    for p in $PIDFILES
    do
        if [ -f $p ]
        then
	    if echo $p | grep "dhcpcd"; then
		dhcpcd -x
	    else
		kill `cat $p`
	    fi
	    debugout cleanup: Killing $p by pid
        fi
    done
    for tk in $TOKILL
    do
        if ps -C $tk > /dev/null
        then
	    if [ $tk == "dhcpcd" ]; then
		$tk -x || true
	    else
		killall  $tk
	    fi
	    debugout cleanup: Killing $tk by name
        fi
    done 
    rm -f $PIDFILES 
}

# Manipulate the avahi service file according our sn, version and product
function modifyAvahiConf () {
    if [ -f /etc/init.d/avahi-daemon ]
    then	
	CFGFILE=/home/plusoptix/plusoptix/program/PlusoptixQtDesktopGui.cfg
	AVAHI_SERVICE_FILE=/etc/avahi/services/plusoptix.service
	
	COLUMNSEP=$(grep CSVColumnSeparator ${CFGFILE}  |cut -f 2 -d "=")
        #VERSION=$(bash /etc/versions/analyze.sh | head -1 | cut -d " " -f 3)
	VERSION=$(cat /etc/versions/analyze.sh|head -1 | cut -d " " -f 4)
	PORT=$(grep "shmport" `dirname ${CFGFILE}`/Analyze30.cfg | cut -f 2 -d "=")
	if [ -z ${PORT} ]
	then
            echo use default port 8888
            PORT=8888
	fi
	if [ -f ${po_serial_file} ]
	then
            PRODUCT=$(grep "Product" ${po_serial_file} | cut -d " " -f 2 | cut -c 1-2)
            SN=$(grep "Device-ID" ${po_serial_file} | cut -d " " -f 2)
	else
            if isX16
            then
    		PRODUCT=16
            elif isX12; then
    		PRODUCT=12
	    elif isOpti || isX18 || isX20; then
		PRODUCT=20
            fi
            SN=$(cat /etc/hostname|cut -f 2 -d "-")
	fi
	
	if [ -f ${AVAHI_SERVICE_FILE} ]
	then
            tmpfile=/tmp/`basename ${AVAHI_SERVICE_FILE}`
            grep -v "txt-record" ${AVAHI_SERVICE_FILE} > ${tmpfile}
            sed -i s/"\/port>"/"\/port>\n\t<txt-record>version=${VERSION}<\/txt-record>\n\t<txt-record>product=${PRODUCT}<\/txt-record>\n\t<txt-record>SN=${SN}<\/txt-record>\n\t<txt-record>csv-sep=${COLUMNSEP}<\/txt-record>"/ ${tmpfile}
            sed -i s/"port>.*<\/port"/"port>${PORT}<\/port"/ ${tmpfile}
            cp ${tmpfile} ${AVAHI_SERVICE_FILE}
	    #grep -nH txt-record ${tmpfile} ${AVAHI_SERVICE_FILE}
	fi
    else
	echo "Missing avahi daemon, doing nothing"
    fi
}
# Starting avahi and fix some tweaks while starting this deamon
# see /etc/network/if-up.d/01-start-services for starting the service without tweaking as alternative.
# DEPRECATED: off for now
function start_avahi () {
  if [ ! -f /tmp/start_avahi ]
  then
      if [ -f /etc/init.d/avahi-daemon ]
      then	
	  echo "Starting avahi mit settings Port: $PORT, Version: $VERSION, Product: $PRODUCT, SN=$SN, COLUMNSEP=$COLUMNSEP"
           # Wait 20 seconds, else avahi will fail
	  ( touch /tmp/start_avahi; sleep 20 ;  
	      /etc/init.d/avahi-daemon restart ; rm /tmp/start_avahi ) &    
            #/etc/init.d/avahi-daemon status
      else
	  echo "Missing avahi daemon, doing nothing"
      fi
  else
      echo Already started avahi.
  fi
}
# Finally call this to unload driver and cleanup
function poststop_network () {
    IFACE=$1
    # not needed, module is built-in: 
    #if [ $IFACE == "eth0" ]; then
	#rmmod smsc95xx
    #fi	
    debugout "Nothing to do for interface: $IFACE"
}
# If once unload we cannot load wl18xx driver anymore, so we have to block it 
# returns true (0) if still not unloaded modules
function check_unload_wlan_module () {
    return 0
    N=0
    detect_wlan_chipset
    if [ -f /tmp/${WLANINTERFACENAME}_modules_unload ]
    then
	N=$(cat /tmp/${WLANINTERFACENAME}_modules_unload)
    fi
    if [ ! -z $1 ]
    then
	let N=$N+$1
    fi
    echo $N > /tmp/${WLANINTERFACENAME}_modules_unload
    return $N

}
# When trying to add a new cell, and the cell
# is already there, then we remove it first and
# add it again with new priority number. 
function remove_cell_from_config () {
   if [[ ! -z "`grep \"${1}\" ${WPA_CONF}`" ]]            
   then                                                   
       echo Cell $1 already specified - remove old section 
       ## static line length
       #POS=$(grep -n "ssid=\\\"${1}\\\"" ${WPA_CONF} | cut -d ":" -f 1)
       #let A=${POS}-2                          
       #LEN=$(wc -l ${WPA_CONF}|cut -d " " -f 1)
       #let B=${LEN}-${POS}-4                  
       #head -$A ${WPA_CONF} > ${WPA_DUP_CONF} 
       #tail -$B ${WPA_CONF} >> ${WPA_DUP_CONF}
       #cp ${WPA_DUP_CONF} ${WPA_CONF}
       ## dynamic / find end of section: 
       sed -i '/# added at/{:a; N; /} $/!ba; /ssid="'"${1}"'"/d}' ${WPA_CONF}
       # Explanation: 
       # /# added at/         # When matching '# added at'
       # {
       # :a                   # Create label a
       # N                    # Append next line to pattern space
       # /\} $/!ba            # If this line doesn't contain '} $' goto a
       # /ssid="'"${1}"'"/d   # If pattern space contains 'ssid=${1}' then delete it.
       # }

   fi
} 
# See bug 2697
# If setup wifi is unsuccessfull, copy logfile onto usb storage if connected and bring message.
function do_error_log () {
    local LOGFILE=$1
    if [ -z $LOGFILE ]
    then
	LOGFILE=/tmp/wlan-$(date +%Y%m%d-%H%M).log
    fi
    # copy setup log into logfile
    if [ ! -z $WPA_TEMP_LOG ] && [ -f $WPA_TEMP_LOG ]
    then
	echo " +++ output of wpa_supplicant run with temporary config: +++ " >> $LOGFILE
	cat $WPA_TEMP_LOG >> $LOGFILE
	stdout="$(grep -i "wpa_state=\|ssid=" ${WPA_TEMP_LOG})"
    fi
    echo "= = = END = = = " >> $LOGFILE
    echo "Content of ${WPA_CONF} " >> $LOGFILE
    cat ${WPA_CONF} >> $LOGFILE
    if [ -f ${WPA_TEMP_CONF} ]
    then
	echo "Content of ${WPA_TEMP_CONF} " >> $LOGFILE
	cat ${WPA_TEMP_CONF} >> $LOGFILE
    fi
    echo "-------- Version: " >> $LOGFILE 
    bash /etc/versions/system.sh >> $LOGFILE                                        
    bash /etc/versions/analyze.sh >> $LOGFILE                                       
    echo "-------- WIFI environment: " >> $LOGFILE
    if [ ! -z ${IWCONFIGOUT} ]
    then
	cat ${IWCONFIGOUT} >> $LOGFILE                                               
	cat ${IWLISTOUT}  >> $LOGFILE
    else
	$LIST_CMD >> $LOGFILE
    fi
    wpa_cli_status_cmd >> $LOGFILE
    echo "-------- lsmod:  " >> $LOGFILE
    lsmod >> $LOGFILE	
    echo "-------- iwconfig after changes:" >> $LOGFILE
    $CELL_STATUS_CMD >> $LOGFILE
    echo "-------- dmesg : " >> $LOGFILE
    dmesg >> $LOGFILE

    if request_support_ext_drive
    then  
	echo "`tr "Setup WLAN failed. See logfile on usb drive:"`"
	basename ${LOGFILE}
	cp $LOGFILE ${SUPPORTDIR}/
	release_support_ext_drive
    else
	echo "Setup WLAN failed" 
	echo "$stdout"
    fi
}
# Waits for temporary wpa_supplicant result.
# Usually called at setup by setup testing a new config.
# returns:
#   0 if successfull
#   1-5 reserved by is_carrier_up
#   6 wrong password
#   7 eap setup wrong
#   8 essid out of reach
#   9 internal error: WPA_TEMP_LOG file missing
#  10 internal error: wpa_supplicant not running
#  11 internal error: variable WPA_TEMP_LOG not set
function wait_for_wpa_supplicant () {
    if [ -z $WPA_TEMP_LOG ]
    then
	debugout "wait_for_wpa_supplicant returned with 11"
	return 11
    fi
    for i in {1..5}
    do
	if  [ -e $WPA_TEMP_LOG ]
	then
	    break
	fi
	sleep 0.5
    done
    local RETVAL=0
    if [ -f $WPA_TEMP_LOG ] &&  ps -C wpa_supplicant -o pid=
    then
	notfoundcounter=0
	tail -F $WPA_TEMP_LOG | while read line
	do
	    case "$line" in
		*"GROUP_HANDSHAKE -> COMPLETED" | *"ASSOCIATED -> COMPLETED" )
		    echo "Setup complete"
		    ret=0
		    break
		    ;;
		*"4WAY_HANDSHAKE -> DISCONNECTED" | *"ASSOCIATING -> DISCONNECTED" )
		    echo "PSK wrong password"
		    ret=6
		    break
		    ;;
		*"ASSOCIATED -> DISCONNECTED" | *"CTRL-EVENT-ASSOC-REJECT" )
		    echo "EAP wrong setup (login, password, cert...)"
		    ret=7
		    break
		    ;;
		*" No suitable network found")
		    echo "ESSID out of reach"
		    ((notfoundcounter++))
		    if [ $notfoundcounter -gt 2 ]; then
		    	ret=8	
		    	break
		    fi
		    ;;
		*"State: "*)
		    # do not output $line here, this might cause a endless loop... - better 
		    #debugout "Else state transition: $(echo $line | sed s/'${WLANINTERFACENAME}: State: '//g)"
		    ;;
		*)
		    # do not output $line here, this might cause a endless loop...
		    #echo "something else: $line"
		    ;;
	    esac
	done
    elif [ ! -f $WPA_TEMP_LOG ]
    then
	echo "Logfile $WPA_TEMP_LOG is missing"
	RETVAL=9
    else
	echo "wpa_supplicant is not running"
	RETVAL=10
    fi
    debugout "wait_for_wpa_supplicant returned with $RETVAL"
    return $RETVAL
}

# Parses ${IWCONFIGOUT} output file and sets variable OURNET, get_cell_status function has to be called before!
function set_ournet () {
    OURNET=
    #debugout set_ournet: iwconfigout: $IWCONFIGOUT 
    if [ -f ${IWCONFIGOUT} ] && [ ! -z "`cat ${IWCONFIGOUT}`" ]
    then
	if [ ${NL80211} == 1 ]
	then
	    OURNET="`grep SSID ${IWCONFIGOUT} | cut -f 2 -d \" \" `";
	else
	    t=\\"
            t=\\"
	    OURNET="`grep ESSID ${IWCONFIGOUT} | cut -f 2 -d \":\" | cut -f 2 -d \"${t}\" `"; 
	fi
    fi
}
# Get current connection status (either with iwconfig or iw dev wlan0
# link) and stores that into ${IWCONFIGOUT}
# param: return of configured_cells_match_ssid_list or 100 if not run
# returns 0 (true) if connected, else false:
# 1 Unconfigured
# 2 Out of reach 
# 3 Unconnected
# 4 Network off
# 5 iw call error
function get_cell_status () {
    #set -x
    match=$1
    if [ -z $match ]
    then
	match=100
    fi
    if [ -z ${IWCONFIGOUT} ]
    then
	detect_wlan_chipset
	detect_wlan_toolset
    fi
    #init
    rm -f ${IWCONFIGOUT}-err ${IWCONFIGOUT}
    RC=100

    if  configured_cells  # amount == 0
    then
	debugout "get_cell_status: Still no network in ${WPA_CONF} specified."
	touch ${IWCONFIGOUT}
	RC=1
	echo "Unconfigured __(${RC})_" > ${IWCONFIGOUT}-err
    elif [ $match != 100 ] && [ $match != 0 ] # non init and does not match
    then
	debugout "get_cell_status: Results of ${IWLISTOUT} does not match ${WPA_CONF}."
	touch ${IWCONFIGOUT}
	RC=2
	echo "Out of reach __(${RC})_" > ${IWCONFIGOUT}-err 	
    else # get cell state
	$CELL_STATUS_CMD > ${IWCONFIGOUT} 2>${IWCONFIGOUT}-err
	if [ ! -s ${IWCONFIGOUT}-err ] # is empty
	then
	    RC=0
	    set_ournet # sets OURNET
	    get_mode
	    gmr=$?
	    if [ ${gmr} == 0 ] # empty
	    then
		RC=3
		echo "Unconnected  __(${RC})_" > ${IWCONFIGOUT}-err
	    elif [ ${gmr} == 1 ] # managed
	    then
		if ( ! ps -C wpa_supplicant > /dev/null )  && ( ! ps -C dhcpcd > /dev/null )  
		then
		    RC=4
		    echo "Network off  __(${RC})_" > ${IWCONFIGOUT}-err
		fi
	    #else # gmr==2, zebra
	    fi 
	else
	    RC=5
	    echo "Interface error __(${RC})_" >> ${IWCONFIGOUT}-err
	fi
	debugout "get_cell_status: RC=$RC OURNET=${OURNET}"
    fi
    #set +x
    return $RC
}

# Get current cells list (either with iwlist or iw dev wlan0
# scan) and stores that into ${IWLISTOUT}
# returns: 
# true (0) if successfull scan
# false (>0) if failed: 4=Network off, 5=call failed, 8=No networks found
function get_essid_list () {
    if [ -z ${IWLISTOUT} ]
    then
	detect_wlan_chipset
	detect_wlan_toolset
    fi
    # init
    rm -f ${IWLISTOUT} ${IWLISTOUT}-err
    RC=100

    local scanret=99
    local try=0
    local retries=5
    while [ $scanret -gt 0 ] && [ ! $scanret == 156 ] && [ $try -lt $retries ]; do 
        $LIST_CMD 1>${IWLISTOUT} 2>${IWLISTOUT}-err
        scanret=$?
	echo "get_essid_list: attempt $try with $scanret" 
        if [ $scanret -gt 0 ]; then
  	   sleep 5 
        fi
	((try++))
    done 

    if [ $scanret == 156 ]
    then
	debugout "get_essid_list: device is down"
	RC=4 # Network off
	touch ${IWLISTOUT}
	echo "Network off __(${RC})_" > ${IWLISTOUT}-err
    elif [ $scanret -gt 0 ]
    then
	debugout "get_essid_list: unknown error: scanret: $scanret"
	RC=5 # Interface error 
        echo "Interface error __(${RC})_" >> ${IWLISTOUT}-err
	debugout "get_essid_list: unknown error again: scanret: $scanret, giving up"
    else
	if [ ! -s ${IWLISTOUT} ]
	then
	    RC=8 # No Networks found 
	    echo "No networks found __(${RC})_" >> ${IWLISTOUT}-err
	elif grep "scan aborted"  ${IWLISTOUT} > /dev/null
	then
	    RC=8
	    echo `cat ${IWLISTOUT}` " __(${RC})_" >> ${IWLISTOUT}-err 
 	    rm  ${IWLISTOUT}
            touch ${IWLISTOUT}
	else
	    RC=0
	fi
    fi
    debugout "get_essid_list $LIST_CMD returned with $scanret, RC=$RC"
    wait_for_ip_no_restart_dhcp
    return $RC
}
# Echos stdgw if possible else empty
function get_stdgw () {
    echo `ip route| grep default | cut -d " " -f 3`
}

# Retry to get standard gateway string from with "ip route" in
# the case, it is still not set, it means, we lost the carrier,
# but it is up again, but "ip route" gives us no gateway, so
# either none is set or it is still not set again.
# echo found stdgw and returns amount of retries
function wait_for_stdgw () {
     stdgw=`get_stdgw`
     RETRY=0
     MAX_RETRIES=$1
     if [ -z $MAX_RETRIES ]
     then
	 MAX_RETRIES=1
     fi
     while [ -z ${stdgw} ] && [ $RETRY -lt ${MAX_RETRIES} ]
     do
	 stdgw=`get_stdgw`
	 sleep 1
	 ((RETRY++))
     done
     if [ ! -z ${stdgw} ]
     then
	 # echo stdgw so we can do var=`get_stdgw`
	 # do not echo something else here!
	 echo $stdgw
     fi
     return $RETRY
}
# Check if configured wifi networks in ${WPA_CONF} matches scan output ${IWLISTOUT}.
# return:
# 0 match
# 1 no match
function configured_cells_match_ssid_list () {
    #set -x
    RC=1 # init
    for wpa_entry in `grep ssid= ${WPA_CONF}|cut -f 2 -d '"'`
    do 
	SSID=$(echo "$wpa_entry" | cut -f 2 -d '"')
	for scan_entry in `grep "SSID:" ${IWLISTOUT} | cut -f 2- -d ' '`
	do
	    if [ "$scan_entry" == "$wpa_entry" ]
 	    #if echo $scan_entry | grep "SSID: ${SSID}$"
	    then
		RC=0 # match !
		break
	    fi
	done
    done
    return $RC
}
# returns the amount of configured cells in ${WPA_CONF}
# 0 nothing configured (true)
# >0 amount of configured networks (false); 
function configured_cells () {
    return $(grep ssid= ${WPA_CONF}|wc -l)
}
# Main loop when network is a managed one
# return true (0) if having an ip, else error code
function scan_managed () {
   ret=0
   if is_carrier_up
   then
       if wait_for_ip
       then
	   dbgstate=${dbgstate}"Got IP. "
	   stdgw=`get_stdgw`
	   if [ ! -z $stdgw ]
	   then
	       ping -c 1 -w 4 ${stdgw}
	       dbgstate=${dbgstate}"stdgw set, ping stdgw=${?}. "
	   else
	       dbgstate=${dbgstate}"stdgw empty. "
	   fi
	   ret=0
       else
	   ret=$?
	   dbgstate="scan_managed: link up, no ip, retries: $ret. "
       fi
   else
      if [ ! -z ${OURNET} ] && [ ! -z "`grep ssid ${WPA_CONF} | grep "${OURNET}" `" ]
      then
	  stdgw=`get_stdgw`
	  if [ ! -z ${stdgw} ]
	  then
	      dbgstate=${dbgstate}"stgw set, "
	      # Usually after 7-8 seconds we find the essid again, so we wait 4 x 2 seconds
	      ping -c 4 -w 2 ${stdgw}
	      if [ $? == 0 ] 
	      then
		  dbgstate=${dbgstate}"ping stdgw ok, wait again for ip "
		  if wait_for_ip
		  then
		      dbgstate=${dbgstate}"have ip. "
		      ret=0
		  else
		      ret=$?
		      dbgstate=${dbgstate}"NO ip: retries: ${ret}. "
		  fi
	      else 
		  dbgstate=${dbgstate}"ping stdgw failed. "
		  ret=100
	      fi
	  else
	      dbstate=${dbstate}"stdgw not set. "
	      ret=101
	  fi
      else
	  dbgstate=${dbstate}"OURNET=${OURNET} not in wpa_supplicant_po.conf or empty!"
	  ret=102
      fi
   fi
  debugout ${dbstate}
  return $ret
}

# Main loop if we are in a ad-hoc network
function scan_adhoc () {
    debugout WLAN adhoc
    detect_wlan_chipset

      # Fix: if there is only one "zebra" (only us) then restart network to start init.d/networking and scan again.
      # Reason: When starting /etc/init.d/networking and the zebra was not found, iwconfig tells us
      # that we are connected to zebra, but we are not. If you scan from another machine, you will not see 
      # it. But if the zebra is in the network, then after restarting the network the network will be connected. 
    ping  -c 2 -W 1  192.168.60.4
    adhocret=$?
    if [[ ! $adhocret == 0 ]]
    then
	if have_ip
	then
	    debugout "Have IP, network device is up, but zebra is not available"
	else
	    debugout "Have no IP, restart network device"
	    network_stop
            /etc/init.d/networking start 
            get_essid_list
            get_cell_status
	fi
    else 
	debugout "Ping OK. No complete scan needed. Have IP"
    fi

    try=0
    while  [ $try -lt 10 ] && ! have_ip
    do
	debugout "Wait for ip... try: $try"
	sleep 1
	((try++))
    done
    if [ $adhocret == 1 ] && ! have_ip
    then
	debugout "Still no ip, but we could ping, so ifconfig was still not set, setting manually"
	ifconfig ${WLANINTERFACENAME} 192.168.60.2
    fi
    
    zf=`grep zebra ${IWLISTOUT} | wc -l`
    if [ $zf -lt 2 ] &&  [ $adhocret == 0 ] 
    then	
	# dBm=$(grep "\-\- joined" -A 10 ${IWLISTOUT} | grep signal | cut -d " " -f 2)
	# if [ "${dBm}" != "0.00" ] 
	mymac="`head -n 1 ${IWCONFIGOUT}  | cut -d " " -f 3`"
	mycell="`grep ${mymac} ${IWLISTOUT}`"
	if [ -z "${mycell}" ]
	then
	        debugout "Adding our own cell to scan output!"
		echo "BSS ${mymac} (on ${WLANINTERFACENAME}) -- joined">>${IWLISTOUT}
		echo "            TSF: 0 usec (0d, 00:00:00)">>${IWLISTOUT} 
		echo "            freq: 2412">>${IWLISTOUT} 
		echo "            beacon interval: 100">>${IWLISTOUT} 
		echo "            capability: IBSS (0x0002)">>${IWLISTOUT} 
		echo "            signal: 0.00 dBm">>${IWLISTOUT} 
		echo "            last seen: 55242 ms ago">>${IWLISTOUT} 
		echo "            SSID: zebra">>${IWLISTOUT} 
		echo "            Supported rates: 1.0* 2.0* 5.5* 11.0* ">>${IWLISTOUT} 
		echo "            DS Parameter set: channel 1">>${IWLISTOUT} 
	fi
        if [ `grep zebra ${IWLISTOUT} | wc -l`  -lt 2 ]
        then
	        debugout "Adding fictive cell to scan output."
	        echo "BSS 00:11:22:33:44:55 (on ${WLANINTERFACENAME})">>${IWLISTOUT}
 	        echo "            TSF: 0 usec (0d, 00:00:00)">>${IWLISTOUT} 
	        echo "            freq: 2412">>${IWLISTOUT} 
	        echo "            beacon interval: 100">>${IWLISTOUT} 
	        echo "            capability: IBSS (0x0002)">>${IWLISTOUT} 
	        echo "            signal: -40.00 dBm">>${IWLISTOUT} 
	        echo "            last seen: 55242 ms ago">>${IWLISTOUT} 
	        echo "            SSID: zebra">>${IWLISTOUT} 
	        echo "            Supported rates: 1.0* 2.0* 5.5* 11.0* ">>${IWLISTOUT} 
	        echo "            DS Parameter set: channel 1">>${IWLISTOUT} 
        fi
    fi
    if [ $DEBUG == 1 ]
    then	
	echo "---- $zf zebras cells found in ${IWLISTOUT}:" 
	grep zebra ${IWLISTOUT} -B 8| grep 'SSID\|BSS\|signal'
	echo Content of ${IWCONFIGOUT} : 
	cat ${IWCONFIGOUT}
    fi
}
# Do a network scan with given parameter if complete ore not ("iwlist"=complete)
function scan_network_wrapper () {
   IF=$1
   MODE=$2
   debugout "scan_network_wrapper: $1 $2"
   detect_wlan_chipset    
   if [ -z $IF ] 
   then
       return 3
   ######### WLAN0 ###############
   elif [ $IF == ${WLANINTERFACENAME} ]
   then
       # init 
       match=100

       #### iw scan / iwlist: #########
       if [ x$MODE == "xiwlist" ]
       then
	   # try only once, takes some time
	   get_essid_list
	   # can be called only after get_essid_list
	   configured_cells_match_ssid_list
	   match=$?
       fi
       #### iw link / iwconfig: ##### 
       get_cell_status $match
       if [ $? -gt 4 ] #call error
       then
	   sleep 1 # try again
	   get_cell_status $match
       fi
   ##########  ETHERNET ############
   elif [ $IF == eth0 ]
   then
       # for wlan0 interface: 
       rm ${IWLISTOUT} ${IWCONFIGOUT} ${IWLISTOUT}-err ${IWCONFIGOUT}-err
       touch ${IWLISTOUT}
       touch ${IWCONFIGOUT}
       touch ${IWLISTOUT}-err
       # check, whether eth0 is up: 
       if is_carrier_up
       then
	   sleep 4 & wait_for_ip 2>/dev/null >/dev/null
	   S=$?
	   if [ $S == 0 ]
	   then
	       echo "Ethernet up __(9)_" > ${IWCONFIGOUT}-err
	   else
	       echo "Ethernet up without IP __(10)_" > ${IWCONFIGOUT}-err
	   fi
	   debugout "${WLANINTERFACENAME} down, but eth0 up, IP $S: "`have_ip` 
       else
	   echo "All devices down __(11)_" > ${IWCONFIGOUT}-err
	   debugout "${WLANINTERFACENAME} and eth0 are down"
       fi
   # for x in {1..10}; 
   # do 
   # 	if [ -f /var/lib/dhcp/dhclient.leases ] && [ ! -z "$(cat /var/lib/dhcp/dhclient.leases)" ]
   # 	then	
   # 		echo "After $x tries, we got an IP:`ifconfig eth0|grep "inet add"`" ;
   # 		if [ $x -lt 4 ]
   # 		then	
   # 			let s=4-$x
   # 			sleep $s
   # 		fi
   # 		break
   # 	fi	
   # 	sleep 1 
   # 	echo "No lease, try again ($x)" ; 
   # done
   else
       debugout "Missing or wrong paramter scan_network_wrapper 1=$IF 2=$MODE"
   fi
}
function get_next_prio () {
    NEXTNO=0
    let NEXTNO=`grep priority ${WPA_CONF} | cut -f 2 -d "="| sort -n| tail -1 `+1
    echo $NEXTNO
}

function gen_psk_wpa_supplicant () {
    if [ ! -z "${1}" ] && [ ! -z "${2}" ] && /usr/sbin/wpa_passphrase "$1" "$2" &> /dev/null
    then 
        echo "# added at `date`"
	/usr/sbin/wpa_passphrase "$1" "$2"  |grep -v "}"
	echo "        priority=`get_next_prio`"
	echo "} "
    else
	return 1
    fi
}

# Generates a wpa_suppicant.conf entry for a SAE/WPA3 network
# param  $1 = ESSID + $2 = PASSWORD
# returns true if all parameter given, else false
function gen_sae_supplicant () {
    if [ ! -z "${1}" ] && [ ! -z "${2}" ] 
    then 
        echo "# added at `date`"
	echo "network={"
	echo "	ssid=\"${1}\""
        echo "	sae_password=\"${2}\""
	echo "	key_mgmt=SAE"
        echo "	ieee80211w=2"
	echo "	priority=`get_next_prio`"
	echo "} "
    else
	return 1
    fi
}

# Add a wpa_passwd output to wpa_supplicant_po.conf
# Need parameter 1 with SSID
# parameter 2 with password
# parameter 3 - if present - is for EAP-PEAP networks
# parameter 4 for type {EAP,SAE,PSK}
function add_passwd_to_wpa_supplicant () {
    local ESSID="${1}"
    local PASSWD="${2}"
    local LOGIN="${3}"
    local TYPE="${4}"
    remove_cell_from_config "${ESSID}"
    if [ ${TYPE} == "EAP" ];then
	gen_eappeap_wpa_supplicant "${1}" "${2}" "${3}" >> ${WPA_CONF}
    elif [ ${TYPE} == "SAE" ]; then
	gen_sae_supplicant "${1}" "${2}"  >> ${WPA_CONF}
    else
	gen_psk_wpa_supplicant "${1}" "${2}"  >> ${WPA_CONF}
    fi
    if [ $DEBUG == 1 ]
    then    
	echo ----- wpa_supplicant_po.conf: ----- 
	grep ${1} ${WPA_CONF} -A 4
    fi
}
function gen_open_network_wpa_supplicant () {
    echo "# added at `date`" 
    echo "network={" 
    echo "          ssid=\"""${1}""\""
    echo "          key_mgmt=NONE" 
    echo "          priority=`get_next_prio`"
    echo "}" 
}
function add_open_network_to_wpa_supplicant () {
    remove_cell_from_config "$1"
    gen_open_network_wpa_supplicant "$1" >> ${WPA_CONF}
}
# Search value of a key in a wpa_supplicant conf file
# like ssid="hansi" we search for "ssid" and get "hansi"
function get_value_of_key () {
    local key="$1"
    local file="$2"
    
    grep "${key}[ ]*=" ${file} | cut -f 2 -d "="| cut -f 2 -d "\"" | sed s/" "//g
}
# Checks, whether there is a wpa config at the USB drive at wifisetup subdir
# Requirements:
#    <usbdrive>/wifisetup/plusoptix.conf
#    <usbdrive>/wifisetup/<ca file name specified in conf>
#    <usbdrive>/wifisetup/<client cert file name specified in conf, if TLS>
#    <usbdrive>/wifisetup/<private key file name specified in conf, if TLS>
#    ... some other files... 
# Example for EAP PEAP with given ca_cert="/etc/xyz/ca.pem"
#    <usbdrive>/wifisetup/plusoptix.conf
#    <usbdrive>/wifisetup/ca.pem
# Important: needs request_support_ext_drive call
# Param: debug - more output
function check_user_wpa_config () {
    local USER_CFG_FILE_NAME=${USBPATH}/wifisetup/plusoptix.conf
    local TMP_OUT_FILE=/tmp/t.conf
    local MISSINGFILES=
    local CERTFILES=
    local SUBDIR=wifisetup
    local WORKDIR=${USBPATH}/${SUBDIR}
    local DEBUG=$1
    local OUTPUT=
    local RETVAL=0
    local number=`get_next_prio`
    
    if [ -e ${USBPATH}/wifisetup ] && [ -f $USER_CFG_FILE_NAME ]
    then
	local ESSID=$(get_value_of_key " ssid" ${USER_CFG_FILE_NAME})
	local KEY_MGMT=$(get_value_of_key "key_mgmt" ${USER_CFG_FILE_NAME})
	local EAP=$(get_value_of_key "eap" ${USER_CFG_FILE_NAME})
	#local PSK=$(get_value_of_key "[^#]psk" ${USER_CFG_FILE_NAME})

	#if [ ${#PSK} -lt 65 ]; then
	#    if wpa_passphrase "${ESSID}" "${PSK}" |grep -v "}" > /tmp/hidden.conf; then
        #       echo "  scan_ssid=1" >> /tmp/hidden.conf	
        #       echo "}" >> /tmp/hidden.conf
	#       PSK=$(get_value_of_key "[^#]psk" /tmp/hidden.conf)
        #    fi
	#elif [ ${#PSK} -gt 65 ]; then
	#    PSK=$(echo $PSK | cut -c -65)
	#fi
	# cert file keys: 
	keys='ca_cert=\|ca_cert2=\|client_cert=\|client_cert2=\|private_key=\|private_key2='
	ignore='}\|ctrl_interface\|ap_scan\|priority='

	# ignore that cert file keys first
	grep -v ${keys} ${USER_CFG_FILE_NAME} |grep -v "${ignore}"> ${TMP_OUT_FILE}
	
	if [ x$DEBUG == x"debug" ]
	then
	    # Debugging: 
	    echo "Original: "
	    cat ${TMP_OUT_FILE}
	    echo "Found: "
	    echo "ESSID: ${ESSID}"
	    echo "Key mgmt: ${KEY_MGMT}"
	    echo "eap: ${EAP}"
	    #echo "Identity: "
	    #get_value_of_key "identity" ${USER_CFG_FILE_NAME}
	    #echo "Password: "
	    #get_value_of_key "private_key_passwd" ${USER_CFG_FILE_NAME}
	fi
	
	# now we replace all cert files by our names
	while read line
	do
            if echo ${line} | grep "${keys}"
            then
		a="$(echo ${line} | cut -f 2 -d "="| cut -f 2 -d "\"")"
		b="${a##*/}"
		if [ ! -e ${WORKDIR}/${b} ]
		then
                    MISSINGFILES="${MISSINGFILES} ${b}"
		else
		    CERTFILES="${CERTFILES} ${b}"
		fi
		#echo "___ ${a} - ${b} ___"
		echo $line | sed s/"\(.*\)=.*"/"\t\1=\"\/etc\/cert\/${number}\/${b}\""/g >> ${TMP_OUT_FILE}
	    #elif echo ${line} | grep "psk=" && [ ! -z "${PSK}" ]; then
		#echo "$line  -> psk=${PSK}"  
		#echo $line | sed s/"[ \t]*psk=.*"/"\tpsk=${PSK}"/g >> ${TMP_OUT_FILE}
	    fi
	done<$USER_CFG_FILE_NAME

	if [ x$DEBUG == x"debug" ]
	then
	    # some output for debugging: 
	    diff $TMP_OUT_FILE $USER_CFG_FILE_NAME
	fi
	if [ ! -z "${MISSINGFILES}" ]
	then
	    OUTPUT="Found \"plusoptix.conf\" at subfolder ${SUBDIR} on the usb drive.\nThere are files (like client certificates) referenced at the file, \nbut that files are missing:\n$MISSINGFILES\nPlease place these files into the folder ${SUBDIR} and try again"
	    RETVAL=1
	else
	    OUTPUT="Found valid config for network $ESSID ($KEY_MGMT $EAP)"
	    # Build new config for test_temp_wpa_supplicant:
	    head -9 ${WPA_CONF} > ${WPA_TEMP_CONF}
	    echo "# added at `date`" >> ${WPA_TEMP_CONF}
	    cat ${TMP_OUT_FILE} >> ${WPA_TEMP_CONF}
	    echo "    priority=${number}" >> ${WPA_TEMP_CONF}
	    echo "} " >> ${WPA_TEMP_CONF}
	    # copy the certificates, if configured
	    mkdir -p /etc/cert/${number}
	    if [ ! -z "${CERTFILES}" ]
	    then
		cd ${WORKDIR}
		cp ${CERTFILES} /etc/cert/${number}/
		cd -
	    fi
	    RETVAL=0
	fi
    elif  [ -e ${USBPATH}/wifisetup ] && [ ! -f $USER_CFG_FILE_NAME ]
    then
	OUTPUT="Missing \"plusoptix.conf\" at subfolder ${SUBDIR} on the usb drive.\nThis file contains the credentials like username, password etc. for your network.\nThe content depends on the network you have.\nHere you can find examples, howto create a config:\nhttps://www.systutorials.com/docs/linux/man/5-wpa_supplicant.conf/\nAdd files and try again."
	RETVAL=2
    fi
    echo $OUTPUT
    return $RETVAL
}
# Add wpa_config of the user (for EAP/...) to wpa_supplicant_po.conf
function add_user_wpa_config  () {
    local TMP_OUT_FILE=/tmp/t.conf
    for ssid in `get_value_of_key ssid ${TMP_OUT_FILE}`
    do
	remove_cell_from_config "${ssid}"
    done
    
    if [ -f ${TMP_OUT_FILE} ]
    then
	echo "# added at `date`" >> ${WPA_CONF}
	cat ${TMP_OUT_FILE} >> ${WPA_CONF}
	echo "    priority=$(get_next_prio)" >> ${WPA_CONF}
	echo "} " >> ${WPA_CONF}
	return 0
    else
	echo "File missing $TMP_OUT_FILE"
	return 1
    fi
}
# Outputs a simple config for EAP-PEAP-MSCHAPv1 without ca check
# param 1 - ssid name
# param 2 - passwd
# param 3 - username
function gen_eappeap_wpa_supplicant () {
    local number=`get_next_prio`
    echo "# added at `date`"
    echo "network={"
    echo "	       ssid=\"${1}\""
    echo "	       password=\"${2}\""
    echo "	       identity=\"${3}\""
    echo "	       key_mgmt=WPA-EAP IEEE8021X"
    echo "	       scan_ssid=1"
    echo "	       proto=WPA RSN"
    # Limit to LEAP and PEAP, if not set try all
    echo "	       eap=LEAP PEAP"
    # optional peaplabel=0/1:
    # old eap
    #echo "	       phase1=\"peaplabel=0\""
    # new eap
    #echo "	       phase1=\"peaplabel=1\""
    # EAP-FAST:
    #echo "             phase1=\"fast_provisioning=1\""
    echo "	       phase2=\"auth=MSCHAPV2\""
    echo "	       priority=${number}"
    echo "} "
}
# Updates the password of PSK entry
# TODO: update of EAP-PEAP 
function update_existing_passwd_in_wpa_supplicant () {
    pw="$(grep "id=\"${1}\"" ${WPA_CONF} -A 1|tail -1|cut -d "\"" -f 2)"
    echo "update_existing_password ${1} ${pw} ${2}"
    add_passwd_to_wpa_supplicant "${1}" "${pw}" "__UNSET__" "${2}"
}
# Uses th current temporary wpa_supplicant conf and test if it works
# usually called during setup
function test_temp_wpa_supplicant () {
    detect_wlan_chipset
    detect_current_nw_if
    local RETVAL=0
    rm -f $WPA_TEMP_LOG
    # backup current config
    cp ${WPA_CONF} ${WPA_CONF}_old  
    # copy temporary in place
    cp ${WPA_TEMP_CONF} ${WPA_CONF}

    wpa_cli -i ${CURRENT_NW_IF} reconfigure                     

    wait_for_carrier > ${WPA_TEMP_LOG}
    RETVAL=$?

    debugout "test_temp_wpa_supplicant returned with $RETVAL / try ${try}"
    mv ${WPA_CONF}_old ${WPA_CONF}
    
    return $RETVAL
}

# Pre parser for the arguments for the wlan-addnet.sh script
# returns 0 if adding is selected
# returns 2 if essid is not set
# returns 3 if password is not set
# returns 4 if password is too short
# returns 5 if password is too long
# returns 10 if udpate is selected
# returns 11 if remove is selected
#
# Fills variables ESSID, PASSWD, LOGIN and TYPE (declare before)
function parse_wlan_addnet_args () {
    ESSID="${1}"
    PASSWD="${2}"

    if [ ! -z "${3}" ]; then
	if echo "${3}" | grep "^-t[^ ]"; then
	    TYPE="$(echo "${3}"| cut -c 3-)"
	elif echo "${3}" | grep "^-u[^ ]"; then
	    LOGIN="$(echo "${3}"| cut -c 3-)"
	    if [ -z "${4}" ]; then
		TYPE="EAP"
	    fi
	elif echo "${3}" | grep "^-c[^ ]"; then
	    TYPE="$(echo "${3}"| cut -c 3-)"
	else
	    LOGIN="${3}"
	    TYPE="EAP"
	fi
    fi
    if [ ! -z "${4}" ] && echo "${4}" | grep "^-t[^ ]"; then
	TYPE="$(echo "${4}"| cut -c 3-)"
    fi

    if [ -z "${ESSID}" ] ; then return 2;
    elif [ ! -z "${ESSID}" ] && [ -z "${PASSWD}" ]; then return 3;
    elif [ "${#PASSWD}" -lt 8 ]; then return 4;
    elif [ "${#PASSWD}" -gt 32 ]; then return 5;
    elif [ "${PASSWD}" == "_PASSWORD_SET_" ] || [ "${TYPE}" == "Update" ]; then return 10; 
    elif [ "${TYPE}" == "Remove" ]; then return 11; 
    #elif [ "${TYPE}" == "PSK" ]; then return 0; 
    #elif [ "${TYPE}" == "SAE" ]; then return 0; 
    #elif [ "${TYPE}" == "EAP" ]; then return 0; 
    else
	return 0
    fi
}

# Generates a temporary config and test it with wpa_supplicant 
# parameter 1 network name / ESSID
# parameter 2 password 
# parameter 3 login for wpa-enterprise / eap... (optional)
# parameter 4 command or option
function test_new_wpa_pw () {
    if [ ! -z "${1}" ] && [ ! -z "${2}" ]
    then
	head -9 ${WPA_CONF} > ${WPA_TEMP_CONF}
	if [ "${4}" == "EAP" ]
	then
	    echo "WPA enterprise / EAP..." 
	    gen_eappeap_wpa_supplicant "$1" "$2" "$3"  >> ${WPA_TEMP_CONF}
	elif [ "${4}" == "SAE" ]; then
	    echo "SAE (WPA3)..."
	    if ! gen_sae_supplicant "$1" "$2"  >> ${WPA_TEMP_CONF} ;then
		echo "error while generating network with wpa_passphrase" 
		return 10
	    fi
	else
	    echo "PSK (WPA2)..."
	    if ! gen_psk_wpa_supplicant "$1" "$2"  >> ${WPA_TEMP_CONF} ;then
		echo "error while generating network with wpa_passphrase" 
		return 10
	    fi
	fi
	local ret=0
	if test_temp_wpa_supplicant; then
	    add_passwd_to_wpa_supplicant "${1}" "${2}" "${3}" "${4}"
	    ret=0
	else
	    ret=1
	fi
        if ! configured_cells; then
	    wpa_cli -i wlan0 reconfigure
            wpa_cli -i wlan0 reconnect
        fi 
	return ${ret}
	# returns 0 if successfull or >0 else
    else
	return 10
    fi
}
# In the case we configured an essid and it is in reach or there are
# some suspicious messages in dmesg, maybe the chipset has an error,
# so we have to restart the device. 
function handle_wl18xx_error () {
    if ! is_carrier_up 
    then
	detect_wlan_chipset
	if [ $? == 2 ]
	then
	    echo "handle_wl18xx_error - wlan configured and essid in reach - but not connected - maybe wl18xx bug..."
	    # Bugfix for crashed wl18xx module
	    WL18BUG=0
	    if dmesg | grep "WARNING: at backports/drivers/net/wireless/ti/wlcore" > /dev/null
	    then                                                                         
		echo "FATAL: wl18xx kernel module caused kernel errors. Restarting network device"
		dmesg -c > ${HOME}/plusoptix/log/wl18xx-driver-bug-`date +%Y%m%d-%H%M`
		WL18BUG=1
	    fi  
	    
	    while ! ls /tmp/iw-* > /dev/null
	    do
		echo "Waiting for first run of wlan-scan..."
		sleep 1
	    done
	    while [ -f /var/run/wlan-scan.pid ]
	    do
		echo "scan running..."
		sleep 1
	    done
	    if configured_cells_match_ssid_list || [ $WL18BUG == 1 ]
            then
		ifdown ${WLANINTERFACENAME}
		rmmod wl18xx
		modprobe wl18xx 
		ifup ${WLANINTERFACENAME}
		sleep 2
		restart_dhcp
		sleep 2
            else
		echo "handle_wl18xx_error - nothing to do - out of reach"
	    fi
	else	
	    echo "handle_wl18xx_error - nothing to do - not Rev. G + wl18xx"
	fi
    else
	if ! have_ip
	then
	    echo "handle_wl18xx_error - link up, but no ip - restart dhcp"
	    restart_dhcp
	else
	    echo  "handle_wl18xx_error - nothing to do - carrier up"
	fi
    fi
}
# echos selection of ssid list by combobox  - and echo only that! If you debug out some else, the Xdialog will fail!
function select_essid_from_list () {
    local RV=1
    # for the dialog we need no debug out, else the output fails!
    # So: Locally unset it, after processing the function, we return to the defaults
    local -
    #OLDOPTS=$(set +o)
    set +xv
    detect_wlan_chipset
    if list=$(iw dev ${WLANINTERFACENAME} scan | grep "SSID: "| cut -f 2 -d " "| grep -v "^[ ]*$")
    then
	debugout "Found ESSID list: " > /tmp/select_essid_from_list.debug
	debugout $list >> /tmp/select_essid_from_list.debug
	PoDialog --combobox "     Select network to connect with    " 0 0  $list  2>&1
	RV=$?
	# return the user selection: 0=ok, 1=cancel
    fi
    #eval $OLDOPTS
    return $RV
}
# central methods of calls of services which should be started or stopped after network was started or stopped
# Params:
# $1 Interface like "wlan0", "eth0",...
# $2 Mode either "start" or "stop" else unsupported
# $3 Method either "static" or "dhcp" else unsupported
function if_up_down_actions () {
    local IFACE=$1
    local MODE=$2
    local METHOD=$3
    detect_wlan_chipset
    if [ x$METHOD == x"dhcp" ] || [ x$METHOD == x"static" ]; then
	if [ x$IFACE == "x${WLANINTERFACENAME}" ] || [ x$IFACE == "xeth0" ]; then 
	    # In the case wl18xx errors appear (wlan configured, but is not connected or has no ip), enable this line:
	    #if [ x$MODE == "xstart" ] && [ x$IFACE == "x${WLANINTERFACENAME}" ]; then
	    #   handle_wl18xx_error &  
	    #fi
	    if  [ x$MODE == "xstart" ] && [ x$METHOD == x"static" ]; then
		static_ip_setup
	    fi
	    ( [[ -f /etc/init.d/samba ]] && /etc/init.d/samba $MODE 
	      if [ -f /home/plusoptix/startssh ]; then
		  if [[ -f /etc/init.d/sshd ]]; then
		      /etc/init.d/sshd $MODE
		  elif [[ -f /etc/init.d/dropbear ]]; then
		      /etc/init.d/dropbear $MODE;
		  fi
		  if [[ -f /etc/init.d/lighttpd ]]; then
		      bash /home/plusoptix/plusoptix/program/create_self_signed_ssl_certificate.sh
		      bash /home/plusoptix/plusoptix/program/check_lighttpd.sh
		      if [[ $MODE == start ]] && ps aux | grep '[l]ighttpd'; then
			  /etc/init.d/lighttpd restart
		      else
			  /etc/init.d/lighttpd $MODE
		      fi
		  fi
	      fi
	      # see bug 7749 - ignore the ntp daemon - activate it, when you want it
	      #/etc/init.d/ntpd $MODE
	      if [ x$MODE == "xstop" ]; then
		  force_shutdown_network ${IFACE}
	      fi
	      # See wlan-functions.sh:start_avahi - maybe that is the better solution
	      # DEPRECATED: takes long and is not needed. off for now, gs, 20191014
	      #/etc/init.d/avahi-daemon $MODE
	      
	      # if [ $MODE == "start" ] && have_ip; then
              #     IP=`have_ip`
	      #     busybox httpd -p ${IP}:8080 -h /home/plusoptix/plusoptix/log
	      # else
	      #     killall busybox || true
	      #fi
	      
	    ) &
	else
	    echo "if_up_down_actions: Unsupported interface: $IFACE"
	fi
    else
	echo "if_up_down_actions: Unsupported method: $METHOD"
    fi

}   

# Special handling for the issue #10620
# In 1 of 7 cases during the boot sequence the dhcpcd failed to get a network address
# In this cases we have to restart network 
function fix_rev_h_dhcp_issue () {
   detect_wlan_chipset
   detect_current_nw_if
   ( sleep 15 
   if [ ${BOARDREVISION} == "H" ] && is_carrier_up && ! ps aux | grep dhcpcd  | grep -v grep ; then
       echo "Fix missing dhcpcd for Rev H devices - see bug 10620"
        if ! wait_for_ip; then 
	    echo "bugfix 10620 - hard reset needed"
 	   network_stop	
	   if rmmod ${WIFIMODULES}; then
	       prestart_network ${WLANINTERFACENAME}
	       /etc/init.d/networking start
	   fi
	else
		echo "dhcpcd restarted - "`have_ip` >> /home/plusoptix/plusoptix/program/test_network_at_boot.csv

        fi
    touch /home/plusoptix/plusoptix/test/reboot
   else
	echo "Fix missing dhcpcd for Rev H devices - ignored"
	have_ip
	is_carrier_up
	
   fi ) & 

}
