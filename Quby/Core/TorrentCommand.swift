enum TorrentCommand: Sendable {
    case location(String)
    case category(String)
    case recheck
    case reannounce
    case pause
    case resume
    case delete(deleteFiles: Bool)
}

enum TorrentCommandResult {
    case accepted
    case failed(String)
}
