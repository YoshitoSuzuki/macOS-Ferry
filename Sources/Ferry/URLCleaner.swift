import Foundation

/// ブラウザに渡す前に URL を整える。
///
/// 順番は **展開 → 除去**。短縮URLを開くと展開後の URL に utm が付いてくるので、
/// 先に展開しないとトラッキングパラメータを取りこぼす。
enum URLCleaner {

    /// 短縮URLの展開にかけてよい時間の上限。
    /// ここで待たせると「リンクを開くのが遅いアプリ」になるので、絶対に伸ばさない。
    private static let budget: TimeInterval = 3.0
    private static let maxHops = 5

    static func clean(_ url: URL, with config: CleanerConfig) async -> URL {
        var result = url
        if config.expandShortLinks, isShortLink(result, hosts: config.shortLinkHosts) {
            result = await expand(result)
        }
        if config.stripTracking {
            result = strip(result, patterns: config.stripParams)
        }
        if result != url {
            AppLog.write("clean: \(url.absoluteString) → \(result.absoluteString)")
        }
        return result
    }

    // MARK: - 短縮URLの展開

    static func isShortLink(_ url: URL, hosts: [String]) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains { pattern in
            let target = pattern.lowercased().trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { return false }
            return host == target || host.hasSuffix("." + target)
        }
    }

    /// Location ヘッダを自分で辿る。失敗したら元の URL をそのまま返す。
    private static func expand(_ url: URL) async -> URL {
        let deadline = Date().addingTimeInterval(budget)
        let blocker = RedirectBlocker()
        var current = url

        for _ in 0..<maxHops {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0.2 else {
                AppLog.write("expand: 時間切れ \(current.absoluteString)")
                return current
            }

            var request = URLRequest(url: current)
            request.httpMethod = "HEAD"
            request.timeoutInterval = remaining
            request.cachePolicy = .reloadIgnoringLocalCacheData

            do {
                let (_, response) = try await URLSession.shared.data(
                    for: request, delegate: blocker
                )
                guard let http = response as? HTTPURLResponse,
                      (300..<400).contains(http.statusCode),
                      let location = http.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: current)?.absoluteURL
                else { return current }
                current = next
            } catch {
                AppLog.write("expand: 失敗したので元のURLで開く \(error.localizedDescription)")
                return current
            }
        }
        return current
    }

    /// リダイレクトを自動追尾させないためのデリゲート。
    /// 自分で1段ずつ辿るのは、途中で時間切れにしても元の URL を失わないようにするため。
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    // MARK: - トラッキングパラメータの除去

    /// `patterns` に載っているクエリパラメータだけを消す。
    /// 末尾 `*` はワイルドカード（`utm_*`）。
    /// 「知らないパラメータを消す」許可リスト方式にはしない。正常な URL を壊すため。
    static func strip(_ url: URL, patterns: [String]) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems,
              !items.isEmpty
        else { return url }

        let kept = items.filter { !shouldStrip($0.name, patterns: patterns) }
        guard kept.count != items.count else { return url }

        // 全部消えたら「?」ごと落とす
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }

    private static func shouldStrip(_ name: String, patterns: [String]) -> Bool {
        let target = name.lowercased()
        for pattern in patterns {
            let trimmed = pattern.lowercased().trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasSuffix("*") {
                if target.hasPrefix(String(trimmed.dropLast())) { return true }
            } else if target == trimmed {
                return true
            }
        }
        return false
    }
}
