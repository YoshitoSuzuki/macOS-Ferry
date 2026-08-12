import AppKit
import SwiftUI

/// 設定画面。
///
/// **画面に説明文を置かない。** 項目名は5文字程度の名詞だけにして、
/// 意味・使い方・注意点は docs/usage.md に書く。
struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    @State private var defaultBrowserName = ""
    @State private var stripParamsText = ""
    @State private var shortLinkHostsText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                defaultBrowserSection
                behaviorSection
                pickerBrowsersSection
                rulesSection
                cleanerSection
                filesSection
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 500)
        .onChange(of: state.config) { _, _ in state.save() }
        .onAppear {
            refreshDefaultBrowser()
            stripParamsText = state.config.cleaner.stripParams.joined(separator: "\n")
            shortLinkHostsText = state.config.cleaner.shortLinkHosts.joined(separator: "\n")
        }
    }

    // MARK: - 既定ブラウザ

    private var defaultBrowserSection: some View {
        SettingsSection("既定") {
            HStack(spacing: 10) {
                Text(defaultBrowserName.isEmpty ? "—" : defaultBrowserName)
                    .fontWeight(.semibold)
                Spacer()
                Button("更新") { refreshDefaultBrowser() }
                if let previous = previousBrowser {
                    Button("戻す") { apply(previous.url) }
                }
                Button("Ferry にする") { makeFerryDefault() }
                    .disabled(Browsers.isFerryDefault())
            }
            .controlSize(.small)
        }
    }

    private var previousBrowser: BrowserApp? {
        guard Browsers.isFerryDefault(),
              let id = state.config.previousDefaultBrowser,
              id != Bundle.main.bundleIdentifier else { return nil }
        return Browsers.find(bundleID: id, in: state.browsers)
    }

    private func refreshDefaultBrowser() {
        defaultBrowserName = Browsers.currentDefault()?.name ?? ""
    }

    private func makeFerryDefault() {
        // 切り替える前に、いまの既定ブラウザを控えておく。
        // これが無いと Ferry が壊れたときにリンクを開く手段を失う。
        if let current = Browsers.currentDefault(),
           current.id != Bundle.main.bundleIdentifier {
            state.config.previousDefaultBrowser = current.id
            state.save()
        }
        apply(Bundle.main.bundleURL)
    }

    private func apply(_ appURL: URL) {
        Browsers.setDefault(to: appURL) { error in
            refreshDefaultBrowser()
            if let error { AppLog.write("既定ブラウザの切り替えに失敗: \(error)") }
        }
    }

    // MARK: - 動作

    /// ラベルは左揃えで縦に並べ、コントロールの左端と幅を揃える。
    /// Picker の既定のラベル配置は右揃えになるので、ラベルは自分で置いて
    /// `labelsHidden()` にし、幅も明示する。
    private var behaviorSection: some View {
        SettingsSection("動作") {
            VStack(alignment: .leading, spacing: 10) {
                settingRow("修飾キー") {
                    Picker("", selection: $state.config.forcePickerModifier) {
                        ForEach(ModifierChoice.allCases) { choice in
                            item(choice.label).tag(choice)
                        }
                    }
                }
                settingRow("設定ブラウザ") {
                    Picker("", selection: fallbackBinding) {
                        item("自動").tag("")
                        ForEach(state.browsers) { browser in
                            item(browser.name).tag(browser.id)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Picker の幅は「いちばん広い項目」で決まる。項目の幅を固定して、
    /// どの Picker も同じ幅のボタンになるようにする。
    private func item(_ title: String) -> some View {
        Text(title).frame(width: Self.controlWidth - 26, alignment: .leading)
    }

    private static let controlWidth: CGFloat = 220

    private func settingRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .frame(width: 100, alignment: .leading)
            control()
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(width: Self.controlWidth)
            Spacer(minLength: 0)
        }
    }

    private var fallbackBinding: Binding<String> {
        Binding(
            get: { state.config.fallbackBrowser ?? "" },
            set: { state.config.fallbackBrowser = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: - パネルに出すブラウザ

    private var pickerBrowsersSection: some View {
        SettingsSection("パネル") {
            ForEach(state.browsers) { browser in
                Toggle(isOn: pickerBinding(browser.id)) {
                    HStack(spacing: 6) {
                        Image(nsImage: browser.icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(browser.name)
                    }
                }
                .toggleStyle(.checkbox)
            }
            Button("更新") { state.refreshBrowsers() }
                .controlSize(.small)
        }
    }

    private func pickerBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: {
                state.config.pickerBrowsers.isEmpty
                    || state.config.pickerBrowsers.contains(id)
            },
            set: { isOn in
                // 「空＝全部出す」なので、初めて外すときに現在の一覧へ展開しておく
                var list = state.config.pickerBrowsers.isEmpty
                    ? state.browsers.map(\.id)
                    : state.config.pickerBrowsers
                if isOn {
                    if !list.contains(id) { list.append(id) }
                } else {
                    list.removeAll { $0 == id }
                }
                state.config.pickerBrowsers = list
            }
        )
    }

    // MARK: - ルール

    private var rulesSection: some View {
        SettingsSection("ルール") {
            ForEach(state.config.rules) { rule in
                if let index = state.config.rules.firstIndex(where: { $0.id == rule.id }) {
                    ruleRow(index)
                }
            }
            Button("追加") {
                state.config.rules.append(Rule(browser: state.browsers.first?.id ?? ""))
            }
            .controlSize(.small)
        }
    }

    private func ruleRow(_ index: Int) -> some View {
        let rule = state.config.rules[index]
        let isLast = index == state.config.rules.count - 1
        return HStack(spacing: 6) {
            Toggle("", isOn: $state.config.rules[index].enabled)
                .labelsHidden()

            Picker("", selection: $state.config.rules[index].match.kind) {
                ForEach(MatchKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 96)

            TextField(rule.match.kind.placeholder, text: $state.config.rules[index].match.value)
                .textFieldStyle(.roundedBorder)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)

            browserPicker(for: index)
                .frame(width: 150)

            Button { swap(index, index - 1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
            Button { swap(index, index + 1) } label: { Image(systemName: "chevron.down") }
                .disabled(isLast)
            Button { state.config.rules.remove(at: index) } label: { Image(systemName: "trash") }
        }
        .buttonStyle(.borderless)
    }

    private func browserPicker(for index: Int) -> some View {
        let selected = state.config.rules[index].browser
        let installed = state.browsers.map(\.id)
        return Picker("", selection: $state.config.rules[index].browser) {
            if selected.isEmpty {
                Text("—").tag("")
            } else if !installed.contains(selected) {
                Text(selected).tag(selected)
            }
            ForEach(state.browsers) { browser in
                Text(browser.name).tag(browser.id)
            }
        }
        .labelsHidden()
    }

    private func swap(_ from: Int, _ to: Int) {
        guard state.config.rules.indices.contains(from),
              state.config.rules.indices.contains(to) else { return }
        state.config.rules.swapAt(from, to)
    }

    // MARK: - URL の前処理

    private var cleanerSection: some View {
        SettingsSection("URL") {
            Toggle("トラッキング", isOn: $state.config.cleaner.stripTracking)
                .toggleStyle(.checkbox)
            TextEditor(text: $stripParamsText)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 80)
                .border(Color.secondary.opacity(0.3))
                .onChange(of: stripParamsText) { _, text in
                    state.config.cleaner.stripParams = lines(text)
                }

            Toggle("短縮URL", isOn: $state.config.cleaner.expandShortLinks)
                .toggleStyle(.checkbox)
                .padding(.top, 4)
            TextEditor(text: $shortLinkHostsText)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 80)
                .border(Color.secondary.opacity(0.3))
                .onChange(of: shortLinkHostsText) { _, text in
                    state.config.cleaner.shortLinkHosts = lines(text)
                }
        }
    }

    private func lines(_ text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - ファイル

    private var filesSection: some View {
        SettingsSection("ファイル") {
            HStack(spacing: 8) {
                Button("設定") {
                    NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.url])
                }
                Button("ログ") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppLog.path])
                }
            }
            .controlSize(.small)
        }
    }
}

/// 見出し付きの枠。設定画面はこれの積み重ねでできている。
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }
}
