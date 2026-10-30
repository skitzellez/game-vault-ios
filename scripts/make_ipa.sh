#!/bin/bash
# Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
# PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
# Game Vault for iPhone - puts the built app and the emulators into an unsigned .ipa. SideStore / AltStore sign it with
# the player's own Apple ID when they install it. Usage: make_ipa.sh <GameVault.app> <cores folder> <out.ipa>
set -euo pipefail
APP="$1"; CORES="$2"; OUT="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
TMP=$(mktemp -d)
mkdir -p "$TMP/Payload"
cp -R "$APP" "$TMP/Payload/"
mkdir -p "$TMP/Payload/GameVault.app/Frameworks"
cp -R "$CORES"/*.framework "$TMP/Payload/GameVault.app/Frameworks/"
if [ -d "$CORES/PPSSPP" ]; then cp -R "$CORES/PPSSPP" "$TMP/Payload/GameVault.app/"; fi
rm -f "$OUT"
(cd "$TMP" && zip -qry "$OUT" Payload)
ls -l "$OUT"
