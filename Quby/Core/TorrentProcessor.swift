import Foundation

struct PreparedTorrents: Sendable {
    let items: [Torrent]
    let activeTransfers: Int
    let categories: [String]
    let trackers: [String]
    let rebuiltCount: Int
    let didSort: Bool
}

// All formatting, natural sorting and cache comparisons run off the UI actor.
actor TorrentProcessor {
    private var cache: [String: (raw: RemoteTorrent, item: Torrent)] = [:]
    private var order: [String] = []
    private var lastSort: TorrentSort?
    private var categories: [String] = []
    private var trackers: [String] = []
    func prepare(_ records: [RemoteTorrent], sort: TorrentSort = .name) -> PreparedTorrents {
        var next: [String: (raw: RemoteTorrent, item: Torrent)] = [:]
        next.reserveCapacity(records.count)
        var needsSort = records.count != cache.count || lastSort != sort
        var needsOptions = records.count != cache.count
        var rebuilt = 0
        var activeTransfers = 0
        for raw in records {
            let old = cache[raw.hash]
            if old == nil {
                needsSort = true
                needsOptions = true
            }
            if old?.raw.category != raw.category || old?.raw.tracker != raw.tracker {
                needsOptions = true
            }
            switch sort {
            case .name: break
            case .size: if old?.raw.size != raw.size { needsSort = true }
            case .dateAdded: if old?.raw.addedOn != raw.addedOn { needsSort = true }
            }
            if old?.raw.name != raw.name { needsSort = true }
            let item: Torrent
            if old?.raw == raw, let existing = old?.item {
                item = existing
            } else {
                item = Torrent(raw)
                rebuilt += 1
            }
            next[raw.hash] = (raw, item)
            if item.isActive { activeTransfers += 1 }
        }
        if needsSort {
            order = next.values.map(\.item).sorted(by: sort.precedes).map(\.id)
            lastSort = sort
        }
        if needsOptions {
            categories = Array(Set(next.values.map { $0.item.category })).sorted(by: Self.localizedOrder)
            trackers = Array(Set(next.values.map { $0.item.trackerLabel })).sorted(
                by: Self.localizedOrder)
        }
        cache = next
        return PreparedTorrents(
            items: order.compactMap { next[$0]?.item }, activeTransfers: activeTransfers,
            categories: categories, trackers: trackers, rebuiltCount: rebuilt, didSort: needsSort)
    }

    private static func localizedOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
