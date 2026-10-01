#!/bin/bash
# t2chill installer.  usage: sudo ./install.sh [--with-logger]
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo ./install.sh $*" >&2; exit 1; }
PREFIX=${PREFIX:-/usr/local}
BIN=$PREFIX/bin
UNITS=/etc/systemd/system
LOGGER=0; [ "${1:-}" = "--with-logger" ] && LOGGER=1

command -v systemctl >/dev/null || { echo "t2chill needs systemd" >&2; exit 1; }
[ -e /sys/class/powercap/intel-rapl:0 ] || echo "warning: no Intel RAPL power controls found; the power cap will be skipped"
[ -e /sys/devices/system/cpu/intel_pstate ] || echo "warning: intel_pstate not active; turbo/EPP controls will be skipped"

echo "== installing t2chill to $BIN"
install -Dm755 t2chill "$BIN/t2chill"
for u in t2chill.service t2chill-log.service t2chill-log.timer; do
	sed "s|@BIN@|$BIN|g" "systemd/$u" > "$UNITS/$u"
	chmod 644 "$UNITS/$u"
done

if [ ! -f /etc/default/t2chill ]; then
	cat > /etc/default/t2chill <<'CONF'
# t2chill settings. After editing:  sudo systemctl restart t2chill
#PL1_W=35          # sustained package power limit, watts (firmware default: 100)
#PL2_W=45          # short burst limit, watts (firmware default: 125)
#EPP=balance_power # performance | balance_performance | balance_power | power
#TURBO_OFF=1       # 1 = cap at base clock, 0 = keep turbo
CONF
	echo "== wrote default settings to /etc/default/t2chill"
fi

systemctl daemon-reload
systemctl enable --now t2chill.service
if [ "$LOGGER" -eq 1 ]; then
	systemctl enable --now t2chill-log.timer
	echo "== thermal logger on: /var/lib/t2chill/temps.csv (one line a minute)"
fi

echo
"$BIN/t2chill" status
echo
echo "Installed. Applied now and at every boot. Undo: sudo systemctl stop t2chill   Remove: sudo ./uninstall.sh"
