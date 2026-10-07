import Foundation
import Observation

@MainActor @Observable
final class TorrentSearchSession {
    var frame = SearchFrame()
    private(set) var recents: [RecentTorrentSearch] = []
    @ObservationIgnored private var frames: [String: SearchFrame] = [:]
    @ObservationIgnored private var instanceKey = ""
    @ObservationIgnored let processor = TorrentSearchProcessor()
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private var historyKey: String { "recentTorrentContexts." + instanceKey }
    private var context: SearchRoute? {
        frame.path.last {
            if case .torrent = $0 { return false }
            return true
        }
    }
    var query: String {
        get {
            switch context {
            case .browse(let kind): frame.browseQueries[kind] ?? ""
            case .results(let scope): configuration(for: scope).query
            default: frame.root.query
            }
        }
        set {
            switch context {
            case .browse(let kind): frame.browseQueries[kind] = newValue
            case .results(let scope):
                var configuration = configuration(for: scope)
                configuration.query = newValue
                update(configuration, scope: scope)
            default: frame.root.query = newValue
            }
        }
    }
    var prompt: String {
        switch context {
        case .browse(let kind): "Search " + kind.title.lowercased()
        case .results(let scope): "Search in " + scope.value
        default: "Search torrents"
        }
    }
    func activateInstance(_ id: String?) {
        let key = id ?? "none"
        guard instanceKey != key else { return }
        if !instanceKey.isEmpty { frames[instanceKey] = frame }
        instanceKey = key
        frame = frames[key] ?? SearchFrame()
        if let data = defaults.data(forKey: historyKey),
            let saved = try? JSONDecoder().decode([RecentTorrentSearch].self, from: data)
        {
            recents = saved
        } else {
            let old =
                defaults.string(forKey: "recentTorrentSearches." + key)
                ?? (key == "legacy" ? defaults.string(forKey: "recentTorrentSearches") : nil)
            let terms =
                old?.data(using: .utf8).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            recents = terms.map { RecentTorrentSearch(configuration: SearchConfiguration(query: $0)) }
            persistRecents()
        }
    }
    func configuration(for scope: SearchScope?) -> SearchConfiguration {
        scope.map { frame.scoped[$0] ?? SearchConfiguration() } ?? frame.root
    }
    func update(_ configuration: SearchConfiguration, scope: SearchScope?) {
        if let scope { frame.scoped[scope] = configuration } else { frame.root = configuration }
    }
    func openScope(_ scope: SearchScope, configuration: SearchConfiguration? = nil) {
        if let configuration {
            frame.scoped[scope] = configuration
        } else if frame.scoped[scope] == nil {
            frame.scoped[scope] = SearchConfiguration()
        }
        frame.path.append(.results(scope))
        rememberCurrent()
    }
    func openTorrent(_ torrent: Torrent) {
        rememberCurrent()
        frame.snapshots[torrent.id] = torrent
        frame.path.append(.torrent(torrent.id))
    }
    func chooseRecent(_ recent: RecentTorrentSearch) {
        if let scope = recent.scope {
            frame.scoped[scope] = recent.configuration
            frame.path = [.results(scope)]
        } else {
            frame.root = recent.configuration
            frame.path = []
        }
        rememberCurrent()
    }
    func rememberCurrent() {
        let scope: SearchScope?
        switch context {
        case .browse: return
        case .results(let value): scope = value
        default: scope = nil
        }
        var configuration = configuration(for: scope)
        configuration.query = configuration.term
        guard configuration.hasSearch || scope != nil else { return }
        let existing = recents.first { $0.matches(configuration: configuration, scope: scope) }
        recents.removeAll { $0.matches(configuration: configuration, scope: scope) }
        var recent = RecentTorrentSearch(configuration: configuration, scope: scope)
        if let existing { recent.id = existing.id }
        recents.insert(recent, at: 0)
        recents = Array(recents.prefix(5))
        persistRecents()
    }
    func removeRecents(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where recents.indices.contains(index) {
            recents.remove(at: index)
        }
        persistRecents()
    }
    func clearRecents() {
        recents = []
        persistRecents()
    }
    private func persistRecents() {
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: historyKey) }
    }
}
