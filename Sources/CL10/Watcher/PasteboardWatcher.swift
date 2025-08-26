// Sources/CL10/Watcher/PasteboardWatcher.swift
import Foundation

final class PasteboardWatcher {
    private let clipboard: Clipboard
    private let store: HistoryStore
    private var timer: DispatchSourceTimer?

    init(clipboard: Clipboard, store: HistoryStore) {
        self.clipboard = clipboard
        self.store = store
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        t.schedule(deadline: .now(), repeating: .milliseconds(150))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        self.timer = t
        Logger.log(.info, "Watcher started")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        Logger.log(.info, "Watcher stopped")
    }

    private func tick() {
        if let s = clipboard.readNewTextIfAvailable() {
            let norm = Normalizer.normalize(s)
            if Normalizer.isBlank(norm) { return }
            let bytes = Normalizer.byteCount(norm)
            if bytes > Constants.maxTextBytes {
                Logger.log(.warn, "Skipped text >256KB")
                return
            }
            store.pushText(norm)
            Logger.log(.info, "Capture: \(Normalizer.escapePreview(Normalizer.firstLine(norm)))")
        }
    }
}
