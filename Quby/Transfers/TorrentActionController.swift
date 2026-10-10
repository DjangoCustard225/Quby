import Foundation
import Observation

enum TorrentAction: String, CaseIterable, Identifiable {
    case location = "Set location"
    case category = "Set category"
    case recheck = "Force recheck"
    case reannounce = "Force reannounce"
    case pause = "Pause"
    case resume = "Resume"
    case delete = "Delete"
    case purge = "Purge"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .location: "folder"
        case .category: "tag"
        case .recheck: "checkmark.arrow.trianglehead.counterclockwise"
        case .reannounce: "antenna.radiowaves.left.and.right"
        case .pause: "pause"
        case .resume: "play"
        case .delete: "minus.circle"
        case .purge: "trash"
        }
    }
}

struct TorrentActionRequest: Identifiable {
    let id = UUID()
    let action: TorrentAction
    let torrents: [Torrent]
    let instanceID: String?
    var ids: Set<String> { Set(torrents.map(\.id)) }
}

@MainActor @Observable
final class TorrentActionController {
    var editor: TorrentActionRequest?
    var removal: TorrentActionRequest?
    private(set) var running = false
    var feedback: String?
    var failure: String?

    func choose(_ action: TorrentAction, torrents: [Torrent], store: TransferStore) {
        guard store.canControl, !running, !torrents.isEmpty else { return }
        let request = TorrentActionRequest(
            action: action, torrents: torrents, instanceID: store.activeInstanceID)
        switch action {
        case .location, .category: editor = request
        case .delete, .purge: removal = request
        case .pause, .resume:
            Task { await submit(action == .pause ? .pause : .resume, request: request, store: store) }
        case .recheck, .reannounce:
            Task { await submit(action == .recheck ? .recheck : .reannounce, request: request, store: store) }
        }
    }

    @discardableResult
    func submit(_ command: TorrentCommand, request: TorrentActionRequest, store: TransferStore) async -> Bool
    {
        guard !running else { return false }
        running = true
        defer { running = false }
        let result = await store.perform(command, ids: request.ids, instanceID: request.instanceID)
        guard store.activeInstanceID == request.instanceID else { return false }
        switch result {
        case .accepted:
            feedback =
                switch command {
                case .location: "Location change requested"
                case .category: "Category change requested"
                case .recheck: "Recheck requested"
                case .reannounce: "Reannounce requested"
                case .pause: "Pause requested"
                case .resume: "Resume requested"
                case .delete: "Removal requested"
                }
            return true
        case .failed(let message):
            failure = message
            return false
        }
    }
}
