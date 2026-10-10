import Foundation

struct TorrentAddDefaults: Codable, Equatable {
    var category = ""
    var automaticManagement = true
    var location = ""
    var startPaused = false

    static func load(instanceID: String?) -> Self {
        guard let instanceID, let data = UserDefaults.standard.data(forKey: "addDefaults." + instanceID),
            let value = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self() }
        return value
    }

    func save(instanceID: String?) {
        guard let instanceID, let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "addDefaults." + instanceID)
    }
}

struct SpeedLimits: Codable, Equatable, Sendable {
    var download: Int64
    var upload: Int64
    var alternativeDownload: Int64
    var alternativeUpload: Int64

    enum CodingKeys: String, CodingKey {
        case download = "dl_limit"
        case upload = "up_limit"
        case alternativeDownload = "alt_dl_limit"
        case alternativeUpload = "alt_up_limit"
    }
}

struct SpeedLimitDraft {
    var download: String
    var upload: String
    var alternativeDownload: String
    var alternativeUpload: String

    init(_ limits: SpeedLimits) {
        download = Self.display(limits.download)
        upload = Self.display(limits.upload)
        alternativeDownload = Self.display(limits.alternativeDownload)
        alternativeUpload = Self.display(limits.alternativeUpload)
    }

    private static func display(_ bytes: Int64) -> String {
        bytes <= 0 ? "0" : String((bytes + 1023) / 1024)
    }

    var limits: SpeedLimits? {
        func bytes(_ text: String) -> Int64? {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isASCII && $0.isNumber }),
                let value = Int64(cleaned), (0...2_097_151).contains(value)
            else { return nil }
            return value * 1024
        }
        guard let download = bytes(download), let upload = bytes(upload),
            let alternativeDownload = bytes(alternativeDownload),
            let alternativeUpload = bytes(alternativeUpload)
        else { return nil }
        return SpeedLimits(
            download: download, upload: upload, alternativeDownload: alternativeDownload,
            alternativeUpload: alternativeUpload)
    }
}
