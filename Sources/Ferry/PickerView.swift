import AppKit
import SwiftUI

/// 選択パネルが見ている状態。パネル側のキー入力で `index` が動く。
final class PickerModel: ObservableObject {
    @Published var index: Int = 0
    @Published var remember: Bool = false

    let url: URL
    let browsers: [BrowserApp]

    var onPick: (BrowserApp, Bool) -> Void = { _, _ in }
    var onCancel: () -> Void = {}

    init(url: URL, browsers: [BrowserApp]) {
        self.url = url
        self.browsers = browsers
    }

    var ruleHost: String? { AppState.ruleHost(for: url) }

    func pick(at index: Int) {
        guard browsers.indices.contains(index) else { return }
        onPick(browsers[index], remember)
    }

    func move(by step: Int) {
        guard !browsers.isEmpty else { return }
        let next = index + step
        index = min(max(next, 0), browsers.count - 1)
    }
}

struct PickerView: View {
    @ObservedObject var model: PickerModel

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(model.browsers.enumerated()), id: \.element.id) { index, browser in
                    BrowserCard(
                        browser: browser,
                        number: index + 1,
                        isSelected: index == model.index
                    )
                    .onTapGesture { model.pick(at: index) }
                }
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 428)
        // 枠なしウィンドウなので、背景と角丸はここで描く
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.url.host ?? model.url.absoluteString)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(model.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let host = model.ruleHost {
                Toggle(isOn: $model.remember) {
                    Text("以後 \(host) はこのブラウザで開く")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
            }
            Text("1〜9 で選択 ・ ←→ と return ・ space で上のチェック ・ esc で中止")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct BrowserCard: View {
    let browser: BrowserApp
    let number: Int
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: browser.icon)
                .resizable()
                .frame(width: 40, height: 40)
            Text(browser.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("\(number)")
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}
