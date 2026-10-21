#!/bin/zsh
set -eu
cd "${0:A:h}"
./build-app.sh
# Preserve the signed application bundle and resource forks in the ZIP.
ditto -c -k --sequesterRsrc --keepParent 'dist/Token Jump.app' dist/TokenJump.zip
stage_dir=$(mktemp -d "${TMPDIR:-/private/tmp}/tokenjump-dmg.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT
ditto 'dist/Token Jump.app' "$stage_dir/Token Jump.app"
ln -s /Applications "$stage_dir/Applications"
hdiutil create -volname 'Token Jump' -srcfolder "$stage_dir" -ov -format UDZO dist/TokenJump.dmg
hdiutil verify dist/TokenJump.dmg
shasum -a 256 dist/TokenJump.zip dist/TokenJump.dmg > dist/SHA256SUMS.txt
