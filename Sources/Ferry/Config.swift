import Foundation

/// ルールを無視して選択パネルを強制する修飾キー。
enum ModifierChoice: String, Codable, CaseIterable, Identifiable {
    case none, option, shift, control, command

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "使わない"
        case .option: return "option"
        case .shift: return "shift"
        case .control: return "control"
        case .command: return "command"
        }
    }
}

struct CleanerConfig: Codable, Equatable {
    var stripTracking: Bool = true
    /// 末尾 `*` でワイルドカードにできる。ここに載っているものだけを消す。
    /// 「知らないパラメータを消す」方式にはしない（正常な URL を壊すため）。
    var stripParams: [String] = [
        "utm_*", "fbclid", "gclid", "dclid", "msclkid",
        "igshid", "igsh", "mc_eid", "mc_cid",
        "ref_src", "ref_url", "si", "spm", "yclid", "_ga",
    ]
    var expandShortLinks: Bool = true
    /// 展開しにいくホスト。全ホストを対象にはしない（遅延と、開く前に相手サーバへ接触する問題）。
    var shortLinkHosts: [String] = [
        "t.co", "bit.ly", "buff.ly", "goo.gl", "amzn.to",
        "tinyurl.com", "ow.ly", "is.gd", "dlvr.it", "lnkd.in", "trib.al",
    ]

    enum CodingKeys: String, CodingKey {
        case stripTracking, stripParams, expandShortLinks, shortLinkHosts
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = CleanerConfig()
        stripTracking = (try? c.decode(Bool.self, forKey: .stripTracking)) ?? fallback.stripTracking
        stripParams = (try? c.decode([String].self, forKey: .stripParams)) ?? fallback.stripParams
        expandShortLinks = (try? c.decode(Bool.self, forKey: .expandShortLinks))
            ?? fallback.expandShortLinks
        shortLinkHosts = (try? c.decode([String].self, forKey: .shortLinkHosts))
            ?? fallback.shortLinkHosts
    }
}

struct Config: Codable, Equatable {
    var version: Int = 1
    /// 一時停止中や、ルールの指すブラウザが見つからないときの逃げ先。
    var fallbackBrowser: String?
    /// Ferry を既定ブラウザにする前の既定ブラウザ。「元に戻す」で使う。
    var previousDefaultBrowser: String?
    /// 選択パネルに出すブラウザ。空なら見つかったものを全部出す。
    var pickerBrowsers: [String] = []
    var forcePickerModifier: ModifierChoice = .option
    var cleaner: CleanerConfig = CleanerConfig()
    var rules: [Rule] = []

    enum CodingKeys: String, CodingKey {
        case version, fallbackBrowser, previousDefaultBrowser
        case pickerBrowsers, forcePickerModifier, cleaner, rules
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        fallbackBrowser = try? c.decode(String.self, forKey: .fallbackBrowser)
        previousDefaultBrowser = try? c.decode(String.self, forKey: .previousDefaultBrowser)
        pickerBrowsers = (try? c.decode([String].self, forKey: .pickerBrowsers)) ?? []
        forcePickerModifier = (try? c.decode(ModifierChoice.self, forKey: .forcePickerModifier))
            ?? .option
        cleaner = (try? c.decode(CleanerConfig.self, forKey: .cleaner)) ?? CleanerConfig()
        rules = (try? c.decode([Rule].self, forKey: .rules)) ?? []
    }

    /// URL に最初に一致したルールを返す。上から順、最初に当たったものが勝ち。
    func firstMatch(for url: URL) -> Rule? {
        rules.first { $0.matches(url) }
    }
}

/// 設定ファイルの読み書き。
///
/// 置き場所は `~/Library/Application Support/one.yoshito.Ferry/config.json`。
/// 手で直接編集できることを前提にしており、外から書き換えられたら読み直す。
enum ConfigStore {

    static let directory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/one.yoshito.Ferry")

    static let url = directory.appendingPathComponent("config.json")

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            AppLog.write("config: 読み込みに失敗したので既定値を使う: \(error)")
            return Config()
        }
    }

    static func save(_ config: Config) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(config)
            // 書き込み途中のファイルを読ませないよう、一時ファイルを作って差し替える
            let temporary = directory.appendingPathComponent("config.json.tmp")
            try data.write(to: temporary)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            AppLog.write("config: 保存に失敗: \(error)")
        }
    }
}

/// 設定ファイルが外から書き換えられたのを見張る。
///
/// ファイルとディレクトリの両方を見る必要がある。片方だけだと取りこぼす。
///
/// - ファイルだけ見る → エディタがアトミックに差し替えると、掴んでいた
///   ディスクリプタが古いファイルを指したままになり、以後の変更に気づけない
/// - ディレクトリだけ見る → その場で上書きされたときはディレクトリの
///   更新日時が変わらないので、まったく発火しない
final class ConfigWatcher {

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var lastModified: Date?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        try? FileManager.default.createDirectory(
            at: ConfigStore.directory, withIntermediateDirectories: true
        )
        lastModified = modificationDate()

        // ファイルの作成・削除・アトミックな差し替え
        directorySource = makeSource(path: ConfigStore.directory.path, mask: [.write]) {
            [weak self] in
            self?.rearmFile()
            self?.check()
        }
        watchFile()
    }

    /// その場での上書き。差し替えられたら張り直す必要がある。
    private func watchFile() {
        guard FileManager.default.fileExists(atPath: ConfigStore.url.path) else { return }
        fileSource = makeSource(
            path: ConfigStore.url.path,
            mask: [.write, .extend, .attrib, .delete, .rename]
        ) { [weak self] in
            self?.check()
            self?.rearmFile()
        }
    }

    private func rearmFile() {
        fileSource?.cancel()
        fileSource = nil
        watchFile()
    }

    private func check() {
        let now = modificationDate()
        guard now != lastModified else { return }
        lastModified = now
        onChange()
    }

    private func makeSource(
        path: String,
        mask: DispatchSource.FileSystemEvent,
        handler: @escaping () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            AppLog.write("watcher: 開けなかった \(path)")
            return nil
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: mask, queue: .main
        )
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func modificationDate() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: ConfigStore.url.path)
        return attributes?[.modificationDate] as? Date
    }

    deinit {
        directorySource?.cancel()
        fileSource?.cancel()
    }
}
