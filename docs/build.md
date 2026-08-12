# ビルド

最終更新: 2026-08-12

```bash
cd path/to/macOS-Ferry
./build.sh            # dist/Ferry.app を作る
./build.sh run        # 作って起動する
./build.sh install    # ~/Applications に入れて起動する
```

`swift build` → `.app` の殻を被せる → ad-hoc 署名 → `lsregister -f` で登録し直す、まで
`build.sh` が面倒を見る。

## ⚠ `.build` をリポジトリ内に作らない

`~/root/...` 配下に `.build` を置くと SwiftPM のビルドDB(SQLite)が

```
error: accessing build database ".../.build/build.db": disk I/O error
```

を出す。**それでも "Build complete!" と表示され成果物もできるが、中身が1回前の編集のまま**になる。
`build.sh` は `--scratch-path ~/Library/Caches/Ferry-build` に逃がしてある。

直したのに直らないと感じたら、まずここを疑う。
なお `strings` でバイナリ内の文言を探す確認方法は使えない
（Swift は15バイト以下の文字列をインライン化するので日本語の短い文言は出てこない）。
**画面を撮って見るのが確実。**

## 置き場所を変えたら登録し直す

`.app` を移動すると LaunchServices が古い場所を掴んだままになり、
システム設定の既定ブラウザ一覧に前の Ferry が残る。

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /path/to/Ferry.app
```

`build.sh` は毎回これを実行している。**常用するなら `./build.sh install` で
`~/Applications` に置き、そこを既定ブラウザにすること。**
`dist/` の中を既定にすると、リポジトリを消したり作り直したりした瞬間にリンクが開けなくなる。

## 署名

ad-hoc 署名（`codesign --sign -`）。個人利用ではこれで足りる。
ただし ad-hoc だと `SMAppService`（ログイン時に起動）の登録に失敗することがある。
失敗したときはアラートを出して、システム設定 → 一般 → ログイン項目 での手動追加を案内する。

配布するなら Developer ID 署名と公証が要る。
