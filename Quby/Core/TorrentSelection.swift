import Foundation

struct TorrentSelection: Equatable {
    private(set) var ids: Set<String> = []
    private(set) var isSelecting = false

    mutating func begin(_ id: String) {
        isSelecting = true
        ids.insert(id)
    }

    mutating func toggle(_ id: String) {
        isSelecting = true
        if !ids.insert(id).inserted { ids.remove(id) }
    }

    mutating func selectAll(_ visibleIDs: Set<String>) {
        isSelecting = true
        ids.formUnion(visibleIDs)
    }

    mutating func retainAvailable(_ availableIDs: Set<String>) {
        ids.formIntersection(availableIDs)
    }

    mutating func deselectAll() {
        ids.removeAll()
    }

    mutating func clear() {
        ids.removeAll()
        isSelecting = false
    }
}
