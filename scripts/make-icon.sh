#!/usr/bin/env bash
# Rebuild assets/AppIcon.icns from assets/icon.svg (+ icon-small.svg for 16/32px).
# Only needed after editing the SVGs; the .icns is committed.
set -euo pipefail
cd "$(dirname "$0")/.."
set_dir=$(mktemp -d)/AppIcon.iconset
mkdir -p "$set_dir"
render() { # svg size out.png
  swift - "$1" "$2" "$3" <<'SWIFT'
import AppKit
let a = CommandLine.arguments
let px = Int(a[2])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSImage(contentsOfFile: a[1])!.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
SWIFT
}
for s in 16 32 128 256 512; do
  src=assets/icon.svg; [[ $s -le 32 ]] && src=assets/icon-small.svg
  render "$src" "$s" "$set_dir/icon_${s}x${s}.png"
  src2=assets/icon.svg; [[ $s -le 16 ]] && src2=assets/icon-small.svg
  render "$src2" $((s * 2)) "$set_dir/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$set_dir" -o assets/AppIcon.icns
echo "wrote assets/AppIcon.icns"
