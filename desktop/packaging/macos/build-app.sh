#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Packages the macOS build of NectarLink into a .app bundle, runs macdeployqt
# to pull in the Qt frameworks and QML modules, ad-hoc signs it, and wraps it
# in a .dmg. Called from the repo root by .github/workflows/macos.yml; paths
# are resolved relative to this script so it also works if run by hand.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$REPO"

APP_NAME="NectarLink"
BINARY="nectarlink-desktop"

# Version: from the workflow input, else from the workspace Cargo.toml.
if [ -n "${VERSION:-}" ]; then
  : # keep VERSION
else
  VERSION="$(grep -m1 '^version = ' Cargo.toml | cut -d'"' -f2)"
fi

STAGE="$(mktemp -d)"
APP="$STAGE/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "==> Packaging $APP_NAME $VERSION"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

# The binary: QML, fonts and shaders are compiled into it (qrc / cxx-qt).
cp "target/release/$BINARY" "$CONTENTS/MacOS/$BINARY"
chmod +x "$CONTENTS/MacOS/$BINARY"

# Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>app.nectarlink.desktop</string>
  <key>CFBundleExecutable</key><string>$BINARY</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSRequiresNativeExecution</key><true/>
</dict>
</plist>
PLIST

# macdeployqt bundles Qt frameworks + the Qt QML modules the app imports.
# The app's own QML (app.nectarlink) is embedded in the binary, so only Qt's
# modules need copying; -qmldir points at the source QML so imports are seen.
MACDEPLOYQT="$(command -v macdeployqt || true)"
if [ -z "$MACDEPLOYQT" ] && [ -n "${QT_DIR:-}" ]; then
  MACDEPLOYQT="$(find "$QT_DIR/.." -name macdeployqt -type f 2>/dev/null | head -1 || true)"
fi
if [ -z "$MACDEPLOYQT" ]; then
  echo "::error::macdeployqt not found; the Qt install may be incomplete" >&2
  exit 1
fi

echo "==> Running macdeployqt ($MACDEPLOYQT)"
"$MACDEPLOYQT" "$APP" -qmldir "$REPO/desktop/app/qml" -verbose=1

# Ad-hoc sign so Gatekeeper lets you open it. This is a personal/unofficial
# build: for wide distribution you would need an Apple Developer ID and
# notarization instead of "-".
echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"

# Wrap in a .dmg (hdiutil ships with macOS, no extra tool needed).
mkdir -p "$STAGE/dmg"
cp -R "$APP" "$STAGE/dmg/"
ln -s /Applications "$STAGE/dmg/Applications"

DMG="dist/$APP_NAME-${VERSION}-macOS.dmg"
mkdir -p dist
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE/dmg" -ov -format UDZO "$DMG"

echo "==> Built $DMG"
ls -lh "$DMG"
