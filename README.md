# Ferry

リンクを開くブラウザを選べる、macOS の既定ブラウザアプリ。

メールや Discord から来た URL を Ferry がいったん受け取り、ルールに一致すれば
そのままそのブラウザで開く。一致しなければカーソルのそばにパネルを出して選ばせる。

```
Discord / メール ──▶ Ferry ──┬─ ルール一致 ──▶ Chrome / Safari / …
                             └─ 不一致 ──▶ [ 選択パネル ]
```

- 開く前に短縮URLを展開し、トラッキングパラメータを落とす
- パネルで `space` → 番号 で「以後このホストはこれ」を1操作で覚えさせる
- option を押しながらのクリックでルールを無視してパネルを出す
- リンクが開けなくなったとき用に、一時停止と元の既定ブラウザへの復元を用意

```bash
./build.sh install     # ~/Applications へ入れて起動
```

詳しくは `docs/` を見る。

- [overview.md](docs/overview.md) — 何を作ったか、なぜか
- [usage.md](docs/usage.md) — 使い方
- [architecture.md](docs/architecture.md) — 仕組みと気をつけた点
- [build.md](docs/build.md) — ビルド
- [history.md](docs/history.md) — 変更の記録と今後
