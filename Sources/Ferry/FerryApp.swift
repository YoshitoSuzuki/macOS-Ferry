import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
struct FerryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // 画面はすべて AppDelegate が NSWindow / NSStatusItem として持つ。
    // SwiftUI の App は Scene を1つ要求するので、中身の無い Settings を置いておく。
    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// メニュー項目の `@objc` メソッドまで含めてメインスレッド前提なので、クラスごと隔離する。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    /// `NSApp.delegate` は SwiftUI の `NSApplicationDelegateAdaptor` が挟む
    /// 内部オブジェクトなので、自前の型にキャストすると nil になる。
    /// 生成時に自分を控えておく。
    private(set) static var shared: AppDelegate?

    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var pauseObserver: AnyCancellable?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist の LSUIElement ではなく実行時に設定する。
        // LSUIElement を書くとシステム設定の「デフォルトのWebブラウザ」一覧に
        // 出ない可能性があり、出なければこのアプリは成立しない。
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()

        pauseObserver = AppState.shared.$isPaused.sink { [weak self] paused in
            self?.updateStatusIcon(paused: paused)
        }

        AppLog.write(
            "起動: 既定ブラウザ=\(Browsers.currentDefault()?.name ?? "不明") "
                + "候補=\(AppState.shared.browsers.count)"
        )
    }

    /// URL を受け取る入口。ここが Ferry の本体。
    func application(_ application: NSApplication, open urls: [URL]) {
        Router.shared.handle(urls)
    }

    /// Dock や Launchpad から起動し直されたとき
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - メニューバー

    /// SwiftUI の `MenuBarExtra` は使わない。
    /// 実行時に `.accessory` へ切り替えるとパネルが開かず、画面外に 500x500 の
    /// 空ウィンドウだけが残る。NSStatusItem なら活性化ポリシーに左右されない。
    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Ferry"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        updateStatusIcon(paused: AppState.shared.isPaused)
    }

    private func updateStatusIcon(paused: Bool) {
        statusItem?.button?.image = NSImage(
            systemSymbolName: paused ? "pause.circle" : "ferry.fill",
            accessibilityDescription: paused ? "Ferry（一時停止中）" : "Ferry"
        )
    }

    /// 項目名は名詞だけにする。状態はチェックマークで示し、文章では書かない。
    func menuNeedsUpdate(_ menu: NSMenu) {
        let state = AppState.shared
        menu.removeAllItems()

        let isDefault = NSMenuItem(title: "既定ブラウザ", action: nil, keyEquivalent: "")
        isDefault.isEnabled = false
        isDefault.state = Browsers.isFerryDefault() ? .on : .off
        menu.addItem(isDefault)

        let pause = NSMenuItem(
            title: "一時停止", action: #selector(togglePause), keyEquivalent: ""
        )
        pause.target = self
        pause.state = state.isPaused ? .on : .off
        menu.addItem(pause)

        if !state.history.isEmpty {
            menu.addItem(.separator())
            menu.addItem(header("履歴"))
            for entry in state.history.prefix(5) {
                let title = "\(entry.url.host ?? entry.url.absoluteString) — \(entry.browserName)"
                let item = NSMenuItem(
                    title: title, action: #selector(repick(_:)), keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry.url
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let login = NSMenuItem(
            title: "自動起動", action: #selector(toggleLaunchAtLogin), keyEquivalent: ""
        )
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let settings = NSMenuItem(
            title: "設定…", action: #selector(openSettings), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func togglePause() {
        AppState.shared.isPaused.toggle()
    }

    @objc private func repick(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        Router.shared.repick(url)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // ad-hoc 署名だと登録できないことがある。
            // 対処（システム設定から手で追加する）は docs/usage.md に書く。
            AppLog.write("ログイン項目の変更に失敗: \(error)")
            let alert = NSAlert()
            alert.messageText = "登録できませんでした"
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 設定ウィンドウ

    @objc func openSettings() {
        showSettings()
    }

    @MainActor
    func showSettings() {
        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            created.title = "設定"
            created.isReleasedWhenClosed = false
            created.center()
            created.setFrameAutosaveName("FerrySettingsWindow")
            created.contentView = NSHostingView(
                rootView: SettingsView().environmentObject(AppState.shared)
            )
            window = created
        }
        AppState.shared.refreshBrowsers()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
