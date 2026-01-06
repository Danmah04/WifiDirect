#!/bin/sh
# wfd_quick_check.sh
#
# Aufgabe:
#   - erkennt Wi-Fi-Direct-Drucker über SSID
#   - bestimmt Peer-IP (Drucker-IP)
#   - prüft Drucker-Ports (631 / 9100 / 80)
#   - richtet CUPS-Queue "WiFiDirect_Printer" passend ein
#       * HP: RAW 9100 (socket://IP:9100, -m raw)
#       * Brother: IPP mit PPD
#       * andere: IPP (631) oder Fallback RAW 9100 / Port 80
#   - setzt "WiFiDirect_Printer" als Default-Queue
#   - zeigt Overlay (PoDialog) und schreibt Logs
#
# Aufruf:
#   wfd_quick_check.sh [IFACE]
#   IFACE = WLAN-Interface, z.B. wlan0 (optional)
#
# Ort:
#   /home/plusoptix/plusoptix/program/wfd_quick_check.sh
#   Wrapper unter /home/plusoptix/plusoptix/progam/wfd_quick_check.sh ruft dieses Skript auf.

# ----------------------------------------------------------
# Konfiguration
# ----------------------------------------------------------
QNAME="WiFiDirect_Printer"
BROTHER_PPD="/etc/cups/ppd/Brother_WFD.ppd"

# Optional: plusoptix-Helper (PoDialog etc.)
. /home/plusoptix/plusoptix/program/functions.sh
# wlan specific macros:
. ${prgdir}/wlan-functions.sh

set -u  # undefinierte Variablen sind Fehler

STAMP="/var/run/wfd_quick_check.stamp"
NOW=$(date +%s)

LOGFILE="/home/plusoptix/wfd_trace.log"

log_q() {
    echo "$(date '+%F %T') [wfd_quick] $*" >>"$LOGFILE"
    logger -t wfd_quick "$*"
}

# --- Laufzeitsperre: max. 1x pro 60s, außer WFD_FORCE=1 ---
if [ "${WFD_FORCE:-0}" != "1" ]; then
  if [ -f "$STAMP" ]; then
    LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
    if [ $((NOW - LAST)) -lt 60 ]; then
      log_q "THROTTLE: exit wegen <60s (LAST=${LAST}, NOW=${NOW})"
      exit 0
    fi
  fi
fi
echo "$NOW" >"$STAMP"

log_q "START IFACE=${1:-?} FORCE=${WFD_FORCE:-0}"

# ----------------------------------------------------------
# Interface bestimmen:
#   - Parameter $1
#   - oder Umgebungsvariablen WLAN_IF / WLANINTERFACENAME
#   - sonst Fallback: wlan0
# ----------------------------------------------------------
IFACE="${1:-${WLAN_IF:-${WLANINTERFACENAME:-wlan0}}}"
log_q "START IFACE=$IFACE"

# ----------------------------------------------------------
# Hilfsfunktionen
# ----------------------------------------------------------

# is_open IP PORT:
#   - prüft mit kurzem Timeout, ob ein TCP-Port erreichbar ist
is_open() {  # is_open IP PORT
  timeout 1 sh -c ":</dev/tcp/$1/$2" 2>/dev/null
}

# get_ssid:
#   - SSID via wpa_cli status
get_ssid() {
  wpa_cli -i "$IFACE" status 2>/dev/null \
    | awk -F= '/^ssid=/{print $2; exit}'
}

# see wlan-functions.sh -> have_ip or wait_for_ip
# # get_ip_wpa:
# #   - IPv4-Adresse aus wpa_cli-Status (ip_address=)
# get_ip_wpa() {
#   wpa_cli -i "$IFACE" status 2>/dev/null \
#     | awk -F= '/^ip_address=/{print $2; exit}'
# }

# # get_ip_ipcmd:
# #   - IPv4-Adresse via 'ip addr show dev IFACE'
# get_ip_ipcmd() {
#   ip -4 addr show dev "$IFACE" 2>/dev/null \
#     | awk '/inet /{print $2; exit}' | cut -d/ -f1
# }

# # ensure_ip:
# #   - versucht, eine IPv4-Adresse für das Interface zu holen
# ensure_ip() {
#   local ip
#   ip="$(get_ip_wpa)"
#   [ -n "$ip" ] || ip="$(get_ip_ipcmd)"

