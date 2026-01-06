#!/bin/bash
# adjust-office2.sh – Minimaler Wi-Fi-Direct Auto-Setup für CUPS (HP + Brother)

LOG=/var/log/wfd-action.log
mkdir -p /var/log
touch "$LOG"
chmod 0644 "$LOG"
exec >>"$LOG" 2>&1

# kein -e, nur -u → Fehler werden geloggt, Skript bleibt leben
set -u

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
export DISPLAY=${DISPLAY:-:0.0}
export HOME=${HOME:-/home/plusoptix}

QNAME="WiFiDirect_Printer"
BROTHER_PPD="/etc/cups/ppd/Brother_WFD.ppd"

log() {
    logger -t adjust-wfd "$*"
    echo "[adjust-wfd] $*" >&2
}

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Fehlt: $1" >&2
        log "Fehlt: $1 – Abbruch."
        exit 1
    }
}

# Minimal-Tools
for c in ip awk grep sed lpstat lpadmin cupsenable cupsaccept iw wpa_cli; do
    need "$c"
done

ensure_cups() {
    if ! pgrep -f /usr/sbin/cupsd >/dev/null 2>&1; then
        log "CUPS nicht aktiv – starte cupsd"
        update-rc.d cupsd start 81 5 3 2 . stop 36 0 2 3 5 . >/dev/null 2>&1 || true
        /etc/init.d/cupsd start || true
        sleep 2
    fi
}

# WLAN-Interface mit DIRECT-SSID finden
find_direct_iface() {
    [[ -n "${WFD_IFACE:-}" ]] && { echo "$WFD_IFACE"; return; }

    local ifs
    ifs=$(iw dev 2>/dev/null | awk '/Interface/ {print $2}')
    for i in $ifs; do
        if wpa_cli -i "$i" status 2>/dev/null \
           | awk -F= '/^ssid=/{print $2}' | grep -q '^DIRECT-'; then
            echo "$i"
            return
        fi
    done

    [[ -n "${ifs:-}" ]] && { echo "$(echo "$ifs" | head -n1)"; return; }
    return 1
}

get_ssid() {
    local iface="$1"
    wpa_cli -i "$iface" status 2>/dev/null | awk -F= '/^ssid=/{print $2}'
}

get_ip_address() {
    local iface="$1"
    wpa_cli -i "$iface" status 2>/dev/null | awk -F= '/^ip_address=/{print $2}'
}

get_gateway() {
    local iface="$1"
    ip -4 route show dev "$iface" 2>/dev/null | awk '/default/ {print $3; exit}'
}

# Drucker-IP bestimmen: erst Gateway, dann <eigene-IP>.1
printer_ip_for_iface() {
    local iface="$1"
    local gw ip a b c d

    gw=$(get_gateway "$iface")
    if [[ -n "$gw" ]]; then
        log "printer_ip: nehme Gateway ${gw} als Drucker-IP"
        echo "$gw"
        return 0
    fi

    ip=$(get_ip_address "$iface")
    if [[ -n "$ip" ]]; then
        IFS=. read -r a b c d <<<"$ip"
        log "printer_ip: ip_address=${ip} -> nehme ${a}.${b}.${c}.1 als Drucker-IP"
        echo "${a}.${b}.${c}.1"
        return 0
    fi

    log "printer_ip: keine IP für ${iface} gefunden"
    return 1
}

# Queue einrichten: Brother speziell, sonst generischer RAW (HP)
setup_queue() {
    local ip="$1"
    local ssid="$2"
    local uri=""

    log "setup_queue: IP=${ip}, SSID='${ssid}'"

    # Brother-Netz: dein PPD-Weg
    if [[ "$ip" == 192.168.118.* && -r "$BROTHER_PPD" ]]; then
        uri="ipp://${ip}/ipp/print"
        log "setup_queue: Brother-Netz erkannt -> URI=${uri}, PPD=${BROTHER_PPD}"
        lpadmin -x "$QNAME" 2>/dev/null || true
        lpadmin -p "$QNAME" -E -v "$uri" -P "$BROTHER_PPD"
    else
        # HP OfficeJet & andere: RAW 9100
        uri="socket://${ip}:9100"
        log "setup_queue: generischer RAW-Drucker -> URI=${uri}"
        lpadmin -x "$QNAME" 2>/dev/null || true
        lpadmin -p "$QNAME" -E -v "$uri" -m raw
    fi

    cupsaccept "$QNAME" 2>/dev/null || true
    cupsenable "$QNAME" 2>/dev/null || true

    log "setup_queue: lpstat -v Ausgabe:"
    lpstat -v "$QNAME" 2>&1 | sed 's/^/[lpstat-v] /'
}

do_add() {
    ensure_cups

    local iface ssid ip

    iface=$(find_direct_iface) || { log "add: Kein DIRECT-Interface gefunden."; exit 1; }
    ssid=$(get_ssid "$iface")
    log "add: IF=${iface}, SSID='${ssid}'"

    ip=$(printer_ip_for_iface "$iface") || { log "add: Keine Drucker-IP gefunden – Abbruch."; exit 1; }

    setup_queue "$ip" "$ssid"
    log "add: Fertig. WiFiDirect_Printer zeigt auf den aktuellen DIRECT-Drucker."
}

do_remove() {
    log "remove: Aufräumen temporärer CUPS-Dateien"
    rm -f /var/spool/cups/tmp/* 2>/dev/null || true
    log "remove: Fertig."
}

do_printtest() {
    local q="${1:-$QNAME}"
    echo "WiFiDirect Test $(date)" | lp -d "$q"
    log "printtest: Testjob an ${q} gesendet."
}

do_probe() {
    local iface ssid ip
    iface=$(find_direct_iface) || { log "probe: kein DIRECT-Interface."; exit 1; }
    ssid=$(get_ssid "$iface")
    ip=$(printer_ip_for_iface "$iface" || echo "?")
    log "probe: IF=${iface}, SSID='${ssid}', IP=${ip}"
}

case "${1:-}" in
    add)        do_add ;;
    remove)     do_remove ;;
    probe)      do_probe ;;
    printtest)  shift; do_printtest "${1:-}" ;;
    *)
        echo "Usage: $0 {add|remove|probe|printtest [QUEUE]}" >&2
        log "Usage-Fehler: $*"
        exit 2
        ;;
esac
