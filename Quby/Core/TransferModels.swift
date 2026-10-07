import Foundation

enum TransferState: String, CaseIterable, Codable, Sendable {
    case downloading = "Downloading"
    case seeding = "Seeding"
    case paused = "Paused"
    case queued = "Queued"
    case checking = "Checking"
    case stalled = "Stalled"
    case error = "Error"
    case unknown = "Unknown"
    var symbol: String {
        switch self {
        case .seeding: return "arrow.up"
        case .paused: return "pause.fill"
        case .error: return "exclamationmark.triangle"
        case .checking: return "checkmark.circle"
        case .queued: return "clock"
        default: return "arrow.down"
        }
    }
    init(remote: String) {
        if remote.hasPrefix("paused") || remote.hasPrefix("stopped") {
            self = .paused
        } else if remote.hasPrefix("queued") {
            self = .queued
        } else if remote.hasPrefix("checking") {
            self = .checking
        } else if ["error", "missingFiles"].contains(remote) {
            self = .error
        } else if ["uploading", "stalledUP", "forcedUP"].contains(remote) {
            self = .seeding
        } else if remote == "stalledDL" {
            self = .stalled
        } else if ["downloading", "forcedDL", "metaDL", "forcedMetaDL", "allocating", "moving"]
            .contains(remote)
        {
            self = .downloading
        } else {
            self = .unknown
        }
    }
}

enum TorrentSort: String, CaseIterable, Identifiable, Sendable {
    case dateAdded = "Date added"
    case name = "Name"
    case size = "Size"
    var id: String { rawValue }

    func precedes(_ left: Torrent, _ right: Torrent) -> Bool {
        switch self {
        case .dateAdded:
            let lhs = left.dateAdded ?? .distantPast
            let rhs = right.dateAdded ?? .distantPast
            if lhs != rhs { return lhs > rhs }
        case .size:
            if left.sizeBytes != right.sizeBytes { return left.sizeBytes > right.sizeBytes }
        case .name: break
        }
        let comparison = left.name.localizedStandardCompare(right.name)
        return comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
    }
}

struct Torrent: Identifiable, Equatable, Sendable {
    static let uncategorized = "Uncategorized"
    let id: String
    let name: String
    let category: String
    let categoryName: String
    let trackerLabel: String
    let trackerURL: String
    let size: String
    let sizeBytes: Int64
    let dateAdded: Date?
    let progress: Double
    let state: TransferState
    let isActive: Bool
    let speed: String
    let peers: Int
    let savePath: String
    let eta: String
    let ratio: String
    init(_ remote: RemoteTorrent) {
        id = remote.hash
        name = remote.name
        state = TransferState(remote: remote.state)
        isActive = remote.downloadSpeed > 0 || remote.uploadSpeed > 0
        categoryName = remote.category ?? ""
        category = categoryName.isEmpty ? Self.uncategorized : categoryName
        let rawTracker = remote.tracker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        trackerURL = rawTracker
        if let host = URL(string: rawTracker)?.host, !host.isEmpty {
            trackerLabel =
                host.lowercased().hasPrefix("www.")
                ? String(host.dropFirst(4)).lowercased() : host.lowercased()
        } else {
            trackerLabel = rawTracker.isEmpty ? "Unknown tracker" : rawTracker.lowercased()
        }
        sizeBytes = max(0, remote.size)
        size = Self.bytes(sizeBytes)
        dateAdded = remote.addedOn.flatMap {
            $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil
        }
        progress = remote.progress.isFinite ? min(1, max(0, remote.progress)) : 0
        speed = Self.bytes(state == .seeding ? remote.uploadSpeed : remote.downloadSpeed) + "/s"
        peers = (remote.seeders ?? 0) + (remote.leechers ?? 0)
        savePath = remote.savePath ?? "—"
        if let seconds = remote.eta, seconds > 0 && seconds < 8_640_000 {
            if seconds >= 86_400 {
                eta = "\(seconds / 86_400)d \((seconds % 86_400) / 3_600)h"
            } else if seconds >= 3_600 {
                eta = "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
            } else {
                eta = "\(max(1, seconds / 60))m"
            }
        } else {
            eta = "—"
        }
        if let value = remote.ratio, value.isFinite, value >= 0 {
            ratio = value.formatted(.number.precision(.fractionLength(2)))
        } else {
            ratio = "—"
        }
    }
    static func bytes(_ amount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: amount, countStyle: .decimal)
    }
}