#   if [ -n "$ip" ]; then
#     log_q "ensure_ip: vorhandene IP=${ip}"
#     echo "$ip"
#     return 0
#   fi

#   # Noch keine IP → DHCP anstoßen (udhcpc oder dhclient)
#   if command -v udhcpc >/dev/null 2>&1; then
#     log_q "DHCP: udhcpc auf $IFACE…"
#     udhcpc -i "$IFACE" -t 5 -T 2 -n >>"$LOGFILE" 2>&1 || true
#   elif command -v dhclient >/dev/null 2>&1; then
#     log_q "DHCP: dhclient auf $IFACE…"
#     dhclient -1 -v "$IFACE" >>"$LOGFILE" 2>&1 || true
#   else
#     log_q "DHCP: weder udhcpc noch dhclient vorhanden"
#   fi

#   sleep 2

#   ip="$(get_ip_wpa)"
#   [ -n "$ip" ] || ip="$(get_ip_ipcmd)"

#   if [ -n "$ip" ]; then
#     log_q "DHCP: IP erhalten: $ip"
#     echo "$ip"
#     return 0
#   fi

#   log_q "DHCP: keine IP erhalten"
#   return 1
# }

# get_peer:
#   - Drucker-IP:
#       1. Default-Route über 'ip route show dev IFACE'
#       2. Falls keine Route: aus eigener IP das Subnetz nehmen und ".1" annehmen
get_peer() {
  local peer myip
  peer="$(ip route show dev "$IFACE" 2>/dev/null | awk '/^default/ {print $3; exit}')"
  if [ -n "$peer" ]; then
    echo "$peer"
    return 0
  fi
  myip="$1"
  if [ -n "$myip" ]; then
    echo "$myip" | awk -F. '{printf "%s.%s.%s.1",$1,$2,$3}'
    return 0
  fi
  return 1
}

# setup_wfd_printer:
#   - richtet Queue QNAME ein/aktualisiert sie
setup_wfd_printer() {  # SSID PEER
  local ssid="$1"
  local peer="$2"
  local uri=""

  log_q "setup_wfd_printer: SSID='${ssid}' PEER=${peer}"

  # Brother-Spezialfall mit PPD
  if echo "$ssid" | grep -qi 'Brother' && [ -r "$BROTHER_PPD" ]; then
      uri="ipp://${peer}/ipp/print"
      log_q "Brother erkannt -> URI=${uri}, PPD=${BROTHER_PPD}"
      lpadmin -x "$QNAME" 2>/dev/null || true
      lpadmin -p "$QNAME" -E -v "$uri" -P "$BROTHER_PPD" || true

      # HP: JetDirect mit PCL (CUPS rendert!) neu version 
  elif echo "$ssid" | grep -qi 'hp\|officejet\|envy\|deskjet\|laserjet'; then
      uri="socket://${peer}:9100"
      log_q "HP-WiFi-Direct erkannt -> JetDirect mit PCL, URI=${uri}"
      lpadmin -x "$QNAME" 2>/dev/null || true
      lpadmin -p "$QNAME" -E \
	      -v "$uri" \
	      -m drv:///sample.drv/laserjet.ppd 2>/dev/null || true

      # generischer Fall (Canon, Epson, …)
  else
      if is_open "$peer" 631; then
	  uri="ipp://${peer}/ipp/print"
	  log_q "Port 631 offen -> URI=${uri}"
	  lpadmin -x "$QNAME" 2>/dev/null || true
	  # Versuch driverless, Fallback auf raw
	  lpadmin -p "$QNAME" -E -v "$uri" -m everywhere 2>/dev/null || \
	      lpadmin -p "$QNAME" -E -v "$uri" -m raw       2>/dev/null || true

      elif is_open "$peer" 9100; then
	  uri="socket://${peer}:9100"
	  log_q "Port 9100 offen -> URI=${uri}"
	  lpadmin -x "$QNAME" 2>/dev/null || true
	  lpadmin -p "$QNAME" -E -v "$uri" -m raw 2>/dev/null || true

      elif is_open "$peer" 80; then
	  uri="ipp://${peer}/ipp/print"
	  log_q "Nur Port 80 offen -> versuche URI=${uri}"
	  lpadmin -x "$QNAME" 2>/dev/null || true
	  lpadmin -p "$QNAME" -E -v "$uri" -m raw 2>/dev/null || true

      else
	  log_q "setup_wfd_printer: keine typischen Drucker-Ports offen"
	  return 1
      fi
  fi

  cupsaccept "$QNAME" 2>/dev/null || true
  cupsenable  "$QNAME" 2>/dev/null || true

  log_q "lpstat -v ${QNAME}:"
  lpstat -v "$QNAME" 2>&1 | sed 's/^/[wfd_quick] /' >>"$LOGFILE"
}

