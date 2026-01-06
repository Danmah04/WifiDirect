export DISPLAY=:0.0
export HOME=/home/plusoptix
export XDG_RUNTIME_DIR=/var/volatile/tmp/runtime-root
prgdir=${HOME}/plusoptix/program
export LD_LIBRARY_PATH=/usr/lib:$LD_LIBRARY_PATH
export LC_ALL=en_US.utf8
X_UP=1
if [ -z $USER ] 
then
    export USER=root
fi

GUIAPP=qtopia_gui

sdavail_flag=/tmp/sdavail
uip_flag=/tmp/uip

po_serial_file=/tmp/poserialnumber
gui_started_flag=/tmp/guistarted

# watchforstorage.sh:
watchforstorage_flag=/tmp/watchforstorage_run
EXTERNAL_DEVICE_TMP=/tmp/externalstorage

# checkerror filenames:
fname_rt=${HOME}/plusoptix/log/gusererror-rt
fname_ui=${HOME}/plusoptix/log/gusererror-ui
fname_sdcarda=${HOME}/plusoptix/log/gusererror-sdcarda

screenshot_active_flag=2
videoload_active_flag=2
videosave_active_flag=2
hpprinter_active_flag=2

function write_con {
    if [ -e /dev/ttyUSB0 ]; then
	echo "$1" >/dev/ttyUSB0
    else
	if isX12 || isX16; then
	    echo "error: no EMAR_CON"
	fi
    fi
}
function check_x11 {
    if xhost + 2>/dev/null >/dev/null
    then
	#echo "X11 running"
	X_UP=0
    fi
}
function init_cores {
    echo '/var/cores/%e' >/proc/sys/kernel/core_pattern
    mkdir -p /var/cores
    chmod 777 /var/cores
    ulimit -c 0
}
function screenshot_active {
    if [ $screenshot_active_flag -eq 2 ]; then
	cat $prgdir/PlusoptixQtDesktopGui.cfg | grep "EnableScreenshots4Docu=1" >/dev/null
	screenshot_active_flag=$?
    fi
    [ $screenshot_active_flag -eq 0 ]
}
function videoload_active {
    if [ $videoload_active_flag -eq 2 ]; then
	cat $prgdir/PlusoptixQtDesktopGui.cfg | grep "EnableLoadVideo=1" >/dev/null
	videoload_active_flag=$?
    fi
    [ $videoload_active_flag -eq 0 ]
}
function videosave_active {
    if [ $videosave_active_flag -eq 2 ]; then
	cat $prgdir/PlusoptixQtDesktopGui.cfg | grep "EnableSaveVideo=1" >/dev/null
	videosave_active_flag=$?
    fi
    [ $videosave_active_flag -eq 0 ]
}
function hpprinter_active {
    if [ $hpprinter_active_flag -eq 2 ]; then
    	cat $prgdir/../data/default-printer-queue | grep [34] >/dev/null
    	hpprinter_active_flag=$?
    fi
    [ $hpprinter_active_flag -eq 0 ]
}

# Small helper, which detects if the wlan0 interface is up - may have no carrier - check with is_carrier_up
# @return 0 (true) if up, else (false) if down
function is_wlan_up () {
    if ip link show wlan0 >/dev/null 2>/dev/null ; then                 
	ip link show wlan0 | grep ",UP" 2>/dev/null >/dev/null
    else                             
	return 1                                             
    fi 
}
# Small helper, whether the eth0 is up, if available
# @return 0 (true) if up and has carrier, else (1): no carrier
function is_lan_up () {
    if ip link show eth0 >/dev/null 2>/dev/null ;then
	ip link show eth0 | grep ",UP" | grep -v "NO-CARRIER" >/dev/null 2>/dev/null
    else                             
	return 1                                             
    fi
}
# return: true/0 OTG active
function otg_active {
    if hpprinter_active || is_wlan_up || is_lan_up || isOpti || isX18 || isX20
    then
	false
    else
	true
    fi
}
function is_sd_mounted {
    mount | grep /home/plusoptix/plusoptix/sd >/dev/null
}

function is_usb_mounted {
    mount | grep /home/plusoptix/plusoptix/usb >/dev/null
}

function request_support_ext_drive {
    if isX16 || isOpti ;then
	sd_request
    else
	is_usb_mounted
    fi
}

function release_support_ext_drive {
    if isX16 || isOpti ;then
	sd_release
    fi
}

function sd_request {
    $prgdir/sdcardaccess request
}
function sd_release {
    $prgdir/sdcardaccess release
}
function sd_access {
    $prgdir/sdcardaccess used
}
function sd_fstype {
    cat $sdavail_flag | cut -d ":" -f 1
}
function sd_devname {
    cat $sdavail_flag | cut -d ":" -f 2
}
function sd_mountpoint {
    cat $sdavail_flag | cut -d ":" -f 3
}
function sdavail_set {
    fstype=$2
    devname=$3
    mountpoint=$4
    if [ $1 -eq 0 ]
    then
	echo "$fstype:$devname:$mountpoint" >$sdavail_flag
    else
	rm $sdavail_flag
	# while sd_release #reset count to 0
	# do
	#     :
	# done	
    fi
}
function sdavail_check {
    [ -e $sdavail_flag ]
}
function uip_set {
    if [ $1 -eq 0 ]
    then
	touch $uip_flag
    else
	rm $uip_flag
    fi
}
# Update in Progress?
# true = yes
function uip_check {
    [ -e $uip_flag ]
}
function otg_ums_on {
    if isX12; then
	modprobe -r g_mass_storage
	modprobe phy_twl4030_usb
	modprobe omap2430
	modprobe musb_hdrc
	modprobe g_mass_storage file=$1 ro=y removable=y stall=0 || true
    fi
}
function otg_ums_off {
    if isX12; then
	modprobe -r g_mass_storage
    fi
}

simul () {
    stop_rt_gui
    stop_smartcard
    killall X
    echo starting all over 3
    sleep 1
    echo starting all over 2
    sleep 1
    echo starting all over 1
    sleep 1
    echo starting all over 0
    startx &
    start_rt &
}
start_support () {
    if [ -e ${prgdir}/system ]
    then
	cd ${prgdir}/system
	sh system.sh
	exit
    fi 
}
runcheck () {
  ps aux | grep -v grep | grep $1
}
checkkill () {
    runcheck $1
    if [ $? -eq 0 ]
    then
	kill -$2 $1
    fi
}

### rt ###
set_camera () {
    if isX20 || isOpti || isX18;then
	echo "Camera is initialized by eval_rt"
    else
	if isX16;then
	    # Setze Kamera Versorgung
	    i2cset -y 3 0x76 0x0B 0x01
	    sleep 1
	    i2cset -y 3 0x76 0x17 
	elif isX12;then
	    # Setze Kamera Versorgung
	    i2cset -y 3 0x77 0x0B 0x01
	    sleep 1
	fi
	
	if i2cget -y 3 0x18 ;then
	    echo 1 > /tmp/camera
	    modprobe ad9891 camera=1
	    #See Bug 4328
	    if isX16;then
		i2cset -y 3 0x76 0x13 0x2e 0xe0 0x55 0xf0 i
	    elif isX12;then
		i2cset -y 3 0x77 0x13 0xa2 0x44 i
	    fi
	else
	    echo 0 > /tmp/camera
	    modprobe ad9891 camera=0
	    #See Bug 2984
	    if isX12;then
		i2cset -y 3 0x77 0x13 0xB1 0x3A i
	    fi
	fi
    
	stop_camera
    fi
}

