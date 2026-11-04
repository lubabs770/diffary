#!/usr/bin/env bash
# swift build → dist/Diffary.app (unsigned). Optional: --install copies to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/fetch-ghosttykit.sh
swift build -c release
bin=$(swift build -c release --show-bin-path)
app=dist/Diffary.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Diffary" "$app/Contents/MacOS/Diffary"
# SwiftPM resource bundles (e.g. Highlightr's) sit next to the binary.
for b in "$bin"/*.bundle; do [[ -e $b ]] && cp -R "$b" "$app/Contents/Resources/"; done
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Diffary</string>
  <key>CFBundleIdentifier</key><string>io.github.lubabs770.diffary</string>
  <key>CFBundleExecutable</key><string>Diffary</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"   # ad-hoc, so macOS will launch it
echo "built $app"
if [[ ${1:-} == --install ]]; then
  mkdir -p ~/Applications && rm -rf ~/Applications/Diffary.app && cp -R "$app" ~/Applications/
  echo "installed ~/Applications/Diffary.app"
  # Seed a commented config the first time; never overwrite an existing one.
  conf="${XDG_CONFIG_HOME:-$HOME/.config}/diffary/config.toml"
  if [[ ! -e $conf ]]; then
    mkdir -p "$(dirname "$conf")/themes" && cp config.example.toml "$conf"
    echo "created $conf"
  fi
fi
