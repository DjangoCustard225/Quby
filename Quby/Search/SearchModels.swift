import Foundation

enum SearchScope: Hashable, Codable, Identifiable, Sendable {
    case category(String)
    case tracker(String)
    var id: String { kind + ":" + value }
    var kind: String {
        switch self {
        case .category: "Category"
        case .tracker: "Tracker"
        }
    }
    var value: String {
        switch self {
        case .category(let value), .tracker(let value): value
        }
    }
    var symbol: String {
        switch self {
        case .category: "folder"
        case .tracker: "antenna.radiowaves.left.and.right"
        }
    }
    func matches(_ torrent: Torrent) -> Bool {
        switch self {
        case .category(let value): torrent.category == value
        case .tracker(let value): torrent.trackerLabel == value
        }
    }
}

enum SearchBrowse: String, Hashable, Codable, Sendable {
    case categories, trackers
    var title: String { self == .categories ? "Categories" : "Trackers" }
    var symbol: String { self == .categories ? "folder" : "antenna.radiowaves.left.and.right" }
    func scope(_ value: String) -> SearchScope {
        self == .categories ? .category(value) : .tracker(value)
    }
}

enum SearchResultSort: String, CaseIterable, Codable, Identifiable, Sendable {
    case relevance = "Relevance"
    case dateAdded = "Date added"
    case name = "Name"
    case size = "Size"
    var id: String { rawValue }
    var torrentSort: TorrentSort {
        switch self {
        case .relevance, .name: .name
        case .dateAdded: .dateAdded
        case .size: .size
        }
    }
}

enum SearchBrowseSort: String, CaseIterable, Identifiable, Sendable {
    case name = "Name"
    case count = "Torrent count"
    var id: String { rawValue }
}

struct SearchConfiguration: Equatable, Codable, Sendable {
    var query = ""
    var status: TransferState?
    var sort: SearchResultSort = .relevance
    var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasSearch: Bool { !term.isEmpty || status != nil }
}

struct RecentTorrentSearch: Identifiable, Codable, Equatable {
    var id = UUID()
    var configuration: SearchConfiguration
    var scope: SearchScope?
    var title: String {
        configuration.term.isEmpty
            ? scope?.value ?? configuration.status?.rawValue ?? "All torrents" : configuration.term
    }
    var subtitle: String {
        var parts: [String] = []
        if let scope { parts.append(scope.kind + ": " + scope.value) }
        if let status = configuration.status { parts.append(status.rawValue) }
        if configuration.sort != .relevance { parts.append(configuration.sort.rawValue) }
        return parts.joined(separator: " · ")
    }
    func matches(configuration other: SearchConfiguration, scope otherScope: SearchScope?) -> Bool {
        scope == otherScope && configuration.status == other.status && configuration.sort == other.sort
            && configuration.term.localizedCaseInsensitiveCompare(other.term) == .orderedSame
    }
}

struct SearchBrowseItem: Identifiable, Sendable {
    let value: String
    let count: Int
    var id: String { value }
}

struct SearchRequest: Equatable, Sendable {
    let torrents: [Torrent]
    let configuration: SearchConfiguration
    var scope: SearchScope?
    var instanceID: String?
}

struct BrowseRequest: Equatable, Sendable {
    let torrents: [Torrent]
    let kind: SearchBrowse
    let query: String
    let sort: SearchBrowseSort
    var instanceID: String?
}

struct SearchSuggestion: Identifiable, Sendable {
    let scope: SearchScope
    let count: Int
    var id: String { scope.id }
}

struct PreparedSearchResults: Sendable {
    let torrents: [Torrent]
    let suggestions: [SearchSuggestion]
}

enum SearchRoute: Hashable {
    case browse(SearchBrowse)
    case results(SearchScope)
    case torrent(String)
}

struct SearchFrame {
    var root = SearchConfiguration()
    var path: [SearchRoute] = []
    var scoped: [SearchScope: SearchConfiguration] = [:]
    var browseQueries: [SearchBrowse: String] = [:]
    var browseSorts: [SearchBrowse: SearchBrowseSort] = [:]
    var snapshots: [String: Torrent] = [:]
}
