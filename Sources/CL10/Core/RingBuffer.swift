import Foundation

final class RingBuffer {
    private var items: [HistoryItem] = []
    private let capacity: Int
    private let queue = DispatchQueue(label: "com.cl10.ring", attributes: .concurrent)

    init(capacity: Int) { self.capacity = capacity }

    func list() -> [HistoryItem] { queue.sync { items } }
    func clear() { queue.async(flags: .barrier) { self.items.removeAll() } }

    func delete(index: Int) {
        queue.async(flags: .barrier) {
            if index >= 0 && index < self.items.count { self.items.remove(at: index) }
        }
    }

    func moveUp(index: Int) {
        queue.async(flags: .barrier) {
            guard index > 0, index < self.items.count else { return }
            self.items.swapAt(index, index - 1)
        }
    }

    func moveDown(index: Int) {
        queue.async(flags: .barrier) {
            guard index >= 0, index < self.items.count - 1 else { return }
            self.items.swapAt(index, index + 1)
        }
    }

    func moveTop(index: Int) {
        queue.async(flags: .barrier) {
            guard index >= 0, index < self.items.count else { return }
            let item = self.items.remove(at: index)
            self.items.insert(item, at: 0)
        }
    }

    func pushText(_ text: String) {
        let now = Date()
        let item = HistoryItem(
            text: text,
            createdAt: now,
            lastUsedAt: now,
            sizeBytes: Normalizer.byteCount(text),
            previewFirstLine: Normalizer.firstLine(text))
        queue.async(flags: .barrier) {
            if let idx = self.items.firstIndex(where: { $0.text == text }) {
                var existing = self.items.remove(at: idx)
                existing.lastUsedAt = now
                self.items.insert(existing, at: 0)
            } else {
                self.items.insert(item, at: 0)
                if self.items.count > self.capacity { self.items.removeLast() }
            }
        }
    }

    func get(_ index: Int) -> HistoryItem? {
        queue.sync { (index >= 0 && index < items.count) ? items[index] : nil }
    }
    func touch(_ index: Int) {
        queue.async(flags: .barrier) {
            if index >= 0 && index < self.items.count { self.items[index].lastUsedAt = Date() }
        }
    }
}
