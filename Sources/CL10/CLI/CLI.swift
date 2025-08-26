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

        // Management / local-process commands
        switch sub {
        case "watch": return runWatch()
        case "version": return showVersion()
        case "quit": return talk("QUIT")
        case "help":
            printUsage()
            return .ok
        default: break
        }

        // One-digit fast path: `cl10 3` → COPY 3
        if let n = Int(sub), args.count == 1 {
            return talk("COPY \(n)")
        }

        // Everything else is thin pass-through to the server/router
        return forward(args)
    }

    // MARK: - Thin forwarder to the wire/CommandRouter
    private func forward(_ args: [String]) -> ExitCode {
        let cmd = args[0].lowercased()

        switch cmd {
        case "list":
            return talk("LIST")

        case "find":
            guard args.count >= 2 else {
                writeErr("E2 Missing query\n")
                return .badArgs
            }
            let q = args.dropFirst().joined(separator: " ")
            return talk("FIND \(q)")

        case "copy", "add", "clear", "up", "down", "top":
            // Minimal shaping; server/CommandRouter does the validation
            let upper = cmd.uppercased()
            let tail = args.dropFirst().joined(separator: " ")
            let line = tail.isEmpty ? upper : "\(upper) \(tail)"
            return talk(line)

        case "del":
            // Client expands multi-targets to many DEL calls (server stays simple)
            guard args.count >= 2 else { return badIndex() }
            guard let targets = parseTargets(args.dropFirst()) else { return badIndex() }
            var rc: ExitCode = .ok
            for idx in targets {
                let r = talk("DEL \(idx)")
                if r != .ok { rc = r }
            }
            return rc

        default:
            printUsage()
            return .badArgs
        }
    }

    // MARK: - Helpers

    private func parseTargets(_ parts: ArraySlice<String>) -> [Int]? {
        var out = Set<Int>()
        for tok in parts {
            for piece in tok.split(separator: ",") {
                if let dash = piece.firstIndex(of: "-") {
                    let aStr = piece[..<dash]
                    let bStr = piece[piece.index(after: dash)...]
                    guard let a = Int(aStr), let b = Int(bStr) else { return nil }
                    let lo = min(a, b)
                    let hi = max(a, b)
                    for i in lo...hi { out.insert(i) }
                } else {
                    guard let v = Int(piece) else { return nil }
                    out.insert(v)
                }
            }
        }
        // Delete descending so indices remain valid
        return out.sorted(by: >)
    }

    private func showVersion() -> ExitCode {
        // Always print CLI version
        writeOut("CLI \(Constants.version)\n")
        // Try to get watcher version; if not running, just return OK
        do {
            let reply = try client.send(line: "VERSION")
            if !reply.isEmpty {
                let watcherVersion =
                    reply
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "CL10 ", with: "")
                writeOut("Watcher \(watcherVersion)\n")
            }
        } catch { /* watcher not running; that's fine for 'version' */  }
        return .ok
    }

    private func badIndex() -> ExitCode {
        writeErr("E2 Bad or missing index/indices. Use 'cl10 list' for valid indices.\n")
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

        // Allow remote QUIT to trigger the same shutdown path
        server.onQuit = { shutdown() }

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

              watch               Start the watcher (foreground)
              0..9                Copy entry at index N (digit shortcut)
              list                Show indices with previews
              find "q"            Show only entries matching q (canonical indices)
              copy N              Copy entry at index N to pasteboard
              add "text"          Add arbitrary text as newest entry (no clipboard)
              del N|N-M …         Delete one or many indices (lists/ranges allowed)
              clear               Clear all (asks to confirm if TTY)
              up|down|top N       Reorder operations
              version             Print build version
              quit                Ask the watcher to shut down

            (Behavior lives in the app host via CommandRouter; CLI just forwards.)
            """
        writeErr(u + "\n")
    }
}
