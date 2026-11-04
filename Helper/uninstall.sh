#!/bin/sh

set -eu
[ "$(id -u)" -eq 0 ] || { echo "run it with sudo" >&2; exit 1; }

if [ -d /var/run/gatebar ]; then
	for pidfile in /var/run/gatebar/*.pid; do
		[ -f "$pidfile" ] || continue
		id=$(basename "$pidfile" .pid)
		/Library/PrivilegedHelperTools/gatebar-helper disconnect "$id" 2>/dev/null || true
	done
	rm -rf /var/run/gatebar
fi
rm -f /etc/sudoers.d/gatebar
rm -f /Library/PrivilegedHelperTools/gatebar-helper /Library/PrivilegedHelperTools/gatebar-vpnc-script
rm -rf "/Library/Application Support/Gatebar"
echo "Gatebar system component removed."
