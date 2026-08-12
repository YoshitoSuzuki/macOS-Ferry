#!/bin/bash
# Ferry.app を組み立てる。
#
#   ./build.sh          ビルドして dist/Ferry.app を作る
#   ./build.sh run      ビルドして起動する
#   ./build.sh install  ビルドして ~/Applications へ入れて起動する
#
# Xcode プロジェクトは持たず SwiftPM でビルドし、.app の殻を自分で被せる。
# Xcode で編集したいときは Package.swift を開けばよい。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/dist/Ferry.app"
MODE="${1:-build}"

echo "==> swift build"
# ビルド成果物はリポジトリ内ではなく Caches に置く。
# ~/root/... 配下に .build を作ると SwiftPM のビルドDB(SQLite)が
# "disk I/O error" になり、増分ビルドが1回分古い結果を返す事故が起きる。
SCRATCH="$HOME/Library/Caches/Ferry-build"

BUILD_LOG="$(mktemp)"
trap 'rm -f "$BUILD_LOG"' EXIT
set +e
swift build -c release --package-path "$ROOT" --scratch-path "$SCRATCH" 2>&1 | tee "$BUILD_LOG"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

BIN="$SCRATCH/release/Ferry"
if [ ! -x "$BIN" ]; then
    echo "ビルドに失敗しました（実行ファイルがありません）" >&2
    exit 1
fi
if [ "$BUILD_STATUS" -ne 0 ]; then
    if grep -q "Build complete!" "$BUILD_LOG"; then
        echo "注意: swift build が非0で終了しましたが、ビルド自体は完了しています" >&2
    else
        # 全角括弧が変数名に食われるので ${} で閉じる
        echo "ビルドに失敗しました（終了コード ${BUILD_STATUS}）" >&2
        exit 1
    fi
fi

echo "==> bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ferry"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# ad-hoc 署名。個人利用ではこれで足りる（配布するなら Developer ID が要る）
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
    echo "警告: 署名に失敗しました。動作はしますが「ログイン時に起動」が使えない場合があります" >&2
}

# LaunchServices に URL ハンドラとして登録し直す。
# これをやらないと「デフォルトのWebブラウザ」一覧に古い場所の Ferry が残る。
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" || true

echo "==> done: $APP"

case "$MODE" in
    run)
        pkill -x Ferry 2>/dev/null || true
        sleep 0.5
        open "$APP"
        echo "起動しました。メニューバーを確認してください。"
        ;;
    install)
        mkdir -p "$HOME/Applications"
        pkill -x Ferry 2>/dev/null || true
        sleep 0.5
        rm -rf "$HOME/Applications/Ferry.app"
        cp -R "$APP" "$HOME/Applications/Ferry.app"
        [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$HOME/Applications/Ferry.app" || true
        open "$HOME/Applications/Ferry.app"
        echo "~/Applications/Ferry.app に入れて起動しました。"
        ;;
esac