get_camera () {
    if grep '1' /tmp/camera &> /dev/null ;then
	echo "cmos"
    else
	echo "ccd"
    fi
}

start_camera () {
    if ! isOpti && ! isX20 && ! isX18;then
	if isX16;then
	    # Setze Kamera Versorgung
	    i2cset -y 3 0x76 0x0B 0x01
	    sleep 1
	    i2cset -y 3 0x76 0x17 
	elif isX12; then
	    # Setze Kamera Versorgung
	    i2cset -y 3 0x77 0x0B 0x01
	    sleep 1
	fi
	
	# Sende camera.conf
	cd ${prgdir}
	if [[ $(get_camera) == "cmos" ]];then
	    ./setcamera_aptina camera_aptina.conf
	elif [[ $(get_camera) == "ccd" ]];then
	    # Setze Takt
	    i2cset -y 3 0x69 0x0C 0x08
	    i2cset -y 3 0x69 0x47 0x08
	    i2cset -y 3 0x69 0x13 0x80
	    i2cset -y 3 0x69 0x0C 0x10
	    i2cset -y 3 0x69 0x40 0xC0
	    i2cset -y 3 0x69 0x41 0x0C
	    i2cset -y 3 0x69 0x42 0x00
	    i2cset -y 3 0x69 0x09 0x10

	    if isX16;then
		./setcamera 76 >/dev/null
	    elif isX12; then
		./setcamera 77 >/dev/null
	    fi
	fi
    fi
}
stop_camera () {
    if isX16;then
	i2cset -y 3 0x76 0x0B 0x00
    elif isX12; then
	i2cset -y 3 0x77 0x0B 0x00
    fi
}
init_omap3isp () {
    UNLOADMODULES="omap3_isp iommu2 ad9891 iovmm iommu"
#    LOADMODULES="iommu2 omap3_isp omap_vout"
    SLEEPTIME=0
    
    if false
    then
	for mod in $UNLOADMODULES
	do
	    if [[ ! -z $(lsmod |grep  ^${mod}) ]]
	    then
		echo modprobe -r $mod
		modprobe -r $mod
		sleep ${SLEEPTIME}
	    fi
	done

	sleep  ${SLEEPTIME}
    fi

    for mod in $LOADMODULES
    do
	if [[ -z $(lsmod |grep  ^${mod}) ]]
	then
	    echo modprobe $mod
	    modprobe $mod
	    sleep  ${SLEEPTIME}
	fi
    done
}
stop_checkerror() {
    for i in `ps aux | grep checkerror | grep bash | sed "s/\( \)*/\1/g" | cut -d " " -f 2`
    do
	kill -1 $i
    done
}
start_checkerror() {
    ps aux | grep checkerror.sh | grep bash
    if [ $? -ne 0 ] 
    then
	bash ${prgdir}/checkerror.sh &
    else
	echo start_checkerror: already running
    fi
}
restart_checkerror() {
    stop_checkerror
    sleep 1
    start_checkerror
}

start_cupsclean() {
    ps aux | grep cups-clean.sh | grep bash
    if [ $? -ne 0 ] 
    then
	bash ${prgdir}/cups-clean.sh &
    fi
}
start_print_spooler () {
    [[ ! -d /tmp/pdf ]] && mkdir /tmp/pdf

    if ! pgrep -f poprintspooler
    then
	nice -19 ${prgdir}/poprintspooler&
    fi
}

stop_print_spooler () {
  killall -9 poprintspooler
  while pgrep -f poprintspooler
  do
      killall -9 poprintspooler
  done
}

start_pdf_copy () {
    local dev=${1}
    
    if ! pgrep -f pdfcopybase.sh
    then
	nice -19 bash ${prgdir}/pdfcopy.sh /tmp/pdf ${dev} &
    fi
}

stop_pdf_copy () {
    pkill -9 -f pdfcopy.sh
    pkill -9 -f pdfcopybase.sh
}

start_rt () {
    rc=0
    if [[ ! -z ${plog} ]];then
	echo "++++++++++++++++++Restart `date` +++++++++++++++++++++++++" >> /home/plusoptix/plusoptix/log/eval_rt.log
	${prgdir}/eval_rt >> /home/plusoptix/plusoptix/log/eval_rt.log 2>&1
	rc=$?
    else
	${prgdir}/eval_rt
	rc=$?
    fi
    # ignore kill -1 and kill -9 
    if [ $rc -ne 0 ] && [ $rc -ne 137 ]
    then
	echo -n `date +%Y%m%d-%H%M%S` >>$fname_rt
	echo " RT exit code: " $rc >>$fname_rt
    fi
}
start_gui () {
    PARAM=
    if isOpti || isX18 || isX20; then
	while [[ ! -e /dev/ttyAMA1 ]]; do
	    echo "Waiting for /dev/ttyAMA1 to be ready..." >> /tmp/waitingformxc1
	    sleep 1
	done
    fi
    rc=0
    touch $watchforstorage_flag
    if [[ ! -z ${plog} ]];then
	echo "++++++++++++++++++Restart `date` +++++++++++++++++++++++++" >> /home/plusoptix/plusoptix/log/qtopia_gui.log
	${prgdir}/${GUIAPP} >> /home/plusoptix/plusoptix/log/qtopia_gui.log 2>&1
	rc=$?
    else
	local program=""
	if [[ $1 == gdb ]]; then
	    program="gdbserver :1234"
	elif [ -f ${HOME}/squish/bin/startaut ]; then
            echo Start with squish
            program="${HOME}/squish/bin/startaut --port=4333 "
        fi                                   
        ${program} ${prgdir}/${GUIAPP}   
	rc=$?
    fi
    # ignore kill -1 and kill -9 
    if [ $rc -ne 0 ] && [ $rc -ne 137 ]
    then
	echo -n `date +%Y%m%d-%H%M%S` >>$fname_ui
	echo " GUI exit code: " $rc >>$fname_ui
    fi
    [[ -f ${gui_started_flag} ]] && rm ${gui_started_flag}
}
stop_rt_gui () {
    rm $watchforstorage_flag
   
    stop_xautolock
    
    killall -1 ${GUIAPP}
    sleep 1
    killall -1 eval_rt
   
    sleep 2

    killall -9 ${GUIAPP}
    killall -9 eval_rt
}
### end rt ###

### smartcard ###
install_smartcard () {
    type pcscd
    if [ $? -ne 0 ]
    then
	opkg install pcsc-lite
    fi
    type openct-control
    if [ $? -ne 0 ]
    then
	opkg install openct
    fi
    if false 
    then
	type lsof
	if [ $? -ne 0 ]
	then
	    opkg install lsof
	fi
    fi

    mkdir /var/run/openct
}
start_smartcard () {
    if isX12 ;then
	rm /var/run/openct/0
	mkdir /var/run/openct
	openct-control init
        #lsof | grep ifdhand
	count=0
	while [ ! -e /var/run/openct/0 ]
	do
	    echo waiting for ifdhandler socket
	    count=$(($count + 1))
	    if [ $count -gt 5 ] # do not wait longer than 5s
	    then
		return
	    fi
	    sleep 1
	done
	pcscd -f -c /etc/reader.conf.d/reader.conf&
    fi
}
stop_smartcard () {
    killall pcscd
    openct-control shutdown
    sleep 1
    killall -9 pcscd
}
restart_smartcard () {
    stop_smartcard
    start_smartcard
}
### end smartcard ###


