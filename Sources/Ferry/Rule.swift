import Foundation

/// URL の照合方法。
enum MatchKind: String, Codable, CaseIterable, Identifiable {
    /// ホスト名。サブドメインを含む後方一致（`github.com` は `gist.github.com` にも当たる）
    case host
    /// `*` だけを使えるワイルドカード。`スキームを除いた host/path?query` に対して照合する
    case glob
    /// 正規表現。URL 全体に対する部分一致
    case regex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .host: return "ホスト"
        case .glob: return "パターン"
        case .regex: return "正規表現"
        }
    }

    var placeholder: String {
        switch self {
        case .host: return "github.com"
        case .glob: return "*.tmu.ac.jp/*"
        case .regex: return "^https://.*\\.pdf$"
        }
    }
}

struct RuleMatch: Codable, Equatable {
    var kind: MatchKind = .host
    var value: String = ""

    enum CodingKeys: String, CodingKey { case kind, value }

    init(kind: MatchKind = .host, value: String = "") {
        self.kind = kind
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(MatchKind.self, forKey: .kind)) ?? .host
        value = (try? c.decode(String.self, forKey: .value)) ?? ""
    }
}

/// 「この URL はこのブラウザで開く」1本分。
struct Rule: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var enabled: Bool = true
    var name: String = ""
    var match: RuleMatch = RuleMatch()
    /// 開くブラウザのバンドルID。パスで持つとアプリを移動した瞬間に壊れる。
    var browser: String = ""

    enum CodingKeys: String, CodingKey { case id, enabled, name, match, browser }

    init(
        id: String = UUID().uuidString,
        enabled: Bool = true,
        name: String = "",
        match: RuleMatch = RuleMatch(),
        browser: String = ""
    ) {
        self.id = id
        self.enabled = enabled
        self.name = name
        self.match = match
        self.browser = browser
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        match = (try? c.decode(RuleMatch.self, forKey: .match)) ?? RuleMatch()
        browser = (try? c.decode(String.self, forKey: .browser)) ?? ""
    }

    func matches(_ url: URL) -> Bool {
        guard enabled, !match.value.isEmpty, !browser.isEmpty else { return false }
        switch match.kind {
        case .host:
            return Self.matchHost(url, suffix: match.value)
        case .glob:
            return Self.matchGlob(url, pattern: match.value)
        case .regex:
            return Self.matchRegex(url, pattern: match.value)
        }
    }

    // MARK: - 照合

    private static func matchHost(_ url: URL, suffix: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let target = suffix.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !target.isEmpty else { return false }
        return host == target || host.hasSuffix("." + target)
    }

    /// スキームを外した `host/path?query` に対して照合する。
    /// `github.com/*` と書いたときに `https://github.com/x` が当たってほしいため。
    private static func matchGlob(_ url: URL, pattern: String) -> Bool {
        let subject = schemeless(url)
        let regex = "^" + pattern.map { character -> String in
            character == "*"
                ? ".*"
                : NSRegularExpression.escapedPattern(for: String(character))
        }.joined() + "$"
        return matches(subject, regex: regex)
    }

    private static func matchRegex(_ url: URL, pattern: String) -> Bool {
        matches(url.absoluteString, regex: pattern)
    }

    private static func matches(_ subject: String, regex: String) -> Bool {
        guard let expression = try? NSRegularExpression(
            pattern: regex, options: [.caseInsensitive]
        ) else { return false }
        let range = NSRange(subject.startIndex..<subject.endIndex, in: subject)
        return expression.firstMatch(in: subject, options: [], range: range) != nil
    }

    /// `https://github.com/a?b=1` → `github.com/a?b=1`
    /// パスが空のときは `/` を補う（`github.com/*` が裸のホストにも当たるように）。
    static func schemeless(_ url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }
        var result = host
        if let port = url.port { result += ":\(port)" }
        let path = url.path.isEmpty ? "/" : url.path
        result += path
        if let query = url.query, !query.isEmpty { result += "?" + query }
        return result
    }
}
