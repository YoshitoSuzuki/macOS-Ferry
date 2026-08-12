import Foundation

/// アプリの動きを追うための小さなログ。
///
/// Ferry は LaunchServices から起動されるので標準出力がどこにも出ない。
/// 「リンクを踏んだのに何も起きない」を追えるよう、URLを受け取ってから
/// ブラウザを起動するまでの経路だけは必ず残す。
enum AppLog {

    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Ferry.log")

    private static let queue = DispatchQueue(label: "one.yoshito.Ferry.log")

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        queue.async {
            let line = "\(stamp.string(from: Date())) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            let directory = path.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            if let handle = try? FileHandle(forWritingTo: path) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: path)
            }
        }
    }
}