show_tipoftheday () {
   if [[ -f ${HOME}/plusoptix/log/errormsg ]];then
       PoDialog --msgbox "`cat ${HOME}/plusoptix/log/errormsg`" 0 0
       rm ${HOME}/plusoptix/log/errormsg
   fi
}

isUpdateMode () {
    grep update /proc/cmdline &> /dev/null
}

setGuiConfDir () {
    GUICONFDIR=${prgdir}
    local mounttmp=${HOME}/plusoptix/sd
    local guicfg=PlusoptixQtDesktopGui.cfg

    # in the case of an update, we use the config from the to-be-updated-system.
    if isUpdateMode ;then
	if [[ ! -d /tmp ]];then
	    echo "/tmp not yet available"
	    return
	fi
	if [[ ! -f /tmp/${guicfg} ]];then
	    if isOpti || isX18 || isX20;then
		[[ ! -d ${mounttmp} ]] && mkdir ${mounttmp}
		mount /dev/mmcblk0p5 ${mounttmp}
		if [[ -f ${mounttmp}/upperdir${prgdir}/${guicfg} ]];then
		    cp ${mounttmp}/upperdir${prgdir}/${guicfg} /tmp/${guicfg}
		    GUICONFDIR=/tmp
		fi
		umount ${mounttmp}
	    else
		mount /dev/mmcblk0p2 ${mounttmp}
		if [[ -f ${mounttmp}${prgdir}/${guicfg} ]];then
		    cp ${mounttmp}${prgdir}/${guicfg} /tmp/${guicfg}
		    GUICONFDIR=/tmp
		fi
	    	umount ${mounttmp}
	    fi
	else 
	    GUICONFDIR=/tmp
	fi
    fi
}

