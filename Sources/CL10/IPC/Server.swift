import Darwin
import Foundation

final class IPCServer {
    private let store: HistoryStore
    private let clipboard: Clipboard
    private var listenFD: Int32 = -1

    private let acceptQueue = DispatchQueue(label: "com.cl10.ipc.accept")
    private let clientQueue = DispatchQueue(label: "com.cl10.ipc.client", attributes: .concurrent)

    // Shared command handler used by server (and later the app UI)
    private let router: CommandRouter

    // Set by CLI.runWatch(): called when client sends QUIT
    var onQuit: (() -> Void)?

    init(store: HistoryStore, clipboard: Clipboard) {
        self.store = store
        self.clipboard = clipboard
        self.router = CommandRouter(store: store, clipboard: clipboard)
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

    // Wire protocol handled here:
    // QUIT (local), everything else via CommandRouter (LIST, COPY n, ADD <text>, DEL n, CLEAR, UP n, DOWN n, TOP n, VERSION, PING, FIND <q>)
    private func process(line: String) -> String {
        let (cmd, arg) = Wire.parse(line)

        // QUIT is handled locally so we can terminate the process cleanly.
        if cmd == "QUIT" {
            DispatchQueue.main.async { [weak self] in
                self?.onQuit?()
            }
            return "OK\n"
        }

        // Delegate all other commands to the shared router.
        return router.handle(cmd: cmd, arg: arg)
    }
}
