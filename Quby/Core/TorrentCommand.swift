enum TorrentCommand: Sendable {
    case location(String)
    case category(String)
    case recheck
    case reannounce
}

enum TorrentCommandResult {
    case accepted
    case failed(String)
}