# When using translation, find out, which language is set at the gui,
# and call one time "gettext <something>" You can use translation by
# adding a tr in front of a text string like "`tr "yes"`".   
#  ~/plusoptix/program/i18n/init_gettext.sh  will find this strings 
# and will output po-syntax of this phrases. Therefore we need the 
# current set language. 
function init_gettext () {
	 export LC_ALL=en_US.utf8 
	 export LANG=$LC_ALL	 
	 export LC_MESSAGES=$LANG
	 
	 TEXTDOMAIN=poscripts
	 TEXTDOMAINDIR=${HOME}/plusoptix/i18n

	 setGuiConfDir
	 
	 #for screenshot creation tool
	 if [[ -f /tmp/newGUILanguage ]];then
	     PO_LANG_ID=$(cat /tmp/newGUILanguage)
	 else
	     PO_LANG_ID=$(grep language ${GUICONFDIR}/PlusoptixQtDesktopGui.cfg | cut -f 2 -d "=")
	 fi
	 case $PO_LANG_ID in 
	     0)
		 export LANGUAGE="cs_CZ.utf8"
		 ;;
	     1)	
		 export LANGUAGE="da_DK.utf8"
		 ;;
	     2)
		 export LANGUAGE="de_DE.utf8"
		 ;;
	     3)
		 export LANGUAGE="nl_NL.utf8"
		 ;;
	     4 | 5)
		 export LANGUAGE="en_US.utf8"
		 ;;
	     6)
		 export LANGUAGE="fi_FI.utf8"
		 ;;
	     7)
		 export LANGUAGE="fr_FR.utf8"
		 ;;
	     8)
		 export LANGUAGE="hu_HU.utf8"
		 ;;
	     9)
		 export LANGUAGE="it_IT.utf8"
		 ;;
	     10)
		 export LANGUAGE="nb_NO.utf8"
		 ;;
	     11)
		 export LANGUAGE="pl_PL.utf8"
		 ;;
	     12 | 13)
		 export LANGUAGE="pt_PT.utf8"
		 ;;
	     14 | 15)
		 export LANGUAGE="es_ES.utf8"
		 ;;
	     16)
		 export LANGUAGE="sv_SE.utf8"
		 ;;
	     17)
		 export LANGUAGE="tr_TR.utf8"
		 ;;
	     18)
		 export LANGUAGE="et_EE.utf8"
		 ;;
	     19)
		 export LANGUAGE="ru_RU.utf8"
		 ;;
	     20)
		 export LANGUAGE="bs_BA.utf8"
		 ;;
	     21)
		 export LANGUAGE="bg_BG.utf8"
		 ;;
	     22)
		 export LANGUAGE="hr_HR.utf8"
		 ;;
	     23)
		 export LANGUAGE="fa_IR.utf8"
		 ;;
	     24)
		 export LANGUAGE="el_GR.utf8"
		 ;;
	     25)
		 export LANGUAGE="lv_LV.utf8"
		 ;;
	     26)
		 export LANGUAGE="lt_LT.utf8"
		 ;;
	     27)
		 export LANGUAGE="mk_MK.utf8"
		 ;;
	     28)
		 export LANGUAGE="ro_RO.utf8"
		 ;;
	     29)
		 export LANGUAGE="sr_ME.utf8"
		 ;;
	     30)
		 export LANGUAGE="sk_SK.utf8"
		 ;;
	     31)
		 export LANGUAGE="sl_SI.utf8"
		 ;;
	     32)
		 export LANGUAGE="ar_JO.utf8"
		 ;;
	     33)
		 export LANGUAGE="uk_UA.utf8"
		 ;;
	     34)
		 export LANGUAGE="be_BY.utf8"
		 ;;
	     35)
		 export LANGUAGE="th_TH.utf8"
		 ;;
	     36)
		 export LANGUAGE="ja_JP.utf8"
		 ;;
	     37)
		 export LANGUAGE="zh_CN.utf8"
		 ;;
	     38)
		 export LANGUAGE="he_IL.utf8"
		 ;;
	     39)
		 export LANGUAGE="ko_KR.utf8"
		 ;;
	     40)
		 export LANGUAGE="zh_TW.utf8"
		 ;;
	     *)
		 export LANGUAGE="en_US.utf8"
		 ;;
	 esac
	 export LC_ALL=$LANGUAGE
	 export LANG=$LANGUAGE
	 export LC_MESSAGES=$LANGUAGE

         echo found lang=$PO_LANG_ID = $LANGUAGE / TEXTDOMAIN=$TEXTDOMAIN / TEXTDOMAINDIR=$TEXTDOMAINDIR
         # We need this call here, to let "`gettext "xx"`" expression work: 
	 gettext "yes" > /dev/null
}
# translation helper for gettext
function tr () {
    init_gettext  > /dev/null
    TEXTDOMAINDIR=$TEXTDOMAINDIR gettext -n -d $TEXTDOMAIN "$1"
}
function PoDialog_off () {
    eval Xdialog "--wrap --rc-file=${HOME}/xdialog.rc" '$@'
}
# Wrapper for Xdialog using translation function tr () 
function PoDialog () {
    init_gettext > /dev/null
    #set -xv
    check_x11
    if [ $X_UP == 1 ]
    then
	echo "X11 not up: $@" 
    else 
	newargs=
	defaultparams="--wrap --rc-file=${HOME}/xdialog.rc"
	#echo Parameter:"${p}":
	for p in "$@"
	do
	    case "${p}" in 
		-*)
		    if [[ ${p} == "--yesno" ]];then
			newargs="$newargs --ok-label \"Ok\" --cancel-label \"Close\" $p"
		    elif [[ ${p} == "--yesno_mod" ]];then
			p_mod="$(echo ${p} |cut -c13-)"
			newargs="$newargs --yesno $p_mod"
		    else
			newargs="$newargs $p"
		    fi
		    ;;
		--*)
		    newargs="$newargs $p"
		    ;;
		[0-9]*)
		    newargs="$newargs $p"
		    ;;
		tr\ *)
		#echo Text: ${p}
		    txt="$(echo ${p} |cut -c4-)"
		    echo "$txt"
		    newargs="${newargs} \"`tr \"${txt}\"`\""
		#echo $newargs
		    ;;
		*)
		#echo Text: ${p}
		#newargs="${newargs} \"`tr \"${p}\"`\""
		#echo $newargs
		    newargs="$newargs \"$p\""
		    ;;
	    esac
	done
        #echo $newargs
	unset LANGUAGE
	export LANGUAGE
	eval podialog "${newargs}"
	#eval Xdialog ${defaultparams} "${newargs}"
        #eval Xdialog "${defaultparams} \"$@\""
    fi
}
function restart {
    cd ${prgdir}
    stop_rt_gui
    stop_print_spooler
    start_print_spooler&
    start_rt&
    start_gui $1 &
    start_xautolock&
    ( sleep 6 & ${prgdir}/setup-samba-security.sh silent ) & 
    cd -
    sleep 1
    if ls ${EXTERNAL_DEVICE_TMP}/* ; then
	echo "Call ignored udev events while gui was down ($(ls ${EXTERNAL_DEVICE_TMP}/*))..." >> /tmp/mounlog
	touch $(ls ${EXTERNAL_DEVICE_TMP}/*);
    fi
    #echo "Reset retrigger udev..."
    #udev_retrigger
}
# Check if there was a device check already
function device_detected {
    [ -f /tmp/x12 ] || [ -f /tmp/x16 ] || [ -f /tmp/opti ] || [ -f /tmp/x18 ] || [ -f /tmp/x20 ]
}
# Set the device by creating a file at /tmp/ like /tmp/x16
# Check by chip addresses 
# detect X12 by its chip address 0x77
# X16 has chip addresses 0x72 and 0x75
# Optiscope has chip addresses 0x72 and 0x76
function detect_device_set {
    if ! device_detected; then
	if i2cget -y 3 0x77 0x00; then
	    touch /tmp/x12
	elif i2cget -y 3 0x75 0x00; then
	    touch /tmp/x16
	else
	    i2ctransfer -y 1 w2@0x76 0x01 0x01
	    sleep 0.1
	    case $(i2ctransfer -y 1 r2@0x76) in
		"0x01 0x00")
    		    touch /tmp/opti
		    ;;
		"0x02 0x00")
		    touch /tmp/x20
		    ;;
		"0x07 0x00")
		    touch /tmp/x18
		    ;;
	    esac
	fi
    fi
    return 0
}
# just a getter for X12
function isX12 {
    detect_device_set
    [ -f /tmp/x12 ]
}
# just a getter for X16
function isX16 {
    detect_device_set
    [ -f /tmp/x16 ]
}
# just a getter for X18
function isX18 {
    detect_device_set
    [ -f /tmp/x18 ]
}
# just a getter for X20
function isX20 {
    detect_device_set
    [ -f /tmp/x20 ]
}
# just a getter for the Optiscope
function isOpti {
    detect_device_set
    [ -f /tmp/opti ]
}
function fix_display_quality () {
    # increase quality of the display, later this will be done by the atmel itself: 
    i2cset -y 3 0x6e 0x00 0x11                                                     
    # low quality:                                                              
    # i2cset 3 0x6e 0x00 0x00 
}

#Link serial device ttyO0 to ttyUSB0 when on X16
#or serial device ttyAMA3 to ttyAMA1 when on X20  
function link_serial_device () {
    if isX16 && [[ ! -c /dev/ttyUSB0 ]];then
	cd /dev
	ln -s ttyO0 ttyUSB0
	cd -
    elif { isX20 || isX18; } && [[ ! -c /dev/ttyAMA1 ]];then
	cd /dev
	ln -s ttyAMA3 ttyAMA1
	cd -
    fi
}

# Do some i2c device linking
function fix_i2c_namings () {
    if dmesg | grep 'Raspberry Pi' && [[ ! -c /dev/i2c-3 ]];then
	cd /dev
	ln -s i2c-1 i2c-3
	cd -
    elif [[ ! -c /dev/i2c-3 ]];then
	cd /dev
	ln -s i2c-2 i2c-3
	cd -
    fi
}

#Initialize serial logging for battery check
function init_serial_log () {
    local file=${1:-/tmp/battery}
    if isX12;then
	stty -F /dev/ttyUSB0 1:0:8fd:0:3:1c:7f:15:4:5:1:0:11:13:1a:0:12:f:17:16:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0 
	cat /dev/ttyUSB0 > ${file} &
    fi
}

# Initial battery check and reboot if wrong
function init_battery_state () {
    if isX12 && [[ ! -f /tmp/battery_checked ]];then
	write_con M0P
	sleep 1
	bash /home/plusoptix/plusoptix/program/battery-check.sh
	ret=$?
	if [[ ${ret} -gt 0 && ${ret} -ne 5 ]];then
	    cat /tmp/battery >> ${HOME}/plusoptix/log/batterylog-$(date +%Y%m%d-%H%M%S)
	    Xdialog --wrap --rc-file=${HOME}/xdialog.rc --no-buttons --infobox "\nWARNING!!!\n\nBatteries inserted incorrectly! Please check!\nShutting down...\n" 0 0 10000
	    /home/plusoptix/plusoptix/program/shutdown.sh &
	    return 1
	fi
    fi
    return 0
}
# Detect, if we are connected to power supply
function check_power_mode () {
    if isX12;then
	local once=${1}
	while
	    init_serial_log /tmp/serial.log

	    for i in $(seq 1 3); do
		write_con "M0P"
		sleep 1
	    done

	    killall cat

	    local state_count=$(grep -o ":1." /tmp/serial.log | wc -l)

	    #if we only want power state once without msg
	    if [[ -n ${once} ]];then
		local ret=0
		[[ ${state_count} -lt 3 ]] && ret=1
		return ${ret}
	    fi

	    [[ ${state_count} -lt 3 ]] && PoDialog --msgbox "`tr "Running in battery mode.\nConnect device to the power supply and press OK."`" 0 0
	do
	    :
	done
    elif isOpti || isX18 || isX20 ;then
	while
	    i2cset -y 3 0x76 0x07 0xff
	    sleep 0.5
	    local power_mode=$(i2cget -y 3 0x76)

	    [[ ${power_mode} -ne 0x1 ]] && PoDialog --msgbox "`tr "Running in battery mode.\nConnect device to the power supply and press OK."`" 0 0
	do
	    :
	done
    fi
}
# Writes atmel version like 02 or 09 into a file called /tmp/atmel and returns 0 when successfull 
function get_atmel_version () {
    set +xv
    # illegal: "set -xv", destroys parser!
    echo "get_atmel_version - `date`" >> /tmp/atmel_update
    ATMEL_VERSION_FILE=/tmp/atmel                    
    if [ ! -f ${ATMEL_VERSION_FILE} ] || [ -z $(cat ${ATMEL_VERSION_FILE}) ]
    then
	# default case: no file found, because we call it during update 
        echo "No ${ATMEL_VERSION_FILE} found or empty, try to get version from atmel." >> /tmp/atmel_update
	rm -f ${ATMEL_VERSION_FILE} ${ATMEL_VERSION_FILE}_raw
	if [ -z "`ps aux |grep eval_rt | grep -v grep`" ]       
	then  
 	    rm ${ATMEL_VERSION_FILE}_raw
	    COUNTER=1
	    # Try up to 10 times and increase sleep while waiting answer of atmel
	    while ([ -z $(cat ${ATMEL_VERSION_FILE}_raw) ] || [ -z $(cat ${ATMEL_VERSION_FILE}) ]) && [ $COUNTER -lt 10 ]
	    do
		cat /dev/ttyUSB0  > ${ATMEL_VERSION_FILE}_raw &
		CATPID=$! 
	        sleep 1
		write_con "@"
		sleep ${COUNTER}
		kill ${CATPID}
		VER=$(cat ${ATMEL_VERSION_FILE}_raw | cut -c 4-5)
		echo 0x${VER} > ${ATMEL_VERSION_FILE}
		((COUNTER++))
	    done
	    
	    if [[ $(cat ${ATMEL_VERSION_FILE}) != '0x' ]];then
		VER=$(cat ${ATMEL_VERSION_FILE})
                echo "Atmel answered with version $VER." >> /tmp/atmel_update
	        echo $VER
                return 0
            else
		echo "${ATMEL_VERSION_FILE} empty" >> /tmp/atmel_update
		rm ${ATMEL_VERSION_FILE}
		return 2
	    fi
	else     
            echo "Doing nothing: eval_rt is running! Call this script earlier!" >> /tmp/atmel_update
            return 1
	fi                                                                      
    else
	# This happens, if you call it not during update, which means a second time after normal boot.
	VER=$(cat ${ATMEL_VERSION_FILE})
        echo "${ATMEL_VERSION_FILE} found with version $VER" >> /tmp/atmel_update
	echo $VER
        return 0
    fi
}


function update_controller() {
    local bootloader_tool=${prgdir}/sendhexi2c_xmega
    local controller=${1}
    local controller_i2c_address=${2}
    local current_controller_vers=${3}
    local new_controller_vers=${4}
    local controller_hex=${5}
    
    if [[ -n ${new_controller_vers} && -n ${current_controller_vers} && -f ${controller_hex} ]];then
	if version_greater ${new_controller_vers} ${current_controller_vers}; then
	    echo "Update ${controller} controller from version ${current_controller_vers} to ${new_controller_vers}"  >> ${logfile}
	    PoDialog --no-buttons --infobox "`tr "Updating firmware...\nDO NOT SWITCH DEVICE OFF!"`\nVersion ${current_controller_vers} ... ${new_controller_vers}" 0 0 1000000&
	    killall -1 eval_rt
	    killall -1 qtopia_gui
	    sleep 1
	    local counter=0
	    local ret=200
	    while [[ ${ret} -ne 0 && ${counter} -lt 5 ]]
	    do
		${bootloader_tool} ${controller_i2c_address} -pj ${controller_hex}
		ret=$?
		echo "Try ${counter} of sendhexi2c call returned with ${ret} ..." >> ${logfile}
		sleep 1
		((counter++))
	    done

	    if [[ ${ret} -ne 0 ]];then
		echo "Atmel update failed ${counter} times. Giving up!" >> ${logfile}
		killall Xdialog podialog
		cp ${logfile} ${final_logdir}/atmel_update_failed_`date +%Y%m%d-%H%M`		    
		PoDialog --infobox "`tr "Atmel update error!\nPlease contact Plusoptix support!"`\nLog: ${final_logdir}/atmel_update_failed_`date +%Y%m%d-%H%M`" 0 0 100000000000
		return 1
	    else
		echo "${controller} controller update finished `date`" >> ${logfile}
		killall Xdialog podialog
	    fi
	else
	    echo "${controller} controller update not needed, version newer or the same ${current_controller_vers} >= ${new_controller_vers}" >> ${logfile}
	fi
    else
	echo "${controller} controller update aborted, reason: version new: ${new_controller_vers}, version old: ${current_controller_vers}, controller hex: ${controller_hex}" >> ${logfile}
    fi
}

controller_vers_hex_to_dec () {
    local version_in_hex="${1}"
    
    local lsb_major=$(( $(echo ${version_in_hex} | cut -d' ' -f1) ))
    local msb_major=$(( $(echo ${version_in_hex} | cut -d' ' -f2) ))
    local lsb_minor=$(( $(echo ${version_in_hex} | cut -d' ' -f3) ))
    local msb_minor=$(( $(echo ${version_in_hex} | cut -d' ' -f4) ))
    local lsb_patch=$(( $(echo ${version_in_hex} | cut -d' ' -f5) ))
    local msb_patch=$(( $(echo ${version_in_hex} | cut -d' ' -f6) ))
    
    local full_major=$(( ((msb_major << 8) | lsb_major) ))
    local full_minor=$(( ((msb_minor << 8) | lsb_minor) ))
    local full_patch=$(( ((msb_patch << 8) | lsb_patch) ))

    echo ${full_major}.${full_minor}.${full_patch}
}

get_current_controller_version () {
    local controller_i2c_address=${1}
    i2ctransfer -y 3 w2@${controller_i2c_address} 0 0
    sleep 0.1
    i2ctransfer -y 3 r7@${controller_i2c_address}
}

# Perform a atmel firmware update
# Check version from ${prgdir}/EMAR_CON.hex, compare it to current installed version with get_atmel_version and start avrdude
# see /tmp/atmel_update log 
function atmel_update() {
    echo "See /tmp/atmel_update for logs"
    echo "atmel_update - `date`" >> /tmp/atmel_update
    local logfile=/tmp/atmel_update
    local final_logdir=${HOME}/plusoptix/log
    local controller_hex_dir=${prgdir}/controller
    if isX16;then
	local maincontroller_i2c_address=0x76
	local basecontroller_i2c_address=0x75
	local current_main_controller_vers=$(i2cget -y 3 ${maincontroller_i2c_address} 0x1E)
	local current_base_controller_vers=$(i2cget -y 3 ${basecontroller_i2c_address} 0x11)
	local new_main_controller_vers=$(cat ${controller_hex_dir}/main.ver)
	local new_base_controller_vers=$(cat ${controller_hex_dir}/base.ver)
	local main_controller_hex=${controller_hex_dir}/main.hex
	local base_controller_hex=${controller_hex_dir}/base.hex

	update_controller main ${maincontroller_i2c_address} ${current_main_controller_vers} ${new_main_controller_vers} ${main_controller_hex}
	update_controller base ${basecontroller_i2c_address} ${current_base_controller_vers} ${new_base_controller_vers} ${base_controller_hex}
	
	return 0
    elif isX20 || isX18; then
	local maincontroller_i2c_address=0x76
	local ledcontroller_i2c_address=0x74

	local current_main_controller_vers=$(controller_vers_hex_to_dec "$(get_current_controller_version ${maincontroller_i2c_address})")
	
	local current_led_controller_vers=$(controller_vers_hex_to_dec "$(get_current_controller_version ${ledcontroller_i2c_address})")

	if isX20; then
	    local new_main_controller_vers=$(cat ${controller_hex_dir}/px20_main.ver)
	    local new_led_controller_vers=$(cat ${controller_hex_dir}/px20_led.ver)
	    local main_controller_hex=${controller_hex_dir}/px20_main.hex
	    local led_controller_hex=${controller_hex_dir}/px20_led.hex
	else
	    local new_main_controller_vers=$(cat ${controller_hex_dir}/px18_main.ver)
	    local new_led_controller_vers=$(cat ${controller_hex_dir}/px18_led.ver)
	    local main_controller_hex=${controller_hex_dir}/px18_main.hex
	    local led_controller_hex=${controller_hex_dir}/px18_led.hex
	fi

	update_controller main ${maincontroller_i2c_address} ${current_main_controller_vers} ${new_main_controller_vers} ${main_controller_hex}
	update_controller led ${ledcontroller_i2c_address} ${current_led_controller_vers} ${new_led_controller_vers} ${led_controller_hex}
	
	return 0
    elif isX12; then
	local current_atmel_vers=$(get_atmel_version)
	if [[ $? -eq 0 ]];then
	    local atmel_hex=${controller_hex_dir}/EMAR_CON.hex
	    local new_atmel_vers=$(cat ${controller_hex_dir}/EMAR_CON.ver)
	    if [[ -n ${new_atmel_vers} && -n ${current_atmel_vers} && ${new_atmel_vers} -gt ${current_atmel_vers} && -f ${atmel_hex} ]];then
		echo "Atmel new version: ${new_atmel_vers} / current version: ${current_atmel_vers}" >> ${logfile}
		local blocked=0
		if [[ ${current_atmel_vers} -lt 0x06 ]];then
		    echo "NO Atmel update - current version too old: ${current_atmel_vers}, must be 0x06" >> ${logfile}
		    blocked=1
		#we call atmel_update in update-restart.sh at the moment; there is no /tmp/poserialnumber available and the following code will not be called
		#what is ok regarding to ok (Oliver), mm 20180131
		elif [[ -f ${po_serial_file} ]];then
		    # Excluded serial numbers from atmel update
		    local serial=$(grep "Device-ID:" ${po_serial_file} | cut -d ":" -f2 | cut -d " " -f2 | cut -c 1,2)
		    local tailserial=$(grep "Device-ID:" ${po_serial_file} | cut -d ":" -f2 | cut -d " " -f2 | cut -c 1,2,3 --complement)
		    if [[ -z ${serial} || -z ${tailserial} ]];then
			echo "NO Atmel update - SERIAL=${serial} or TAILSERIAL=${tailserial} is empty - fatal error " >> ${logfile}
			blocked=1
		    elif [[ (${serial} -eq 13 && ${tailserial} -lt 1002) ||  (${serial} -eq 12 && (${tailserial} -lt 1288 || (${tailserial} -gt 1312 && ${tailserial} -lt 1348) || (${tailserial} -gt 1350 && ${tailserial} -lt 1358) || (${tailserial} -gt 1358 && ${tailserial} -lt 1364) || (${tailserial} -gt 1365 && ${tailserial} -lt 1384) || (${tailserial} -gt 1384 && ${tailserial} -lt 1428) || (${tailserial} -gt 1428 && ${tailserial} -lt 1432) || ${tailserial} -eq 1438) ) ]];then
			echo "NO Atmel update - blocked serial: $serial - $tailserial" >> ${logfile}
			blocked=1
		    fi
		fi
		
		if [[ $blocked -eq 0 ]];then
		    echo ${serial} - ${tailserial}: Update atmel from version ${current_atmel_vers} to ${new_atmel_vers} >> ${logfile}
		    PoDialog --no-buttons --infobox "`tr "Updating firmware...\nDO NOT SWITCH DEVICE OFF!"`\nVersion ${current_atmel_vers} ... ${new_atmel_vers}" 0 0 1000000&
		    #X1PID=$! //we need PID of Xdialog not of PoDialog
		    killall -1 eval_rt
		    killall -1 qtopia_gui
		    sleep 1
		    check_power_mode
		    write_con $'\x1b'
		    sleep 0.1
		    write_con $'\x1b'
		    sleep 2
		    local counter=0
		    local ret=200
		    while [[ ${ret} -ne 0 && ${counter} -lt 5 ]]
		    do
			avrdude -p m8 -P /dev/ttyUSB0 -c avr910  -b 9600 -F -e -U flash:w:${atmel_hex}
			ret=$?
			echo "Try ${counter} of avrdude call returned with ${ret} ..." >> ${logfile}
			sleep 1
			((counter++))
		    done

		    if [[ ${ret} -ne 0 ]];then
			echo "Atmel update failed ${counter} times. Giving up!" >> ${logfile}
			killall Xdialog podialog
			PoDialog --infobox "`tr "Atmel update error!\nPlease contact Plusoptix support!"`\nLog: ${final_logdir}/atmel_update_failed_`date +%Y%m%d-%H%M`" 0 0 100000000000
			cp ${logfile} ${final_logdir}/atmel_update_failed_`date +%Y%m%d-%H%M`
			return 1
		    fi
		    write_con E
		    echo ${new_atmel_vers} > /tmp/atmel
		    echo "Atmel update finished `date`" >> ${logfile}
		    killall Xdialog podialog
		    return 0
		fi
	    elif [[ -n ${new_atmel_vers} && -n ${current_atmel_vers} && ${new_atmel_vers} == ${current_atmel_vers} ]];then
		echo "Atmel update not needed, same version ${current_atmel_vers} == ${new_atmel_vers}" >> ${logfile}
		return 0
	    else
		echo "Atmel update aborted, reason: version new: ${new_atmel_vers}, version old: ${current_atmel_vers}, atmel-prog: ${atmel_hex}" >> ${logfile}
	    fi
	fi
    fi
    return 0 
}

#Get distributor ID with image
function getDistIdForImage () {
    DISTFILE=/home/plusoptix/plusoptix/distributors/current
    DISTDIR=/home/plusoptix/plusoptix/distributors
    IMGFILE_X20=xbackground-1024x600.png
    IMGFILE_NOT_X20=xbackground-800x480.png

    if isX20;then
	IMGFILE=${IMGFILE_X20}
    else
	IMGFILE=${IMGFILE_NOT_X20}
    fi

    if [[ -f ${DISTFILE} && -n $(cat ${DISTFILE}) && -f ${DISTDIR}/$(cat ${DISTFILE})/${IMGFILE} ]];then
	cat ${DISTFILE}
    else
	echo 0
    fi
}


#Set link to background file depending on distributor
function setBackgroundLink () {
    BACKGROUNDFILE=/home/plusoptix/.fvwm/xbackground.png
    FILENAMEBASE_NOT_X20=xbackground-800x480
    FILENAMEBASE_X20=xbackground-1024x600
    DISTDIR=/home/plusoptix/plusoptix/distributors
    LICENCE_CHANGE=

    if isX20;then
	FILENAMEBASE=${FILENAMEBASE_X20}
    else
	FILENAMEBASE=${FILENAMEBASE_NOT_X20}
    fi
    
    if ! isUpdateMode && isScreener && [[ $(cat ${prgdir}/licence) != "S" ]]; then
	echo "S" > ${prgdir}/licence
	LICENCE_CHANGE=1
    elif ! isUpdateMode && isAutoref && [[ $(cat ${prgdir}/licence) != "A" ]]; then
	echo "A" > ${prgdir}/licence
	LICENCE_CHANGE=1
    elif ! isUpdateMode && isTransilumination && [[ $(cat ${prgdir}/licence) != "T" ]]; then
	echo "A" > ${prgdir}/licence
	LICENCE_CHANGE=1
    fi
    
    if [[ ! -f ${BACKGROUNDFILE} || ! -f ${DISTDIR}/old || $(cat ${DISTDIR}/old) -ne $(cat ${DISTDIR}/current) || -n ${LICENCE_CHANGE} ]];then
	cp ${DISTDIR}/current ${DISTDIR}/old
	rm ${BACKGROUNDFILE} &> /dev/null
	if ! isUpdateMode && isScreener && [[ -f ${DISTDIR}/$(getDistIdForImage)/${FILENAMEBASE}_S.png ]];then
	    ln -s ${DISTDIR}/$(getDistIdForImage)/${FILENAMEBASE}_S.png ${BACKGROUNDFILE}
	elif ! isUpdateMode && isAutoref && [[ -f ${DISTDIR}/$(getDistIdForImage)/${FILENAMEBASE}_A.png ]] ;then
	    ln -s ${DISTDIR}/$(getDistIdForImage)/${FILENAMEBASE}_A.png ${BACKGROUNDFILE}
	elif [[ -f ${DISTDIR}/$(getDistIdForImage)/${FILENAMEBASE}_A.png || -f ${DISTDIR}/$(getDistIdForImage)/${FILENAMEBASE}_S.png ]] ;then
	    ln -s ${DISTDIR}/$(getDistIdForImage)/${FILENAMEBASE}.png ${BACKGROUNDFILE}
	    rm ${DISTDIR}/old
	else
	    ln -s ${DISTDIR}/$(getDistIdForImage)/${FILENAMEBASE}.png ${BACKGROUNDFILE}
	fi	
    fi
}

function showProgressSmileyGif () {
    local filenamebase=xbackground-
    local distdir=/home/plusoptix/plusoptix/distributors/0
    local resolution=
    local licence=
    
    if isOpti || isX18 || grep "omapfb.rotate=" /proc/cmdline;then
	resolution=800x480
    elif isX20;then
	resolution=1024x600
    else
	resolution=640x480	
    fi
    
    if ! isUpdateMode && isScreener && [[ $(cat ${prgdir}/licence) != "S" ]]; then
	echo "S" > ${prgdir}/licence
    elif ! isUpdateMode && isAutoref && [[ $(cat ${prgdir}/licence) != "A" ]]; then
	echo "A" > ${prgdir}/licence
    fi

    case  $(cat ${prgdir}/licence) in
	S)
	    licence=_S
	    ;;
	A)
	    licence=_A
	    ;;
	*)
	    licence=
	    ;;
    esac

    gifview -T "Gifview ProgressSmiley" -a ${distdir}/${filenamebase}${resolution}${licence}.gif &
    local pid=$!
    if ! isRootfsOnNfs ;then
	sleep 20
	kill -9 ${pid}
    fi
}

function isRootfsOnNfs () {
    mount | grep "on / " | grep nfs &> /dev/null
}

function isScreener () {
    setGuiConfDir
    local guiconf=${GUICONFDIR}/PlusoptixQtDesktopGui.cfg
    if [[ ! -f ${guiconf} ]];then
	return 2
    fi
    (( $(grep "LicenceWord=" ${guiconf} | cut -d "=" -f2) & 128 ))
}
function isTransilumination () {
    setGuiConfDir
    local guiconf=${GUICONFDIR}/PlusoptixQtDesktopGui.cfg
    if [[ ! -f ${guiconf} ]];then
	return 2
    fi
    x=$((1<<13))
    (( $(grep "LicenceWord=" ${guiconf} | cut -d "=" -f2) & $x ))
}

function isAutoref () {
    setGuiConfDir
    local guiconf=${GUICONFDIR}/PlusoptixQtDesktopGui.cfg
    if [[ ! -f ${guiconf} ]];then
	return 2
    fi
    (( $(grep "LicenceWord=" ${guiconf} | cut -d "=" -f2) & 16 ))
}

function deleteUnneededVideos () {
    if [[ ! -f ${prgdir}/cleanedup.videos ]];then
	touch ${prgdir}/cleanedup.videos
	if isX16; then
	    rm -r ${prgdir}/videos/12/
	elif isX12; then
	    rm -r ${prgdir}/videos/16/
	fi
	if isScreener; then
	    rm -r ${prgdir}/videos/*/*/cm/
	elif isAutoref; then
	    rm -r ${prgdir}/videos/*/*/ca/
	else
	    rm ${prgdir}/cleanedup.videos
	fi
    fi
}
# Enter username and password for wpa-enterprise and ad dc login / entering a domain
# param 1: title of the field
# param 2: purpose
function ask_for_username_password () {
    TITLE=$1
    PURPOSE=$2
    INPUT=/tmp/xdialog_input
    set +x
    if PoDialog --title ${TITLE} \
	--left \
	--password=2 \
	--separator="\\\n" \
	--2inputsbox "Specify login and password\nto ${PURPOSE}" 0 0 "Login:" "\${ADDC_LOGIN}" "Password:" "\${ADDC_PW}" 2>${INPUT}
    then
	set -x
	ASK_LOGIN=`head -n 1 ${INPUT}`
	ASK_PW=`tail -n 1 ${INPUT}`
	return 0
    else
	set -x
	echo "User name or password input aborted." >> ${ERRORLOG}
	return 1
    fi
}

