import Foundation

// Keep response IDs and partial records together, and serialize sync requests.
// Decoding and merging happen off the UI actor, including for large libraries.
actor TorrentSync {
    private var rid = 0
    private var records: [String: [String: Any]] = [:]
    private var items: [String: RemoteTorrent] = [:]
    private var serverState: [String: Any] = [:]
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func snapshot(fetch: (Int) async throws -> Data) async throws -> TransferSnapshot {
        if busy { await withCheckedContinuation { waiters.append($0) } }
        busy = true
        defer {
            if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        do {
            let data = try await fetch(rid)
            guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let nextID = response["rid"] as? Int,
                rid != 0 || response["full_update"] as? Bool == true
            else { throw QBError.unexpected }
            let full = response["full_update"] as? Bool == true
            var nextRecords = full ? [:] : records
            var nextItems = full ? [:] : items
            var nextState = full ? [:] : serverState
            var changed: [[String: Any]] = []
            if let changes = response["torrents"] as? [String: [String: Any]] {
                for (hash, patch) in changes {
                    var record = nextRecords[hash] ?? [:]
                    record.merge(patch) { _, new in new }
                    record["hash"] = hash
                    nextRecords[hash] = record
                    changed.append(record)
                }
            }
            for hash in response["torrents_removed"] as? [String] ?? [] {
                nextRecords.removeValue(forKey: hash)
                nextItems.removeValue(forKey: hash)
            }
            if let patch = response["server_state"] as? [String: Any] {
                nextState.merge(patch) { _, new in new }
            }
            let decoder = JSONDecoder()
            let updates = try decoder.decode(
                [RemoteTorrent].self,
                from: JSONSerialization.data(withJSONObject: changed))
            for torrent in updates where nextRecords[torrent.hash] != nil {
                nextItems[torrent.hash] = torrent
            }
            let info = try decoder.decode(
                TransferInfo.self, from: JSONSerialization.data(withJSONObject: nextState))
            records = nextRecords
            items = nextItems
            serverState = nextState
            rid = nextID
            return TransferSnapshot(torrents: Array(nextItems.values), info: info)
        } catch {
            // A failed or malformed response must never advance the cursor.
            // Ask for a full snapshot next time in case the server consumed it.
            rid = 0
            if error is QBError || error is URLError || error is CancellationError { throw error }
            throw QBError.unexpected
        }
    }
}
