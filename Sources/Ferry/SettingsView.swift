import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    @State private var defaultBrowserName = ""
    @State private var statusMessage = ""
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
        // 画面のどこを触っても設定はその場で保存する
        .onChange(of: state.config) { _, _ in state.save() }
        .onAppear {
            refreshDefaultBrowser()
            stripParamsText = state.config.cleaner.stripParams.joined(separator: "\n")
            shortLinkHostsText = state.config.cleaner.shortLinkHosts.joined(separator: "\n")
        }
    }

    // MARK: - 既定ブラウザ

    private var defaultBrowserSection: some View {
        SettingsSection("既定ブラウザ") {
            HStack(spacing: 8) {
                Text("いまの既定:")
                Text(defaultBrowserName.isEmpty ? "不明" : defaultBrowserName)
                    .fontWeight(.semibold)
                Spacer()
                Button("再確認") { refreshDefaultBrowser() }
                    .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button("Ferry を既定のブラウザにする") { makeFerryDefault() }
                    .disabled(Browsers.isFerryDefault())
                if let previous = previousBrowser {
                    Button("\(previous.name) に戻す") { restore(to: previous) }
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(
                "ボタンが効かないときは システム設定 → デスクトップとDock → デフォルトのWebブラウザ "
                    + "から Ferry を選ぶ。"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var previousBrowser: BrowserApp? {
        guard let id = state.config.previousDefaultBrowser,
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
        apply(Bundle.main.bundleURL, label: "Ferry")
    }

    private func restore(to browser: BrowserApp) {
        apply(browser.url, label: browser.name)
    }

    private func apply(_ appURL: URL, label: String) {
        statusMessage = "\(label) に切り替えています…"
        Browsers.setDefault(to: appURL) { error in
            refreshDefaultBrowser()
            if let error {
                statusMessage = "切り替えに失敗しました: \(error.localizedDescription)"
            } else {
                statusMessage = "既定ブラウザを \(label) にしました。"
            }
        }
    }

    // MARK: - 動作

    private var behaviorSection: some View {
        SettingsSection("動作") {
            Picker("ルールを飛ばしてパネルを出す修飾キー", selection: $state.config.forcePickerModifier) {
                ForEach(ModifierChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            Text("リンクを開き終わるまで押したままにする。")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Picker("逃げ先のブラウザ", selection: fallbackBinding) {
                Text("自動").tag("")
                ForEach(state.browsers) { browser in
                    Text(browser.name).tag(browser.id)
                }
            }
            Text("一時停止中と、ルールの指すブラウザが見つからないときに使う。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
        SettingsSection("選択パネルに出すブラウザ") {
            ForEach(state.browsers) { browser in
                Toggle(isOn: pickerBinding(browser.id)) {
                    HStack(spacing: 6) {
                        Image(nsImage: browser.icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(browser.name)
                        Text(browser.id)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            Button("一覧を更新") { state.refreshBrowsers() }
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
            Text("上から順に照合し、最初に当たったものを使う。")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if state.config.rules.isEmpty {
                Text("ルールはまだ無い。選択パネルの「以後このホストは…」からでも追加できる。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(state.config.rules) { rule in
                if let index = state.config.rules.firstIndex(where: { $0.id == rule.id }) {
                    ruleRow(index)
                }
            }

            Button("ルールを追加") {
                state.config.rules.append(
                    Rule(browser: state.browsers.first?.id ?? "")
                )
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
                .help("無効にする")

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
                Text("未選択").tag("")
            } else if !installed.contains(selected) {
                Text("\(selected)（見つからない）").tag(selected)
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
        SettingsSection("URL の前処理") {
            Toggle("トラッキングパラメータを消す", isOn: $state.config.cleaner.stripTracking)
                .toggleStyle(.checkbox)
            Text("1行に1つ。末尾の * はワイルドカード（utm_*）。ここに書いたものだけを消す。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            TextEditor(text: $stripParamsText)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 80)
                .border(Color.secondary.opacity(0.3))
                .onChange(of: stripParamsText) { _, text in
                    state.config.cleaner.stripParams = lines(text)
                }

            Toggle("短縮URLを展開してから開く", isOn: $state.config.cleaner.expandShortLinks)
                .toggleStyle(.checkbox)
            Text("1行に1ホスト。ここに書いたホストだけ展開する（最大3秒、失敗したら元のURLで開く）。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
            HStack {
                Button("設定ファイルを表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.url])
                }
                Button("ログを表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppLog.path])
                }
            }
            .controlSize(.small)
            Text(ConfigStore.url.path)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
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
