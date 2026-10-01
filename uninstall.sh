#!/bin/bash
# t2chill uninstaller.  usage: sudo ./uninstall.sh [--purge]
#   --purge also deletes /etc/default/t2chill and /var/lib/t2chill (backups + thermal log)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo ./uninstall.sh $*" >&2; exit 1; }
PREFIX=${PREFIX:-/usr/local}
UNITS=/etc/systemd/system

echo "== stopping t2chill (this restores the firmware defaults it saved)"
systemctl disable --now t2chill-log.timer 2>/dev/null || true
systemctl disable --now t2chill.service 2>/dev/null || true

rm -f "$UNITS/t2chill.service" "$UNITS/t2chill-log.service" "$UNITS/t2chill-log.timer" "$PREFIX/sbin/t2chill"
systemctl daemon-reload

if [ "${1:-}" = "--purge" ]; then
	rm -rf /var/lib/t2chill /etc/default/t2chill
	echo "== purged settings, backups and thermal log"
else
	echo "== kept /etc/default/t2chill and /var/lib/t2chill (backups + log). Delete with --purge"
fi
echo "Uninstalled. Firmware defaults are restored now; a reboot would also restore them."