function show_progress_gif_on_gui () {
    local background_color="#1e1f1d"
    
    gifview --bg "${background_color}" -T "Gifview GUI" -a /home/plusoptix/plusoptix/data/running_without_gui.gif
}

function unset_set () {
    V_WAS_SET=0
    X_WAS_SET=0
    if echo $- | grep v &> /dev/null ;then
	V_WAS_SET=1
	set +v
    fi

    if echo $- | grep x &> /dev/null;then
	X_WAS_SET=1
	set +x
    fi
}

function reset_set () {
    if [[ ${V_WAS_SET} -eq 1 ]] ;then
	V_WAS_SET=0
	set -v
    fi

    if [[ ${X_WAS_SET} -eq 1 ]] ;then
	X_WAS_SET=0
	set -x
    fi

}

#Function called by support-dbimport.sh and update-restart.sh to merge and delete duplicates (see Bug #7348)
#${1} is the backup directory if needed and ${2} is the prefix of the database path if needed
function fix_duplicates_db () {
    local backupdir=${1}
    local prefix=${2}
    local dbpath=${prefix}${HOME}/plusoptix/database
    local dbvers=$(ls -t ${dbpath}/Plusoptix-V?.db | head -n1 | cut -d 'V' -f2 | cut -d '.' -f1)
    local database=${dbpath}/Plusoptix-V${dbvers}.db
    local sqlite_binary=/usr/bin/sqlite3
    local sqldir=${prgdir}/sql
	   
    local check_script=
    local fix_script=

    if ! ls ${database} ;then
	echo "No database found. Exit"
	return
    fi

    echo "Database version: ${dbvers}"
    
    case ${dbvers} in
	3)
	    check_script=check_for_dups_09.sql
	    fix_script=reassign_and_delete_dubs_09.sql
	    ;;
	[4-9]|1[0-9])
	    check_script=check_for_dups.sql
	    fix_script=reassign_and_delete_dubs.sql
	    ;;
	*)
	    echo "Database version ${dbvers} not supported"
	    return
	    ;;
    esac
    
    if [[ -n $(${sqlite_binary} ${database} < ${sqldir}/${check_script}) ]]; then
	local count=0
	local amount=$(${sqlite_binary} ${database} < ${sqldir}/${check_script} | wc -l)
	echo "Found ${amount} duplicates in database"
	if [[ -n ${backupdir} ]];then
	    echo "Backup database to boot part of update device" 
	    cp ${database} ${backupdir}/$(basename ${database})_orig-$(date +%Y%m%d-%H%M%S)
	fi
	while [[ -n $(${sqlite_binary} ${database} < ${sqldir}/${check_script}) ]]
	do
	    ${sqlite_binary} ${database} < ${sqldir}/${fix_script}
	    echo $(( count++ * 100 / ${amount} ))
	done | PoDialog --gauge "$(tr "Please wait while merging duplicates in the database...")" 0 0
	echo "Duplicates are merged!"
    fi
}
function rotate_xbackground {
    sed -i -e 's@qiv -x /home/plusoptix/.fvwm/xbackground.png@qiv -q 1 -x /home/plusoptix/.fvwm/xbackground.png@' ${HOME}/.fvwm/config
}
function isGuiUp {
    [[ -f ${gui_started_flag} ]]
}
function start_xautolock {
    while ! isGuiUp
    do
	sleep 0.5
    done
    bash ${prgdir}/send-touch.sh &  
    xautolock -killtime 120 -killer "killall -USR2 qtopia_gui" -locker "killall -USR1 qtopia_gui" -time 10  &
}
function stop_xautolock {
    killall xautolock
}

