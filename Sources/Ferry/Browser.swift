import AppKit

struct BrowserApp: Identifiable, Hashable {
    /// バンドルID。設定にはこれを書く（パスはアプリを移動すると壊れる）。
    let id: String
    let name: String
    let url: URL

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// インストール済みブラウザの発見と、URL の受け渡し。
///
/// **URL を実際に開く経路はこのファイルの `open(_:in:)` 1本だけ**にしてある。
/// 他の場所から `NSWorkspace.open` を呼ばせないための集約。
enum Browsers {

    /// 「https を開けるアプリ」を問い合わせるための当て馬
    private static let probe = URL(string: "https://example.com")!

    /// よく使うものを上に出すための並び順
    private static let preferred = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    static func installed() -> [BrowserApp] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var found: [BrowserApp] = []

        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: probe) {
            guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else { continue }
            // 自分自身は必ず外す。既定ブラウザにすると自分もこの一覧に入るので、
            // 外し忘れると選ぶたびに自分へ戻ってくる無限ループになる。
            // 名前ではなくバンドルIDで判定する（リネームで壊れないように）。
            if bundleID == own { continue }
            if !seen.insert(bundleID).inserted { continue }

            let name = FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
            found.append(BrowserApp(id: bundleID, name: name, url: appURL))
        }

        return found.sorted { left, right in
            let leftRank = preferred.firstIndex(of: left.id) ?? preferred.count
            let rightRank = preferred.firstIndex(of: right.id) ?? preferred.count
            if leftRank != rightRank { return leftRank < rightRank }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    static func find(bundleID: String, in list: [BrowserApp]) -> BrowserApp? {
        if let hit = list.first(where: { $0.id == bundleID }) { return hit }
        // 一覧のキャッシュが古い場合に備えて LaunchServices にも聞く
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return BrowserApp(id: bundleID, name: name, url: url)
    }

    /// URL を指定したブラウザへ渡す。
    ///
    /// **アプリを指定しない `NSWorkspace.shared.open(url)` は絶対に書かないこと。**
    /// 既定ブラウザが Ferry 自身なので、呼んだ瞬間に自分へ戻ってきて無限ループする。
    static func open(_ url: URL, in browser: BrowserApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [url], withApplicationAt: browser.url, configuration: configuration
        ) { _, error in
            if let error {
                AppLog.write("open: 失敗 \(browser.name) \(url.absoluteString) \(error)")
            } else {
                AppLog.write("open: \(browser.name) ← \(url.absoluteString)")
            }
        }
    }

    // MARK: - 既定ブラウザ

    /// いまの既定ブラウザ。Ferry 自身が既定なら Ferry が返る。
    static func currentDefault() -> BrowserApp? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: probe),
              let bundleID = Bundle(url: appURL)?.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: appURL.path)
            .replacingOccurrences(of: ".app", with: "")
        return BrowserApp(id: bundleID, name: name, url: appURL)
    }

    static func isFerryDefault() -> Bool {
        currentDefault()?.id == Bundle.main.bundleIdentifier
    }

    /// 既定ブラウザを切り替える。システムの確認ダイアログが出る。
    /// http と https を順に設定する（2回目は聞かれないことが多い）。
    static func setDefault(to appURL: URL, completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.setDefaultApplication(
            at: appURL, toOpenURLsWithScheme: "http"
        ) { firstError in
            NSWorkspace.shared.setDefaultApplication(
                at: appURL, toOpenURLsWithScheme: "https"
            ) { secondError in
                DispatchQueue.main.async {
                    completion(firstError ?? secondError)
                }
            }
        }
    }
}
