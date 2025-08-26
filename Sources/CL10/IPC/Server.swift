import Darwin
import Foundation

final class IPCServer {
    private let store: HistoryStore
    private let clipboard: Clipboard
    private var listenFD: Int32 = -1

    private let acceptQueue = DispatchQueue(label: "com.cl10.ipc.accept")
    private let clientQueue = DispatchQueue(label: "com.cl10.ipc.client", attributes: .concurrent)

    // Set by CLI.runWatch(): called when client sends QUIT
    var onQuit: (() -> Void)?

    init(store: HistoryStore, clipboard: Clipboard) {
        self.store = store
        self.clipboard = clipboard
    }

    func start() throws {
        let path = SocketPaths.userSocketPath()
        unlink(path)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw NSError(domain: "socket", code: 1) }

        var sun = sockaddr_un()
        memset(&sun, 0, MemoryLayout<sockaddr_un>.size)
        #if os(macOS)
            sun.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        sun.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &sun.sun_path) { dst in
            path.withCString { cs in
                _ = strlcpy(dst.baseAddress!.assumingMemoryBound(to: CChar.self), cs, dst.count)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindRes = withUnsafePointer(to: &sun) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(listenFD, sa, addrLen)
            }
        }
        guard bindRes == 0 else { throw NSError(domain: "bind", code: 2) }

        _ = chmod(path, 0o600)
        guard listen(listenFD, 64) == 0 else { throw NSError(domain: "listen", code: 3) }

        Logger.log(.info, "IPC listening at \(path)")
        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(SocketPaths.userSocketPath())
    }

    private func acceptLoop() {
        while true {
            var addr = sockaddr()
            var len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
            let fd = accept(listenFD, &addr, &len)
            if fd < 0 { continue }
            clientQueue.async { [weak self] in self?.handle(fd: fd) }
        }
    }

    private func handle(fd: Int32) {
        var buf = Data()
        let tmpSize = 1024
        var tmp = [UInt8](repeating: 0, count: tmpSize)

        // Read a single line (until '\n')
        while true {
            let n: Int = tmp.withUnsafeMutableBytes { mb in
                guard let p = mb.baseAddress else { return -1 }
                return read(fd, p, tmpSize)
            }
            if n <= 0 { break }
            buf.append(tmp, count: n)
            if let nl = buf.firstIndex(of: 0x0A) {
                let lineData = buf[..<nl]
                let line = String(decoding: lineData, as: UTF8.self)
                let reply = process(line: line)
                if let data = reply.data(using: .utf8) {
                    data.withUnsafeBytes { raw in _ = write(fd, raw.baseAddress, data.count) }
                }
                break
            }
        }
        close(fd)
    }

    // Wire protocol: LIST, COPY n, ADD <text>, DEL n, CLEAR, UP n, DOWN n, TOP n, VERSION, PING, FIND <q>, QUIT
    private func process(line: String) -> String {
        let (cmd, arg) = Wire.parse(line)
        switch cmd {
        case "PING":
            return "PONG\n"

        case "VERSION":
            return "CL10 \(Constants.version)\n"

        case "LIST":
            let rows = store.list().enumerated().map { (i, it) in
                let preview = Normalizer.escapePreview(it.previewFirstLine)
                return "\(i)  \"\(preview)\"  \(Normalizer.humanBytes(it.sizeBytes))\n"
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
            // FIND <query> → returns only matching rows, keeping canonical indices
            guard let q = arg?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty
            else { return "ERR missing query\n" }

            let lq = q.lowercased()
            let rows = store.list().enumerated().compactMap { (i, it) -> String? in
                if it.previewFirstLine.lowercased().contains(lq)
                    || it.text.lowercased().contains(lq)
                {
                    let preview = Normalizer.escapePreview(it.previewFirstLine)
                    return "\(i)  \"\(preview)\"  \(Normalizer.humanBytes(it.sizeBytes))\n"
                }
                return nil
            }.joined()
            return rows.isEmpty ? "EMPTY\n" : rows

        case "QUIT":
            // Reply OK, then trigger shared shutdown path on main queue
            DispatchQueue.main.async { [weak self] in
                self?.onQuit?()
            }
            return "OK\n"

        default:
            return "ERR unknown\n"
        }
    }
}
