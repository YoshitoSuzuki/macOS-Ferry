# 仕組み

最終更新: 2026-08-12

## 技術構成

| | 選定 | 理由 |
|---|---|---|
| UI | SwiftUI + AppKit（macOS 14+） | パネルと設定画面は SwiftUI、メニューバーは AppKit |
| ビルド | **SwiftPM**（.xcodeproj なし） | CLI だけでビルドできる。Xcode でも `Package.swift` を開けば編集可 |
| 常駐形態 | 実行時に `.accessory` | Dock にアイコンを出さない。**LSUIElement は使わない**（後述） |
| 設定 | JSON ファイル | 手で直接編集でき、書き換えを検知して読み直す |
| 依存 | なし | 外部パッケージ0 |

## ファイルの役割

| ファイル | 役割 |
|---|---|
| `FerryApp.swift` | `@main`。AppDelegate、URL受信の入口、NSStatusItem のメニュー、設定ウィンドウ |
| `Router.swift` | 受け取った URL を処理する中核。キュー、前処理、ルール照合、パネル呼び出し |
| `Browser.swift` | インストール済みブラウザの発見と起動。既定ブラウザの取得・変更 |
| `Rule.swift` | ルールのモデルと照合（host / glob / regex） |
| `Config.swift` | JSON の読み書き、外部変更の監視 |
| `URLCleaner.swift` | 短縮URLの展開とトラッキングパラメータの除去 |
| `PickerPanel.swift` | 選択パネルの NSPanel、位置決め、キー入力 |
| `PickerView.swift` | 選択パネルの中身 |
| `SettingsView.swift` | 設定ウィンドウ |
| `AppState.swift` | 設定・ブラウザ一覧・履歴・一時停止の保持 |
| `AppLog.swift` | `~/Library/Logs/Ferry.log` |

## 気をつけた点

### 自分自身への無限ループ

既定ブラウザが Ferry なので、**アプリを指定しない `NSWorkspace.shared.open(url)` を
1か所でも書くと自分に戻ってきて無限ループする。**
開く経路は `Browsers.open(_:in:)` の1本だけに集約し、必ず `withApplicationAt:` を使う。

`urlsForApplications(toOpen:)` の結果には Ferry 自身も入るので、**バンドルIDで**除外する
（名前で除外するとリネームで壊れる）。

### LSUIElement は Info.plist に書かない

`LSUIElement` のアプリはシステム設定の「デフォルトのWebブラウザ」一覧に出ない可能性がある。
出なければこのアプリは成立しないので、そこは賭けずに
`applicationDidFinishLaunching` で `NSApp.setActivationPolicy(.accessory)` を呼ぶ。

登録できているかは LaunchServices に直接聞けば確かめられる。

```
lsregister -dump | grep -A3 "one.yoshito.Ferry"
# claimed schemes: ferry:, http:, https:   ← これが出ていればよい
```

### メニューバーに `MenuBarExtra` を使わない

SwiftUI の `MenuBarExtra` は、実行時に `.accessory` へ切り替える構成だと**パネルが開かない**。
アイコンは出るがクリックしても反応せず、画面外に 500x500 の空ウィンドウだけが残る。
`NSStatusItem` + `NSMenu` を AppDelegate が自前で持つ形にしてある。

### 既定ブラウザにすると `.html` の担当も Ferry になる

システム設定でデフォルトのWebブラウザを変えると、URLスキーム（http/https）だけでなく
**HTMLファイルの担当アプリも一緒に切り替わる**。そのため `open foo.html` も Ferry に来る。

これを受けないと、`md` のようなローカルHTMLを開くコマンドが**無言で失敗する**
（ログに「扱えないスキーム file://...」だけが残る）。`Router` は file: も受けて、
ホストが無くルールを当てられないので設定ブラウザへそのまま渡す。

### URL は起動より先に届く

未起動の状態でリンクを踏むと、`application(_:open:)` が
`applicationDidFinishLaunching` **より先**に呼ばれる（ログの並びで確認できる）。
そのため設定の読み込みは `AppState` の `init` で同期的に済ませてある。非同期にすると、
アプリを立ち上げてから最初の1本だけルールが効かない、という形で壊れる。

### 修飾キーを読むタイミング

`NSEvent.modifierFlags` は URL が**届いた瞬間**に読む。
短縮URLの展開で最大3秒待つので、処理を始めるときに読むと指が離れていて取りこぼす。

### 設定ファイルの監視はファイルとディレクトリの両方

片方だけでは取りこぼす。

- ファイルだけ → エディタがアトミックに差し替えると、掴んでいたディスクリプタが
  古いファイルを指したままになり以後気づけない
- ディレクトリだけ → その場で上書きされたときはディレクトリの更新日時が変わらず発火しない

### 選択パネルは枠なしウィンドウ

`.titled` を付けるとタイトルバーの分だけ上に余白が残る。`.borderless` にして、
角丸と背景は SwiftUI 側で描く。ただし枠なしの `NSPanel` は既定で key になれずキー入力を
取りこぼすので、`canBecomeKey` を `true` に上書きしたサブクラスを使う。

`onPick` と `onCancel` は必ずどちらか一方だけが一度だけ呼ばれる。
Router が `withCheckedContinuation` で待っているため、二重に呼ぶとクラッシュする。

## 設定ファイル

`~/Library/Application Support/one.yoshito.Ferry/config.json`

```json
{
  "version": 1,
  "fallbackBrowser": null,
  "previousDefaultBrowser": "com.apple.Safari",
  "pickerBrowsers": [],
  "forcePickerModifier": "option",
  "cleaner": {
    "stripTracking": true,
    "stripParams": ["utm_*", "fbclid", "..."],
    "expandShortLinks": true,
    "shortLinkHosts": ["t.co", "bit.ly", "..."]
  },
  "rules": [
    {
      "id": "…", "enabled": true, "name": "GitHub",
      "match": { "kind": "host", "value": "github.com" },
      "browser": "com.google.Chrome"
    }
  ]
}
```

- `pickerBrowsers` が空 = 見つかったブラウザを全部出す
- `browser` は**バンドルID**。パスで持つとアプリを移動した瞬間に壊れる
- `match.kind` は3種類
  - `host` … サブドメインを含む後方一致。`github.com` は `gist.github.com` にも当たる
  - `glob` … `*` だけのワイルドカード。**スキームを除いた `host/path?query`** に対して照合する
  - `regex` … URL 全体に対する部分一致
