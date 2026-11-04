#!/bin/sh

set -eu
cd "$(dirname "$0")/.."

VERSION=$(tr -d '[:space:]' <VERSION)
APP=dist/Gatebar.app

echo "Building Gatebar ${VERSION}..."
swift build -c release --product Gatebar
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/helper"
cp "$BIN_DIR/Gatebar" "$APP/Contents/MacOS/Gatebar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
cp Helper/gatebar-helper Helper/gatebar-vpnc-script Helper/install.sh Helper/uninstall.sh "$APP/Contents/Resources/helper/"
chmod 755 "$APP/Contents/Resources/helper/"*
codesign --force --deep --sign - "$APP"
echo "Built $APP"

case "${1:-}" in
	--install)
		pkill -x Gatebar 2>/dev/null || true
		sleep 1
		mkdir -p "$HOME/Applications"
		rm -rf "$HOME/Applications/Gatebar.app"
		cp -R "$APP" "$HOME/Applications/Gatebar.app"
		open "$HOME/Applications/Gatebar.app"
		echo "Installed in ~/Applications/Gatebar.app"
		;;
	--zip)
		(cd dist && ditto -c -k --keepParent Gatebar.app "Gatebar-$VERSION.zip")
		echo "Created dist/Gatebar-$VERSION.zip"
		;;
esac
