import Darwin
import Foundation

final class IPCClient {
    func send(line: String) throws -> String {
        let path = SocketPaths.userSocketPath()

        // 1) create socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: "socket", code: 1) }

        // 2) set non-blocking only for connect
        let origFlags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, origFlags | O_NONBLOCK)

        // 3) sockaddr_un
        var sun = sockaddr_un()
        memset(&sun, 0, MemoryLayout<sockaddr_un>.size)
        #if os(macOS)
            sun.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        sun.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &sun.sun_path) { dst in
            path.withCString { cs in
                _ = strlcpy(
                    dst.baseAddress!.assumingMemoryBound(to: CChar.self),
                    cs, dst.count)  // NUL-terminated
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &sun) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, addrLen)
            }
        }

        // 4) finish non-blocking connect with POLLOUT
        if rc != 0 {
            if errno != EINPROGRESS {
                close(fd)
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let res = poll(&pfd, 1, Int32(Constants.connectTimeoutMs))
            if res <= 0 || (pfd.revents & Int16(POLLOUT)) == 0 {
                close(fd)
                throw NSError(domain: "timeout", code: 1)  // connect timeout
            }
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
            if err != 0 {
                close(fd)
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(err))
            }
        }

        // 5) switch back to blocking for stable IO
        _ = fcntl(fd, F_SETFL, origFlags & ~O_NONBLOCK)

        // 6) write full command + newline
        let out = (line + "\n").data(using: .utf8)!
        try writeAll(fd: fd, data: out)

        // 7) wait for response with POLLIN (2s)
        var rfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let wait = poll(&rfd, 1, Int32(Constants.ioTimeoutSec * 1000))
        if wait <= 0 || (rfd.revents & Int16(POLLIN)) == 0 {
            close(fd)
            return ""  // signal timeout to caller
        }

        // 8) read until EOF
        var data = Data()
        let bufSize = 1024
        var buf = [UInt8](repeating: 0, count: bufSize)
        while true {
            let n: Int = buf.withUnsafeMutableBytes { mb in
                guard let p = mb.baseAddress else { return -1 }
                return read(fd, p, bufSize)
            }
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        close(fd)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { raw in
            var sent = 0
            while sent < data.count {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), data.count - sent)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                sent += n
            }
        }
    }
}