function get_system_version {
    cat /etc/versions/system_release
}

function version_less_equal {
    printf '%s\n%s\n' "$1" "$2" | sort --check=quiet --version-sort
}

function version_greater {
    ! version_less_equal "$1" "$2"
}

function initial_rotation {
    #Call this function before starting any other program running on the Xserver. 
    bash ${prgdir}/set_rotation.sh 1
}
# returns true, if the mem size is below 500 MB
function check_overo_256m {
    MEM=`free -m  | grep Mem | awk '{print $2}'`
    [ $MEM -lt 300 ]
}
# Reduce memory footprint for machines with low memory.
function fix_overo_256m_env {
    if check_overo_256m
    then
	echo "NOTE: Device with 256M detected ... "
	if [ -f /etc/rc5.d/S81cupsd ]
	then
	    echo "... deactivate cups"
	    rm -f /etc/rc5.d/S81cupsd
	fi
	if grep "/var/spool/cups" /etc/fstab;
	then
	    echo "... deactiveate spooler tmpfs"
	    umount /var/spool/cups
	    grep -v /var/spool/cups /etc/fstab > /etc/fstab_
	    mv /etc/fstab_ /etc/fstab
	fi
	sed -i s/FACTOR=50/FACTOR=100/ /etc/default/zram 
    fi
}

