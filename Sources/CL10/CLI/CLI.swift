import Darwin
import Foundation

final class CLI {
    private let client = IPCClient()

    // Keep signal sources alive
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?

    // Simple writers to avoid fputs(String, …) footguns
    private func writeOut(_ s: String) { FileHandle.standardOutput.write(Data(s.utf8)) }
    private func writeErr(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }

    func run(args: [String]) -> ExitCode {
        guard let sub = args.first else {
            printUsage()
            return .badArgs
        }
        switch sub {
        case "watch":
            return runWatch()

        case "list":
            return talk("LIST")
        case "find":
            // cl10 find <query> → show only matching rows (indices stay canonical)
            guard args.count >= 2 else {
                writeErr("E2 Missing query\n")
                return .badArgs
            }
            let q = args.dropFirst().joined(separator: " ")
            return talk("FIND \(q)")

        case "copy":
            guard args.count >= 2, Int(args[1]) != nil else { return badIndex() }
            return talk("COPY \(args[1])")

        case "add":
            guard args.count >= 2 else {
                writeErr("E2 Missing text\n")
                return .badArgs
            }
            let text = args.dropFirst().joined(separator: " ")
            return talk("ADD \(text)")

        case "del":
            guard args.count >= 2, Int(args[1]) != nil else { return badIndex() }
            return talk("DEL \(args[1])")

        case "clear":
            if isatty(STDIN_FILENO) != 0 {
                writeErr("Type YES to clear all (cannot be undone): ")
                fflush(stderr)
                var lineptr: UnsafeMutablePointer<CChar>? = nil
                var n: size_t = 0
                let rc = getline(&lineptr, &n, stdin)
                let input =
                    (rc > 0)
                    ? String(cString: lineptr!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                if input != "YES" {
                    writeErr("Aborted.\n")
                    return .generic
                }
            }
            return talk("CLEAR")

        case "up":
            guard args.count >= 2, Int(args[1]) != nil else { return badIndex() }
            return talk("UP \(args[1])")

        case "down":
            guard args.count >= 2, Int(args[1]) != nil else { return badIndex() }
            return talk("DOWN \(args[1])")

        case "top":
            guard args.count >= 2, Int(args[1]) != nil else { return badIndex() }
            return talk("TOP \(args[1])")

        case "version":
            return showVersion()

        default:
            printUsage()
            return .badArgs
        }
    }

    private func showVersion() -> ExitCode {
        // Always print CLI version
        writeOut("CLI \(Constants.version)\n")
        // Try to get watcher version; if not running, just return OK
        do {
            let reply = try client.send(line: "VERSION")  // watcher responds like: "CL10 0.1.0-mvp\n"
            if !reply.isEmpty {
                // Normalize to "Watcher <version>"
                let watcherVersion =
                    reply
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "CL10 ", with: "")
                writeOut("Watcher \(watcherVersion)\n")
            }
        } catch {
            // watcher not running; that's fine for 'version'
        }
        return .ok
    }

    private func badIndex() -> ExitCode {
        writeErr("E2 Index out of range. Use 'cl10 list' for valid indices.\n")
        return .badArgs
    }

    private func talk(_ line: String) -> ExitCode {
        do {
            let reply = try client.send(line: line)
            if reply.isEmpty {
                writeErr("E4 Timed out talking to watcher. Is it running?\n")
                return .timeout
            }
            if reply.hasPrefix("ERR") {
                writeErr(reply)
                if reply.contains("no-such-index") { return .badArgs }
                return .generic
            } else {
                writeOut(reply)
                return .ok
            }
        } catch let e as NSError {
            if e.domain == "timeout" {
                writeErr("E4 Timed out talking to watcher. Is it running?\n")
                return .timeout
            }
            writeErr("E3 Watcher not running. Start it with: cl10 watch\n")
            return .notRunning
        }
    }

    private func runWatch() -> ExitCode {
        let store = HistoryStore()
        let clipboard = Clipboard()
        let watcher = PasteboardWatcher(clipboard: clipboard, store: store)
        let server = IPCServer(store: store, clipboard: clipboard)

        // Single instance check
        let path = SocketPaths.userSocketPath()
        if FileManager.default.fileExists(atPath: path) {
            let c = IPCClient()
            do {
                _ = try c.send(line: "PING")
                writeErr("Watcher already running.\n")
                return .generic
            } catch {
                unlink(path)  // stale socket
            }
        }

        do {
            try server.start()
        } catch {
            writeErr("Failed to start IPC server. Remove stale socket at \(path) and retry.\n")
            return .generic
        }

        watcher.start()

        // Clean shutdown on SIGINT/SIGTERM using GCD signals (capture-safe)
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let shutdown: () -> Void = {
            Logger.log(.info, "Shutting down…")
            watcher.stop()
            server.stop()
            exit(0)
        }

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler(handler: shutdown)
        sigint.resume()
        self.sigintSource = sigint

        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler(handler: shutdown)
        sigterm.resume()
        self.sigtermSource = sigterm

        RunLoop.main.run()  // keep the main thread alive
        return .ok

    }

    private func printUsage() {
        let u = """
            Usage: cl10 <command> [args]

              watch             Start the watcher (foreground)
              list              Show indices with previews
              find "q"          Show only entries matching q (keeps canonical indices)
              copy N            Copy entry at index N to pasteboard
              add "text"        Add arbitrary text as newest entry (no clipboard)
              del N             Delete entry N
              clear             Clear all (asks to confirm if TTY)
              up|down|top N     Reorder operations
              version           Print build version

            If the watcher is not running, most commands will fail with E3.
            """
        writeErr(u + "\n")
    }
}
