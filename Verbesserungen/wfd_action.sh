#!/bin/bash
set -u

# ---- config ----
IFACE="${1:-wlan0}"
EVENT="${2:-MANUAL}"

# Logfile (wird auch von wfd_lib.sh benutzt)
export WFD_LOG="/var/log/wfd-action.log"

# ---- load lib ----
LIB="/home/plusoptix/plusoptix/program/wfd_lib.sh"
[ -r "$LIB" ] || { printf 'E100: missing lib: %s\n' "$LIB" >&2; exit 100; }
# shellcheck source=/dev/null
. "$LIB"

# ---- basic sanity ----
need_root 101
need ip 110
need iw 110
need wpa_cli 110
need systemctl 110

iface_exists "$IFACE" 120

# Optional: nur wenn du wirklich UP brauchst (sonst weglassen)
# iface_is_up "$IFACE" 121

# ---- important files (anpassen, falls dein Projekt andere Pfade nutzt) ----
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
need_file "$WPA_CONF" 111

log_i "start IFACE=$IFACE EVENT=$EVENT"

# ---- service checks (je nach distro unterschiedlich; passe an, was ihr nutzt) ----
# Wenn ihr wpa_supplicant@wlan0 nutzt:
# svc_active "wpa_supplicant@${IFACE}.service" 130
# Wenn ihr wpa_supplicant (global) nutzt:
# svc_active "wpa_supplicant.service" 130

# ---- STEP 1: Scan Wi-Fi Direct SSIDs ----
# Typisch: "DIRECT-xx-..." SSIDs
SCAN_OUT="$(iw dev "$IFACE" scan 2>/dev/null)" || die 140 "iw scan failed on $IFACE"
echo "$SCAN_OUT" | grep -q "SSID: DIRECT-" || die 141 "no Wi-Fi Direct SSID found (DIRECT-*)"

log_i "scan ok: found DIRECT-*"

# ---- STEP 2: Check wpa_supplicant connectivity state ----
# (Hier nur ein Beispiel; passe an, was ihr genau erwartet)
WPA_STATE="$(wpa_cli -i "$IFACE" status 2>/dev/null | grep '^wpa_state=' | cut -d= -f2 || true)"
[ -n "$WPA_STATE" ] || die 150 "wpa_cli status returned no state for $IFACE"
log_i "wpa_state=$WPA_STATE"

# ---- STEP 3: IP check (wenn verbunden, sollte IP existieren) ----
# Wenn das Projekt zwingend DHCP macht, dann ist fehlende IP ein Fehler.
IPV4="$(ip -4 addr show dev "$IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -n1 || true)"
[ -n "$IPV4" ] || die 160 "no IPv4 address on $IFACE (DHCP?)"
log_i "ipv4=$IPV4"

# ---- STEP 4: Peer/Drucker IP (falls euer Projekt die Peer-IP so bestimmt) ----
# Beispiel: Nachbarn/ARP nach DIRECT-Verbindung:
PEER_IP="$(ip neigh show dev "$IFACE" 2>/dev/null | awk '/REACHABLE|STALE|DELAY|PROBE/{print $1; exit}' || true)"
[ -n "$PEER_IP" ] || die 170 "could not determine peer IP via ip neigh on $IFACE"
log_i "peer_ip=$PEER_IP"

# ---- STEP 5: Port checks (anpassen: IPP 631, RAW 9100, HTTP 80 etc.) ----
need nc 110

# Beispiel: IPP 631 oder RAW 9100:
nc -z -w 2 "$PEER_IP" 631 >/dev/null 2>&1 || log_w "port 631 not reachable on $PEER_IP (maybe ok)"
nc -z -w 2 "$PEER_IP" 9100 >/dev/null 2>&1 || log_w "port 9100 not reachable on $PEER_IP (maybe ok)"

log_i "done ok"
printf 'OK: Wi-Fi Direct basic checks passed (IFACE=%s EVENT=%s)\n' "$IFACE" "$EVENT"
exit 0
