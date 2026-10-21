#!/bin/zsh
set -eu
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/token-jump-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/private/tmp}/token-jump-modules"
mkdir -p .build/release
extra_flags=()
# Some Command Line Tools installations retain both old and new module maps.
if [[ -f /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap && -f /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap ]]; then
  mkdir -p .build/workaround
  : > .build/workaround/empty.modulemap
  python3 - "$PWD/.build/workaround" <<'PYTHON'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
(root / 'overlay.json').write_text(json.dumps({'version': 0, 'roots': [{'type': 'file', 'name': '/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap', 'external-contents': str(root / 'empty.modulemap')}]}))
PYTHON
  extra_flags=(-vfsoverlay "$PWD/.build/workaround/overlay.json")
fi
swiftc "${extra_flags[@]}" -O -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" -framework AppKit -framework SpriteKit Sources/TokenJump/main.swift -o .build/release/TokenJump
swiftc "${extra_flags[@]}" -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" -framework AppKit Tools/RenderSprites.swift -o .build/render-sprites
.build/render-sprites Assets/Sprites .build/release/Sprites Assets/Sprites-preview.png
mkdir -p .build/release/Fonts 'dist/Token Jump.app/Contents/Resources/Fonts'
cp Assets/Fonts/* .build/release/Fonts/
cp Assets/Fonts/* 'dist/Token Jump.app/Contents/Resources/Fonts/'
mkdir -p 'dist/Token Jump.app/Contents/Resources/Sprites'
cp .build/release/Sprites/*.png 'dist/Token Jump.app/Contents/Resources/Sprites/'
mkdir -p 'dist/Token Jump.app/Contents/MacOS'
cp .build/release/TokenJump 'dist/Token Jump.app/Contents/MacOS/TokenJump'
cat > 'dist/Token Jump.app/Contents/Info.plist' <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.tokenjump.app</string>
<key>CFBundleName</key><string>Token Jump</string>
<key>CFBundleExecutable</key><string>TokenJump</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - 'dist/Token Jump.app'
