import Foundation

final class HistoryStore {
    private let ring = RingBuffer(capacity: Constants.capacity)

    func list() -> [HistoryItem] { ring.list() }
    func clear() { ring.clear() }
    func delete(index: Int) { ring.delete(index: index) }
    func moveUp(index: Int) { ring.moveUp(index: index) }
    func moveDown(index: Int) { ring.moveDown(index: index) }
    func moveTop(index: Int) { ring.moveTop(index: index) }
    func pushText(_ text: String) { ring.pushText(text) }
    func get(_ index: Int) -> HistoryItem? { ring.get(index) }
    func touch(_ index: Int) { ring.touch(index) }
}
