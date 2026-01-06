#!/bin/bash
set -u

# ---- logging helpers ----
ts(){ date '+%F %T'; }

# Logfile optional (kannst du im action-script setzen)
: "${WFD_LOG:=/var/log/wfd-action.log}"

log_i(){ printf '%s [INFO] %s\n'  "$(ts)" "$*" >>"$WFD_LOG" 2>/dev/null || true; }
log_w(){ printf '%s [WARN] %s\n'  "$(ts)" "$*" >>"$WFD_LOG" 2>/dev/null || true; }
log_e(){ printf '%s [ERR ] %s\n'  "$(ts)" "$*" >>"$WFD_LOG" 2>/dev/null || true; }

# ---- exit numbering: zentrale Abbruchfunktion ----
# Usage: die 120 "message..."
die(){
  local code="${1:-1}"; shift || true
  local msg="${*:-unknown error}"
  # Betreuer-Output: klare Exitnummer + Text
  printf 'E%03d: %s\n' "$code" "$msg" >&2
  log_e "E${code}: ${msg}"
  exit "$code"
}

# ---- checks (führen bei Fehler automatisch zu eindeutiger Exitnummer) ----
need(){
  local tool="$1" code="${2:-110}"
  command -v "$tool" >/dev/null 2>&1 || die "$code" "missing tool: $tool"
}

need_file(){
  local f="$1" code="${2:-111}"
  [ -e "$f" ] || die "$code" "missing file: $f"
}

need_exec(){
  local f="$1" code="${2:-112}"
  [ -x "$f" ] || die "$code" "not executable: $f"
}

need_root(){
  local code="${1:-113}"
  [ "$(id -u)" -eq 0 ] || die "$code" "must be root (run with sudo)"
}

iface_exists(){
  local ifc="$1" code="${2:-120}"
  ip link show "$ifc" >/dev/null 2>&1 || die "$code" "interface not found: $ifc"
}

iface_is_up(){
  local ifc="$1" code="${2:-121}"
  ip link show "$ifc" 2>/dev/null | grep -q "state UP" || die "$code" "interface not UP: $ifc"
}

svc_active(){
  local svc="$1" code="${2:-130}"
  systemctl is-active --quiet "$svc" || die "$code" "service not active: $svc"
}

run_ok(){
  # Usage: run_ok 140 "human step" -- cmd args...
  local code="$1"; shift
  local label="$1"; shift
  "$@" >/dev/null 2>&1 || die "$code" "step failed: ${label} (cmd: $*)"
}
