import AppKit

/// 受け取った URL を1本の流れで処理する中核。
///
///     前処理（展開 → 除去） → 修飾キー判定 → ルール照合
///         一致 → そのブラウザで開く
///         不一致 → 選択パネル
///
/// URL は立て続けに届くことがあるので、キューに積んで1件ずつ順に片付ける。
/// パネルを出している最中に次のパネルを重ねない、というのが主な目的。
@MainActor
final class Router {

    static let shared = Router()

    private var queue: [(url: URL, forcePicker: Bool)] = []
    private var isBusy = false
    private let picker = PickerPanelController()

    func handle(_ urls: [URL]) {
        // 修飾キーは URL が届いた「いま」読む。
        // 処理を始めるときに読むと、短縮URLの展開を待つ間に指が離れて取りこぼす。
        let forcePicker = isForcePickerHeld()

        for url in urls {
            guard let scheme = url.scheme?.lowercased() else { continue }
            if scheme == "ferry" {
                AppDelegate.shared?.showSettings()
                continue
            }
            guard scheme == "http" || scheme == "https" else {
                AppLog.write("受信: 扱えないスキーム \(url.absoluteString)")
                continue
            }
            AppLog.write("受信: \(url.absoluteString)")
            queue.append((url, forcePicker))
        }
        pump()
    }

    /// 履歴から「別のブラウザで開き直す」。ルールを見ずに必ずパネルを出す。
    func repick(_ url: URL) {
        queue.append((url, true))
        pump()
    }

    private func pump() {
        guard !isBusy, !queue.isEmpty else { return }
        isBusy = true
        let item = queue.removeFirst()

        Task { @MainActor in
            await process(item.url, forcePicker: item.forcePicker)
            isBusy = false
            pump()
        }
    }

    private func process(_ url: URL, forcePicker: Bool) async {
        let state = AppState.shared

        if state.isPaused {
            AppLog.write("一時停止中なので逃げ先へ流す")
            deliver(url, to: state.fallbackBrowser())
            return
        }

        let cleaned = await URLCleaner.clean(url, with: state.config.cleaner)

        if forcePicker {
            AppLog.write("修飾キーが押されているのでルールを飛ばす")
        } else if let rule = state.config.firstMatch(for: cleaned) {
            if let browser = Browsers.find(bundleID: rule.browser, in: state.browsers) {
                AppLog.write("ルール一致: \(rule.name.isEmpty ? rule.match.value : rule.name)")
                deliver(cleaned, to: browser)
                return
            }
            // ルールはあるがブラウザが消えている。黙って握りつぶさず逃げ先へ。
            AppLog.write("ルールの指すブラウザが見つからない: \(rule.browser)")
            deliver(cleaned, to: state.fallbackBrowser())
            return
        }

        await showPicker(for: cleaned)
    }

    private func showPicker(for url: URL) async {
        let state = AppState.shared
        let candidates = state.pickerBrowsers
        guard !candidates.isEmpty else {
            AppLog.write("パネルに出せるブラウザが1つも無い")
            deliver(url, to: state.fallbackBrowser())
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            picker.show(
                url: url,
                browsers: candidates,
                onPick: { [weak self] browser, remember in
                    if remember {
                        state.addHostRule(for: url, browser: browser)
                    }
                    self?.deliver(url, to: browser)
                    continuation.resume()
                },
                onCancel: {
                    AppLog.write("パネルで中止: \(url.absoluteString)")
                    continuation.resume()
                }
            )
        }
    }

    /// 実際に開くのはここだけ。履歴もここで積む。
    func deliver(_ url: URL, to browser: BrowserApp?) {
        guard let browser else {
            AppLog.write("開けるブラウザが見つからない: \(url.absoluteString)")
            return
        }
        Browsers.open(url, in: browser)
        AppState.shared.record(url: url, browser: browser)
    }

    private func isForcePickerHeld() -> Bool {
        let flags = NSEvent.modifierFlags
        switch AppState.shared.config.forcePickerModifier {
        case .none: return false
        case .option: return flags.contains(.option)
        case .shift: return flags.contains(.shift)
        case .control: return flags.contains(.control)
        case .command: return flags.contains(.command)
        }
    }
}
