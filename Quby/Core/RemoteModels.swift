import Foundation

struct RemoteTorrent: Decodable, Equatable, Sendable {
    let hash: String
    let name: String
    let size: Int64
    let progress: Double
    let state: String
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let seeders: Int?
    let leechers: Int?
    let savePath: String?
    let category: String?
    var addedOn: Int64? = nil
    var tracker: String? = nil
    var eta: Int64? = nil
    var ratio: Double? = nil
    enum CodingKeys: String, CodingKey {
        case hash, name, size, progress, state, category, tracker, eta, ratio
        case downloadSpeed = "dlspeed"
        case uploadSpeed = "upspeed"
        case seeders = "num_seeds"
        case leechers = "num_leechs"
        case savePath = "save_path"
        case addedOn = "added_on"
    }

}

struct TorrentFile: Decodable, Identifiable, Sendable {
    let index: Int
    let name: String
    let size: Int64
    let progress: Double
    let priority: Int
    var id: Int { index }
}

struct RemoteCategory: Decodable, Sendable {
    let name: String
    let savePath: String
}

struct TorrentTracker: Decodable, Sendable {
    let url: String
    let status: Int?
    let msg: String?
}

struct TransferInfo: Decodable, Equatable, Sendable {
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let downloadedBytes: Int64
    let uploadedBytes: Int64
    var alternativeSpeedLimits: Bool? = nil
    static let zero = TransferInfo(
        downloadSpeed: 0, uploadSpeed: 0, downloadedBytes: 0, uploadedBytes: 0)
    enum CodingKeys: String, CodingKey {
        case downloadSpeed = "dl_info_speed"
        case uploadSpeed = "up_info_speed"
        case downloadedBytes = "dl_info_data"
        case uploadedBytes = "up_info_data"
        case alternativeSpeedLimits = "use_alt_speed_limits"
    }

}

struct TransferSnapshot: Sendable {
    let torrents: [RemoteTorrent]
    let info: TransferInfo
}
