import Foundation

final class CLIShell {
    private let cli: CLI

    init(cli: CLI) {
        self.cli = cli
    }

    func run() -> ExitCode {
        while true {
            FileHandle.standardOutput.write(Data("cl10> ".utf8))
            guard let line = readLine() else { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed == "exit" || trimmed == "quit" { break }
            let parts = Self.tokenize(trimmed)
            if parts.first == "shell" { continue }
            _ = cli.run(args: parts)
        }
        return .ok
    }

    private static func tokenize(_ line: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inQuotes = false
        var escape = false
        for ch in line {
            if escape {
                current.append(ch)
                escape = false
            } else if ch == "\\" {
                escape = true
            } else if ch == "\"" {
                inQuotes.toggle()
            } else if ch.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            args.append(current)
        }
        return args
    }
}
