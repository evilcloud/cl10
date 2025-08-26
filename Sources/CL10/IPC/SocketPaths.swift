import Foundation

enum SocketPaths {
    static func userSocketPath() -> String {
        let uid = getuid()
        return "\(Constants.socketDir)/\(Constants.socketNamePrefix)\(uid).sock"
    }
}