# Function to adjust device specific display stuff in bootloader files (after a software update, same is done in dtoverlay-initramfs on boot)
function adjust_bootloader_config {
    if isX20; then
	if ! grep 'dtoverlay=px-px20' /boot/config.txt; then
	    echo "dtoverlay=px-px20" >> /boot/config.txt
	    sed -i 's/hdmi_cvt=800 480 60 6 0 0 1/hdmi_cvt=1024 600 60 6 0 0 0/' /boot/config.txt
            sed -i 's/video=HDMI-A-1:480x800MR@60e,rotate=270/video=HDMI-A-1:1024x600@60e/' /boot/cmdline.txt
	fi
    elif isX18; then
	if ! grep 'dtoverlay=px-px18' /boot/config.txt; then
	    echo "dtoverlay=px-px18" >> /boot/config.txt
	    sed -i 's/hdmi_cvt=800 480 60 6 0 0 1/hdmi_cvt=800 480 60 6 0 0 0/' /boot/config.txt
            sed -i 's/video=HDMI-A-1:480x800MR@60e,rotate=270/video=HDMI-A-1:800x480@60e/' /boot/cmdline.txt
	fi
    elif isOpti; then
	if ! grep 'dtoverlay=px-opti' /boot/config.txt; then
	    echo "dtoverlay=px-opti" >> /boot/config.txt
	fi
    fi	
}

