import Foundation

enum Wire {
    // Commands: LIST, COPY n, ADD <text>, DEL n, CLEAR, UP n, DOWN n, TOP n, VERSION, PING
    static func parse(_ line: String) -> (cmd: String, arg: String?) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("", nil) }
        if let sp = trimmed.firstIndex(of: " ") {
            let c = String(trimmed[..<sp]).uppercased()
            let a = String(trimmed[trimmed.index(after: sp)...])
            return (c, a)
        } else {
            return (trimmed.uppercased(), nil)
        }
    }
}
