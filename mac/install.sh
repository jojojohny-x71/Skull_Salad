#!/bin/bash
# Builds Skull Salad, copies it into Applications (or ~/Applications if that isn't writable), and opens it.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh

DEST="/Applications"
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
osascript -e 'tell application id "app.skullsalad.SkullSalad" to quit' >/dev/null 2>&1 || true
rm -rf "$DEST/Skull Salad.app"
ditto "build/Skull Salad.app" "$DEST/Skull Salad.app"
# Leave only the installed copy, so Launchpad and Spotlight don't list the build folder's copy too.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "build/Skull Salad.app" >/dev/null 2>&1 || true
rm -rf build
echo "Installed to $DEST/Skull Salad.app"
open "$DEST/Skull Salad.app"