# Function to activate the default touchscreen config of the X18/X20
function copy_touch_config {
    if { isX18 || isX20; } && [[ ! -f /etc/pointercal.xinput ]]; then
	if isX18; then
	    cp /etc/pointercal.xinput.x18.default /etc/pointercal.xinput
	else
	    if grep "rotated" /proc/cmdline;then
		cp /etc/pointercal.xinput.x20.reverted /etc/pointercal.xinput
	    else
		cp /etc/pointercal.xinput.x20.default /etc/pointercal.xinput
	    fi
	fi
    fi
}

# Function to adjust the X-Server's 20-screen.conf on Optiscope and X18
function adjust_screen_config {
    if isOpti || isX18; then
	local conf_file=/etc/X11/xorg.conf.d/20-screen.conf
	if grep "1024x600" ${conf_file}; then
	    sed -i 's/"1024x600"/"800x480"/' ${conf_file}
	    sed -i 's/1024 600/800 480/' ${conf_file}
	fi
    fi
}

# Function to trigger a factory reset
function trigger_factory_reset {
    local cmdline_file=/boot/cmdline.txt
    local cmdline_bak_file=/tmp/cmdline.txt
    local EMMC_PATH=/home/plusoptix/plusoptix/emmc

    mount | grep /boot || mount /boot
    
    awk '{ v=sub(/rootrwreset=no/, "rootrwreset=yes"); print } v==0 { exit 1 }' ${cmdline_file} > ${cmdline_bak_file} && mv ${cmdline_bak_file} ${cmdline_file} && rm -rf $EMMC_PATH/*
}

# Check if current image is a production image
function is_a_production_image {
    grep -e production -e installation -e calibration /proc/cmdline
}

# start cups daemon and additionally setup automatic startup at boot by using parameter set to 1 
function  start_cupsd () {
    local atboot=$1
    if ! pgrep -f /usr/sbin/cupsd; then
	if [ $atboot == 1 ]; then
	    update-rc.d cupsd  start 81 5 3 2 . stop 36 0 2 3 5 .
	fi
	/etc/init.d/cupsd start
    fi
}

# stop cups daemon and additionally remove cups from automatic startup
function  stop_cupsd () {
    local atboot=$1
    if ! pgrep -f /usr/sbin/cupsd; then
	if [ $atboot == 1 ]; then
	    update-rc.d -f cupsd remove
	fi
	/etc/init.d/cupsd stop
    fi
}
