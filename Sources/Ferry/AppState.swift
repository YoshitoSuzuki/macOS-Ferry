import AppKit
import Combine

struct HistoryEntry: Identifiable {
    let id = UUID()
    let url: URL
    let browserID: String
    let browserName: String
    let date: Date
}

/// 画面が見る状態のすべて。設定・ブラウザ一覧・履歴・一時停止。
final class AppState: ObservableObject {

    static let shared = AppState()

    @Published var config: Config
    @Published var browsers: [BrowserApp]
    /// ON の間はルールもパネルも通さず、逃げ先のブラウザへ直接流す。
    /// 不具合でリンクが開けなくなったときの脱出口として最初から用意しておく。
    @Published var isPaused = false
    @Published var history: [HistoryEntry] = []

    private var watcher: ConfigWatcher?

    private init() {
        // URL は起動直後に届くことがあるので、設定は同期的に読み終えておく
        config = ConfigStore.load()
        browsers = Browsers.installed()

        watcher = ConfigWatcher { [weak self] in
            guard let self else { return }
            let loaded = ConfigStore.load()
            // 自分で保存した直後も発火する。中身が同じなら何もしない。
            guard loaded != self.config else { return }
            self.config = loaded
            AppLog.write("config: 外部で書き換えられたので読み直した")
        }
        watcher?.start()
    }

    func save() {
        ConfigStore.save(config)
    }

    func refreshBrowsers() {
        browsers = Browsers.installed()
    }

    // MARK: - ブラウザの選び方

    /// 選択パネルに出すブラウザ。設定が空なら見つかったもの全部。
    var pickerBrowsers: [BrowserApp] {
        guard !config.pickerBrowsers.isEmpty else { return browsers }
        return config.pickerBrowsers.compactMap { id in
            browsers.first { $0.id == id }
        }
    }

    /// 一時停止中や、ルールの指すブラウザが見つからないときの逃げ先。
    func fallbackBrowser() -> BrowserApp? {
        if let id = config.fallbackBrowser,
           let hit = Browsers.find(bundleID: id, in: browsers) { return hit }
        if let id = config.previousDefaultBrowser,
           let hit = Browsers.find(bundleID: id, in: browsers) { return hit }
        return pickerBrowsers.first ?? browsers.first
    }

    // MARK: - ルールの追加

    /// 選択パネルの「以後このブラウザで開く」から呼ばれる。
    /// これが実質のルール作成手段で、設定画面をほとんど開かずに済むようにしている。
    func addHostRule(for url: URL, browser: BrowserApp) {
        guard let host = Self.ruleHost(for: url) else { return }
        config.rules.removeAll { $0.match.kind == .host && $0.match.value == host }
        config.rules.append(
            Rule(
                enabled: true,
                name: host,
                match: RuleMatch(kind: .host, value: host),
                browser: browser.id
            )
        )
        save()
        AppLog.write("rule: 追加 \(host) → \(browser.name)")
    }

    /// `www.` は落とす。落としておけば裸のドメインにも当たる（ホスト一致は後方一致のため）。
    static func ruleHost(for url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    // MARK: - 履歴

    func record(url: URL, browser: BrowserApp) {
        history.insert(
            HistoryEntry(
                url: url, browserID: browser.id, browserName: browser.name, date: Date()
            ),
            at: 0
        )
        if history.count > 20 { history.removeLast(history.count - 20) }
    }
}
