import Foundation

struct TorrentFileDraft: Identifiable {
    let id = UUID()
    let filename: String
    let data: Data

    init(importing url: URL) throws {
        guard url.pathExtension.lowercased() == "torrent" else { throw TorrentImportError.invalidType }
        #if os(iOS)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw TorrentImportError.emptyFile }
        filename = url.lastPathComponent
        self.data = data
    }
}

enum TorrentImportError: LocalizedError {
    case invalidType, emptyFile

    var errorDescription: String? {
        switch self {
        case .invalidType: "Select a .torrent file."
        case .emptyFile: "The selected torrent file is empty."
        }
    }
}

enum TorrentSource: Identifiable {
    case magnet(String)
    case file(TorrentFileDraft)

    var id: String {
        switch self {
        case .magnet(let link): "magnet:" + link
        case .file(let file): file.id.uuidString
        }
    }

    static func isValidMagnet(_ link: String) -> Bool {
        guard
            let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
            components.scheme?.lowercased() == "magnet"
        else { return false }
        return components.queryItems?.contains {
            $0.name == "xt"
                && ($0.value?.hasPrefix("urn:btih:") == true || $0.value?.hasPrefix("urn:btmh:") == true)
        } == true
    }
}
