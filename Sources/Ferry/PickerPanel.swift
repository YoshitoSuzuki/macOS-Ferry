import AppKit
import SwiftUI

/// キーを受け取れるパネル。
/// 素の `NSPanel` はタイトルバーを消すと key になれずキー入力を取りこぼす。
final class PickerWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// どのブラウザで開くかを聞くパネル。
///
/// - マウスカーソルのそばに出す
/// - 1〜9 / ←→ + return / クリックで選ぶ、esc で中止
/// - 中止したら元いたアプリにフォーカスを返す
///
/// `onPick` と `onCancel` は必ずどちらか一方だけが一度だけ呼ばれる。
/// 呼び出し側（Router）が continuation で待っているため、二重呼び出しはクラッシュになる。
@MainActor
final class PickerPanelController: NSObject, NSWindowDelegate {

    private var panel: PickerWindow?
    private var model: PickerModel?
    private var monitor: Any?
    private var previousApp: NSRunningApplication?
    private var hasFinished = true
    private var hasBecomeKey = false

    private var onPick: ((BrowserApp, Bool) -> Void)?
    private var onCancel: (() -> Void)?

    func show(
        url: URL,
        browsers: [BrowserApp],
        onPick: @escaping (BrowserApp, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        // 出す前に「いま手前にいるアプリ」を控える。中止したらここへ戻す。
        previousApp = NSWorkspace.shared.frontmostApplication
        self.onPick = onPick
        self.onCancel = onCancel
        hasFinished = false
        hasBecomeKey = false

        let model = PickerModel(url: url, browsers: browsers)
        model.onPick = { [weak self] browser, remember in
            self?.finish(with: browser, remember: remember)
        }
        model.onCancel = { [weak self] in self?.finish(with: nil, remember: false) }
        self.model = model

        let hosting = NSHostingView(rootView: PickerView(model: model))
        let size = hosting.fittingSize

        // タイトルバーを持つスタイルにすると、その分だけ上に余白が残る。
        // 枠なしにして角丸と背景は SwiftUI 側で描く。
        let created = PickerWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        created.backgroundColor = .clear
        created.isOpaque = false
        created.hasShadow = true
        created.isMovableByWindowBackground = true
        created.isFloatingPanel = true
        created.level = .floating
        created.hidesOnDeactivate = false
        created.isReleasedWhenClosed = false
        // 他アプリがフルスクリーンでも手前に出す
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.contentView = hosting
        created.delegate = self
        panel = created

        position(created, size: size)
        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)

        installMonitor()
        AppLog.write("パネル表示: \(url.absoluteString) 候補=\(browsers.count)")
    }

    // MARK: - 位置

    /// カーソルの少し下に、カーソルのあるスクリーンからはみ出さないように置く。
    private func position(_ window: NSWindow, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }

        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 12)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        // 下にはみ出すならカーソルの上に出す
        if origin.y < visible.minY + 8 {
            origin.y = min(mouse.y + 12, visible.maxY - size.height - 8)
        }
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        window.setFrameOrigin(origin)
    }

    // MARK: - キー入力

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let model = self.model, !self.hasFinished else { return event }
            return self.handle(event, model: model) ? nil : event
        }
    }

    private func handle(_ event: NSEvent, model: PickerModel) -> Bool {
        switch event.keyCode {
        case 53:  // esc
            finish(with: nil, remember: false)
            return true
        case 36, 76:  // return / enter
            model.pick(at: model.index)
            return true
        case 123:  // ←
            model.move(by: -1)
            return true
        case 124:  // →
            model.move(by: 1)
            return true
        case 49:  // space
            model.remember.toggle()
            return true
        case 48:  // tab
            let next = model.index + (event.modifierFlags.contains(.shift) ? -1 : 1)
            let count = model.browsers.count
            if count > 0 { model.index = (next + count) % count }
            return true
        default:
            break
        }

        if let character = event.charactersIgnoringModifiers?.first,
           let number = character.wholeNumberValue,
           (1...9).contains(number),
           model.browsers.indices.contains(number - 1) {
            model.pick(at: number - 1)
            return true
        }
        return false
    }

    // MARK: - 終了

    /// `browser` が nil なら中止。
    private func finish(with browser: BrowserApp?, remember: Bool) {
        guard !hasFinished else { return }
        hasFinished = true  // 片付けの途中で resignKey が来ても二重に呼ばせない

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        model = nil

        let pick = onPick
        let cancel = onCancel
        onPick = nil
        onCancel = nil

        if let browser {
            // ブラウザ側が前面に出るので、ここでフォーカスを戻す必要はない
            pick?(browser, remember)
        } else {
            previousApp?.activate()
            cancel?()
        }
        previousApp = nil
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        hasBecomeKey = true
    }

    /// パネルの外をクリックしたら中止扱いにする。
    /// 表示直後（まだ key になっていない）の通知では閉じない。
    func windowDidResignKey(_ notification: Notification) {
        guard hasBecomeKey, !hasFinished else { return }
        finish(with: nil, remember: false)
    }
}
