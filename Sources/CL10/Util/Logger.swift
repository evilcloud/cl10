import Foundation

enum LogLevel: String {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

struct Logger {
    static func log(_ level: LogLevel, _ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        FileHandle.standardOutput.write(
            "[\(level.rawValue)] \(ts) \(message)\n".data(using: .utf8)!)
    }
}
