#!/bin/sh

set -eu

die() {
	echo "install.sh: $*" >&2
	exit 1
}

[ "$(id -u)" -eq 0 ] || die "run it with sudo"
TARGET_USER=${1:-${SUDO_USER:-}}
[ -n "$TARGET_USER" ] && [ "$TARGET_USER" != root ] || die "say which user may use Gatebar: sudo sh install.sh <user>"
printf '%s\n' "$TARGET_USER" | grep -Eq '^[A-Za-z0-9._-]+$' || die "invalid user name"
id "$TARGET_USER" >/dev/null 2>&1 || die "user $TARGET_USER does not exist"

HERE=$(cd "$(dirname "$0")" && pwd)
TOOLS=/Library/PrivilegedHelperTools
HELPER="$TOOLS/gatebar-helper"

install -d -o root -g wheel -m 755 "$TOOLS"
install -o root -g wheel -m 755 "$HERE/gatebar-helper" "$HELPER"
install -o root -g wheel -m 755 "$HERE/gatebar-vpnc-script" "$TOOLS/gatebar-vpnc-script"
install -d -o root -g wheel -m 755 "/Library/Application Support/Gatebar"
install -d -o root -g wheel -m 755 "/Library/Application Support/Gatebar/vpn"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
	echo "# Written by Gatebar (https://github.com/VictorMMosqueraG/Gatebar)."
	echo "# Lets $TARGET_USER start and stop Gatebar VPN profiles without typing a password."
	echo "$TARGET_USER ALL=(root) NOPASSWD: $HELPER connect *, $HELPER disconnect *"
} >"$tmp"
visudo -cf "$tmp" >/dev/null || die "the sudoers rule did not validate"
install -o root -g wheel -m 440 "$tmp" /etc/sudoers.d/gatebar
visudo -c >/dev/null || die "sudoers check failed"

if ! [ -x /opt/homebrew/bin/openconnect ] && ! [ -x /usr/local/bin/openconnect ]; then
	echo "Note: openconnect is not installed yet. VPN gateways need it: brew install openconnect"
fi
echo "Gatebar system component installed for $TARGET_USER."
