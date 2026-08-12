# 履歴

## 2026-08-12 — 初版

リンクを開くブラウザを選べる既定ブラウザアプリとして新規作成した。

作ったもの:

- URL受信 → 前処理 → 修飾キー判定 → ルール照合 → 選択パネル、の一周
- ルール3種（ホスト後方一致 / ワイルドカード / 正規表現）と設定画面
- 選択パネルからの1操作ルール追加
- 短縮URL展開とトラッキングパラメータ除去
- 既定ブラウザの登録と、元のブラウザへの復元
- メニューバー（一時停止、履歴からの開き直し、ログイン時に起動）

作りながら変えた判断:

- **`MenuBarExtra` をやめて `NSStatusItem` にした。**
  実行時に `.accessory` へ切り替える構成だとパネルが開かず、画面外に空ウィンドウが残った。
  当初の設計では `MenuBarExtra` を使うつもりだった
- **選択パネルを `.titled` から `.borderless` にした。**
  タイトルバーの分だけ上に余白が残ったため
- **設定ファイルの監視をディレクトリだけからファイル＋ディレクトリの両方にした。**
  ディレクトリだけだと、その場で上書きされたときに更新日時が変わらず発火しなかった

確認したこと（`~/Library/Logs/Ferry.log` と画面で）:

- 未起動から URL を受け取れる。`application(_:open:)` は
  `applicationDidFinishLaunching` より先に呼ばれる
- `utm_source` / `fbclid` が消え、`id` は残る
- 302 を辿って展開し、そのあとで utm を落とす（展開→除去の順序）
- `github.com` のルールが `gist.github.com` にも当たる
- 修飾キーを押しながらだとルールを飛ばしてパネルが出る
- 一時停止中はルールを無視して逃げ先へ流れる
- LaunchServices に `claimed schemes: ferry:, http:, https:` として登録されている

## 今後

- **送信元アプリごとの分岐**（Discord からは Chrome、メールからは Safari）。
  送信元の特定は `NSAppleEventManager.shared().currentAppleEvent` の `keySenderPIDAttr` から
  PID を取るのが本筋。取れないときは `NSWorkspace.didActivateApplicationNotification` を
  監視して「直前に手前にいた自分以外のアプリ」を覚えておく方式で補う
- Chrome のプロファイル指定（`--profile-directory`。新規起動時しか引数が効かない制約あり）
- 特定URLをブラウザではなくアプリで開く（x.com → X.app など）
- 配布するなら Developer ID 署名と公証
