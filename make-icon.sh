#!/bin/bash
# Resources/icon.svg から Resources/Ferry.icns を作り直す。
#
# 出来上がった .icns はリポジトリに入れてあるので、ビルドするだけなら実行不要。
# アイコンの絵を変えたときだけ走らせる。rsvg-convert (brew install librsvg) が要る。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG="$ROOT/Resources/icon.svg"

command -v rsvg-convert >/dev/null || {
    echo "rsvg-convert がありません: brew install librsvg" >&2
    exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SET="$WORK/Ferry.iconset"
mkdir -p "$SET"

for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$SVG" -o "$SET/icon_${size}x${size}.png"
    rsvg-convert -w "$((size * 2))" -h "$((size * 2))" "$SVG" \
        -o "$SET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$SET" -o "$ROOT/Resources/Ferry.icns"
echo "==> done: $ROOT/Resources/Ferry.icns"
