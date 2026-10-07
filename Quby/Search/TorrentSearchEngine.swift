import Foundation

actor TorrentSearchProcessor {
    func results(_ request: SearchRequest, includingSuggestions: Bool = false)
        -> PreparedSearchResults
    {
        guard !Task.isCancelled else { return PreparedSearchResults(torrents: [], suggestions: []) }
        let matches = TorrentSearchEngine.results(
            request.torrents, configuration: request.configuration, scope: request.scope)
        var suggestions: [SearchSuggestion] = []
        if includingSuggestions && !request.configuration.term.isEmpty {
            for kind in [SearchBrowse.categories, .trackers] {
                let items = TorrentSearchEngine.browse(
                    request.torrents, kind: kind, query: request.configuration.term, sort: .name)
                suggestions += items.prefix(2).map {
                    SearchSuggestion(scope: kind.scope($0.value), count: $0.count)
                }
            }
        }
        return PreparedSearchResults(torrents: matches, suggestions: suggestions)
    }
    func browse(_ request: BrowseRequest) -> [SearchBrowseItem] {
        guard !Task.isCancelled else { return [] }
        return TorrentSearchEngine.browse(
            request.torrents, kind: request.kind, query: request.query, sort: request.sort)
    }
}

enum TorrentSearchEngine {
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
    private static func rank(_ torrent: Torrent, term: String, tokens: [String]) -> Int? {
        guard !term.isEmpty else { return 0 }
        let name = normalized(torrent.name)
        if name == term { return 0 }
        if name.hasPrefix(term) { return 1 }
        if name.contains(term) { return 2 }
        if tokens.allSatisfy({ name.contains($0) }) { return 3 }
        let fields = name + " " + normalized(torrent.category) + " " + normalized(torrent.trackerLabel)
        return tokens.allSatisfy({ fields.contains($0) }) ? 4 : nil
    }
    static func results(
        _ torrents: [Torrent], configuration: SearchConfiguration, scope: SearchScope? = nil
    ) -> [Torrent] {
        let term = normalized(configuration.term)
        let tokens = term.split(whereSeparator: \.isWhitespace).map(String.init)
        let matches = torrents.compactMap { torrent -> (Torrent, Int)? in
            guard scope?.matches(torrent) ?? true,
                configuration.status == nil || torrent.state == configuration.status,
                let rank = rank(torrent, term: term, tokens: tokens)
            else { return nil }
            return (torrent, rank)
        }
        return matches.sorted { left, right in
            if configuration.sort == .relevance && left.1 != right.1 { return left.1 < right.1 }
            return configuration.sort.torrentSort.precedes(left.0, right.0)
        }.map(\.0)
    }
    static func browse(
        _ torrents: [Torrent], kind: SearchBrowse, query: String, sort: SearchBrowseSort
    ) -> [SearchBrowseItem] {
        let tokens = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines)).split(
            whereSeparator: \.isWhitespace)
        var counts: [String: Int] = [:]
        for torrent in torrents {
            let value = kind == .categories ? torrent.category : torrent.trackerLabel
            counts[value, default: 0] += 1
        }
        return counts.compactMap { value, count in
            let name = normalized(value)
            return tokens.allSatisfy({ name.contains($0) })
                ? SearchBrowseItem(value: value, count: count) : nil
        }.sorted {
            if sort == .count && $0.count != $1.count { return $0.count > $1.count }
            return $0.value.localizedStandardCompare($1.value) == .orderedAscending
        }
    }
}
