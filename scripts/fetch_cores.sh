#!/bin/bash
# Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
# PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
# Game Vault for iPhone - downloads the emulators (libretro cores for iOS arm64, from the libretro build server) and
# wraps each one as a framework, the way an iPhone app must carry extra code. Usage: fetch_cores.sh <out folder>
set -euo pipefail
OUT="$1"
SERVER=https://buildbot.libretro.com/nightly/apple/ios-arm64/latest
CORES="fceumm_libretro_ios snes9x_libretro_ios gambatte_libretro_ios mgba_libretro pcsx_rearmed_libretro_ios
genesis_plus_gx_libretro_ios mednafen_pce_fast_libretro_ios stella_libretro_ios handy_libretro_ios
mednafen_vb_libretro_ios"
mkdir -p "$OUT"
TMP=$(mktemp -d)
for c in $CORES; do
  name=${c%_ios}
  curl -sfL --retry 3 "$SERVER/$c.dylib.zip" -o "$TMP/$c.zip"
  unzip -oq "$TMP/$c.zip" -d "$TMP/$c"
  dylib=$(find "$TMP/$c" -name "*.dylib" | head -1)
  fw="$OUT/$name.framework"
  rm -rf "$fw"; mkdir -p "$fw"
  cp "$dylib" "$fw/$name"
  install_name_tool -id "@rpath/$name.framework/$name" "$fw/$name"
  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$name</string>
<key>CFBundleIdentifier</key><string>com.skitzelles.gamevault.${name//_/-}</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
<key>MinimumOSVersion</key><string>16.0</string>
</dict></plist>
PLIST
  echo "$name: $(shasum -a 256 "$fw/$name" | cut -c1-16) $(stat -f%z "$fw/$name") bytes"
done
