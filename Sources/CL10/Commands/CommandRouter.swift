import Foundation

/// Single source of truth for command behavior.
/// Server (IPC) and future App UI should both call this.
final class CommandRouter {
    private let store: HistoryStore
    private let clipboard: Clipboard

    init(store: HistoryStore, clipboard: Clipboard) {
        self.store = store
        self.clipboard = clipboard
    }

    /// Handle one command (wire-compatible) and return a wire-formatted reply.
    func handle(cmd: String, arg: String?) -> String {
        switch cmd {

        case "PING":
            return "PONG\n"

        case "VERSION":
            return "CL10 \(Constants.version)\n"

        case "LIST":
            let rows = store.list().enumerated().map { (i, it) in
                let preview = Normalizer.escapePreview(it.previewFirstLine)
                let bytes = Normalizer.humanBytes(it.sizeBytes)
                let lineCount = it.text.reduce(into: 1) { if $1.isNewline { $0 += 1 } }
                let metric = lineCount > 1 ? "\(bytes) · \(lineCount)L" : bytes
                return "\(i)  \"\(preview)\"  \(metric)\n"
            }.joined()
            return rows.isEmpty ? "EMPTY\n" : rows

        case "ADD":
            guard let txt = arg else { return "ERR missing text\n" }
            let norm = Normalizer.normalize(txt)
            if Normalizer.isBlank(norm) { return "ERR blank\n" }
            if Normalizer.byteCount(norm) > Constants.maxTextBytes { return "ERR oversize\n" }
            store.pushText(norm)
            return "OK\n"

        case "COPY":
            guard let a = arg, let idx = Int(a) else { return "ERR bad index\n" }
            guard let item = store.get(idx) else { return "ERR no-such-index\n" }
            clipboard.writeText(item.text)
            store.touch(idx)
            return "OK\n"

        case "DEL":
            guard let a = arg, let idx = Int(a) else { return "ERR bad index\n" }
            store.delete(index: idx)
            return "OK\n"

        case "CLEAR":
            store.clear()
            return "OK\n"

        case "UP":
            guard let a = arg, let idx = Int(a) else { return "ERR bad index\n" }
            store.moveUp(index: idx)
            return "OK\n"

        case "DOWN":
            guard let a = arg, let idx = Int(a) else { return "ERR bad index\n" }
            store.moveDown(index: idx)
            return "OK\n"

        case "TOP":
            guard let a = arg, let idx = Int(a) else { return "ERR bad index\n" }
            store.moveTop(index: idx)
            return "OK\n"

        case "FIND":
            // Substring search over preview OR full text (case-insensitive)
            guard let q = arg?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty
            else { return "ERR missing query\n" }
            let lq = q.lowercased()
            let rows = store.list().enumerated().compactMap { (i, it) -> String? in
                if it.previewFirstLine.lowercased().contains(lq)
                    || it.text.lowercased().contains(lq)
                {
                    let preview = Normalizer.escapePreview(it.previewFirstLine)
                    let bytes = Normalizer.humanBytes(it.sizeBytes)
                    let lineCount = it.text.reduce(into: 1) { if $1.isNewline { $0 += 1 } }
                    let metric = lineCount > 1 ? "\(bytes) · \(lineCount)L" : bytes
                    return "\(i)  \"\(preview)\"  \(metric)\n"
                }
                return nil
            }.joined()
            return rows.isEmpty ? "EMPTY\n" : rows

        default:
            return "ERR unknown\n"
        }
    }
}
