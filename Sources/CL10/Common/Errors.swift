import Foundation

enum ExitCode: Int32 {
    case ok = 0
    case generic = 1
    case badArgs = 2
    case notRunning = 3
    case timeout = 4
    case unsupported = 5
}

enum IPCError: Error {
    case badCommand(String)
    case indexOutOfRange
    case notFound
}