# Default-Queue setzen, damit 'lpr' ohne -P funktioniert
set_default_queue() {
  log_q "Setze ${QNAME} als Default-Queue (lpadmin/lpoptions)"
  lpadmin  -d "$QNAME" 2>>"$LOGFILE" || log_q "lpadmin -d ${QNAME} fehlgeschlagen"
  lpoptions -d "$QNAME" 2>>"$LOGFILE" || log_q "lpoptions -d ${QNAME} fehlgeschlagen"
  lpstat -d 2>&1 | sed 's/^/[wfd_quick] /' >>"$LOGFILE"
}

# ----------------------------------------------------------
# eigentliche Logik
# ----------------------------------------------------------

SSID="$(get_ssid)"
[ -n "$SSID" ] || { log_q "Keine SSID -> Abbruch"; exit 1; }

# nur DIRECT-/Drucker-SSIDs behandeln
case "$SSID" in
  DIRECT-*) ;;   # klassisches Wi-Fi-Direct immer zulassen
  *)
    echo "$SSID" | grep -qiE 'canon|epson|brother|hp|ricoh|lexmark|kyocera|oki|pantum|zebra' \
      || { log_q "SSID='${SSID}' sieht nicht nach Wi-Fi-Direct-Drucker aus -> exit"; exit 1; }
    ;;
esac

log_q "SSID='${SSID}' -> Kandidat Wi-Fi-Direct"

MYIP="$(wait_for_ip)"
if [ -z "${MYIP:-}" ]; then
  log_q "Keine IP trotz DHCP -> exit"
  exit 1
fi

PEER="$(get_peer "$MYIP" || true)"
if [ -z "${PEER:-}" ]; then
  log_q "Keine Peer-IP ableitbar -> exit"
  exit 1
fi

# Ports grob checken (nur um offensichtliche Nicht-Drucker rauszufiltern)
if ! ( is_open "$PEER" 631 || is_open "$PEER" 9100 || is_open "$PEER" 80 ); then
  log_q "PEER=${PEER}: Ports 631/9100/80 alle zu -> vermutlich kein Drucker"
  exit 1
fi

log_q "Wi-Fi-Direct-Drucker erkannt: SSID='${SSID}', Host=${PEER}"

# start cupsd with param 1 means at boot 
start_cupsd 1

# Queue einrichten
setup_wfd_printer "$SSID" "$PEER" || {
  log_q "setup_wfd_printer fehlgeschlagen"
  exit 1
}

# Default-Queue setzen
set_default_queue

# Tell gui to call lpr 
echo 2 > ${HOME}/plusoptix/data/default-printer-queue

# ----------------------------------------------------------
# User-Feedback im Terminal
# ----------------------------------------------------------
GREEN="$(printf '\033[1;32m')"
RESET="$(printf '\033[0m')"
CHECK="*"
printf '%s%s%s  Wi-Fi Direct Printer Detected (%s)\n' "$GREEN" "$CHECK" "$RESET" "$SSID"
printf '       SSID: %s\n' "$SSID"
printf '       Host: %s\n' "$PEER"

# ----------------------------------------------------------
# Optionales PoDialog-Overlay
# ----------------------------------------------------------
if command -v PoDialog >/dev/null 2>&1; then
  CHECK="✔"
  MSG="${CHECK}  WiFi-Direct Detected (${SSID})\n\nSSID: ${SSID}\nHost: ${PEER}\nQueue: ${QNAME}"
  PoDialog --msgbox "$MSG" 8 50
fi

# zusätzlicher Log-Eintrag
printf '%s Wi-Fi-Direct-Drucker erkannt (SSID: %s, Host: %s)\n' \
  "$(date '+%Y-%m-%d %H:%M:%S')" "$SSID" "$PEER" >> /home/plusoptix/wfd_detect.log 2>/dev/null || true

exit 0

