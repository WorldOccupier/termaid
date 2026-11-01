#!/usr/bin/env bash
# Builds the release TermaidApp and wraps it into mac/build/Termaid.app (ad-hoc signed).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build -c release --product TermaidApp
BIN_DIR="$(swift build -c release --show-bin-path)"
RESOURCE_BUNDLE="$BIN_DIR/Termaid_TermaidCore.bundle"
[[ -d "$RESOURCE_BUNDLE" ]] || { echo "error: missing $RESOURCE_BUNDLE" >&2; exit 1; }

APP="$ROOT/build/Termaid.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TermaidApp" "$APP/Contents/MacOS/Termaid"
chmod +x "$APP/Contents/MacOS/Termaid"
# llama.cpp ships as a dynamic framework; embed it and point the binary's rpath at it.
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN_DIR/llama.framework" "$APP/Contents/Frameworks/llama.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Termaid"
# FluidAudio's resource bundle, which its Bundle.module also looks for beside the executable.
for extra in "$BIN_DIR"/FluidAudio_*.bundle; do
  [[ -d "$extra" ]] && cp -R "$extra" "$APP/Contents/MacOS/"
done
# Bundle.module resolves beside the executable; Resources copy is for tools that look there.
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/MacOS/"
# App icon; regenerate it from Resources/AppIcon.svg with scripts/make-icon.swift.
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
# SwiftPM resource bundles ship without Info.plist, which codesign rejects when nested; add a minimal one.
for b in "$APP/Contents/Resources/$(basename "$RESOURCE_BUNDLE")" "$APP"/Contents/MacOS/*.bundle; do
  [[ -f "$b/Info.plist" ]] && continue
  cat > "$b/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.termaid.app.resources.$(basename "$b" .bundle)</string>
    <key>CFBundlePackageType</key><string>BNDL</string>
    <key>CFBundleName</key><string>$(basename "$b" .bundle)</string>
</dict>
</plist>
PLIST
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.termaid.app</string>
    <key>CFBundleName</key><string>Termaid</string>
    <key>CFBundleExecutable</key><string>Termaid</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>termaid listens while you hold ⌥ Space to turn what you say into a diagram.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"
