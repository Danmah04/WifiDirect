#!/bin/sh
set -u
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
prgdir=/home/plusoptix/plusoptix/program

LOG=/var/log/wfd-action.log
IFACE="${1:-wlan0}"
EVENT="${2:-}"

RUNDIR="/var/run/wfd"
mkdir -p "$RUNDIR" 2>/dev/null || true

ts(){ date '+%F %T'; }
log(){
  mkdir -p /var/log 2>/dev/null || true
  echo "$(ts) [wfd_action] EVENT=$EVENT IFACE=$IFACE $*" >>"$LOG"
}

get_ssid(){
  wpa_cli -i "$IFACE" status 2>/dev/null | awk -F= '/^ssid=/{print $2; exit}'
}

ssid_looks_like_printer(){
  printf '%s' "$1" | grep -qiE '^(DIRECT-|direct-|hp-print|hp-setup|canon|epson|brother|ricoh|lexmark|samsung|kyocera|oki|pantum|zebra)'
}

ssid_key(){
  echo "$1" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-80
}

case "$EVENT" in
  CONNECTED)
    SSID="$(get_ssid || true)"
    [ -n "${SSID:-}" ] || { log "SSID leer -> exit"; exit 0; }

    ssid_looks_like_printer "$SSID" || { log "SSID '$SSID' kein Printer -> ignore"; exit 0; }

    KEY="$(ssid_key "$SSID")"
    LAST="$RUNDIR/last_${KEY}"
    NOW="$(date +%s)"

    # nur 1x pro 120s je SSID
    if [ -f "$LAST" ]; then
      PREV="$(cat "$LAST" 2>/dev/null || echo 0)"
      if [ $((NOW - PREV)) -lt 120 ]; then
        log "Cooldown aktiv für '$SSID' -> skip"
        exit 0
      fi
    fi
    echo "$NOW" >"$LAST" 2>/dev/null || true

    log "Printer-SSID '$SSID' -> starte Quick-Check (FORCE=1)"
    WFD_FORCE=1 ${prgdir}/wfd_quick_check.sh "$IFACE" >>"$LOG" 2>&1
    RC=$?
    log "Quick-Check done rc=$RC"
    exit 0
    ;;

  DISCONNECTED)
    # Cooldowns zurücksetzen, damit nächster Connect wieder 1x triggert
    rm -f "$RUNDIR"/last_* 2>/dev/null || true
    log "DISCONNECTED -> cooldown reset + optional cleanup"

    if [ -x ${prgdir}/wfd_adjust-officejet.sh ]; then
      ${prgdir}/wfd_adjust-officejet.sh remove >>"$LOG" 2>&1 || true
    fi
    exit 0
    ;;

  *)
    exit 0
    ;;
esac
