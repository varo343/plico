#!/bin/zsh
# Regenerates Resources/AppIcon.icns from the PlicoLogo SwiftUI view.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)/AppIcon.iconset"
cd "$ROOT"
swift run -c release PlicoIconGenerator "$WORK"
iconutil -c icns "$WORK" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote $ROOT/Resources/AppIcon.icns"
