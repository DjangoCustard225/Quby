import SwiftUI

struct SearchBrowsePage: View {
    let store: TransferStore
    @Bindable var session: TorrentSearchSession
    let kind: SearchBrowse
    @Binding var selectedTab: AppTab
    @State private var items: [SearchBrowseItem] = []
    @State private var preparedQuery: String?
    @State private var preparedSort: SearchBrowseSort?
    @State private var preparedInstanceID: String?
    private var query: String { session.frame.browseQueries[kind] ?? "" }
    private var sort: SearchBrowseSort { session.frame.browseSorts[kind] ?? .name }
    var body: some View {
        List {
            SearchInstanceRow(store: store)
            SearchConnectionNotice(store: store, selectedTab: $selectedTab)
            if preparedQuery != query || preparedSort != sort
                || preparedInstanceID != store.activeInstanceID
            {
                SearchLoadingRow()
            } else if items.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No " + kind.title.lowercased() : "No matches", systemImage: kind.symbol,
                    description: Text(
                        query.isEmpty
                            ? "These appear when torrents are assigned to them."
                            : "Try another name or clear the search.")
                )
                .searchEmptyRow()
            } else {
                Section {
                    ForEach(items) { item in
                        Button {
                            session.openScope(kind.scope(item.value))
                            dismissSearchKeyboard()
                        } label: {
                            HStack(spacing: 12) {
                                Text(item.value).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                Text(item.count, format: .number).foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        .tertiary)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.value), \(item.count) torrents")
                    }
                } header: {
                    Text("\(items.count) " + kind.title.lowercased())
                }
                .listRowBackground(Color.clear)
            }
        }
        .searchListStyle()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BrowseSortMenu(sort: sort) { session.frame.browseSorts[kind] = $0 }.equatable()
            }
        }
        .refreshable { await retryServerConnection(store, selectedTab: $selectedTab) }
        .task(
            id: BrowseRequest(
                torrents: store.torrents, kind: kind, query: query, sort: sort,
                instanceID: store.activeInstanceID)
        ) {
            let request = BrowseRequest(
                torrents: store.torrents, kind: kind, query: query, sort: sort,
                instanceID: store.activeInstanceID)
            let prepared = await session.processor.browse(request)
            guard !Task.isCancelled else { return }
            items = prepared
            preparedQuery = request.query
            preparedSort = request.sort
            preparedInstanceID = request.instanceID
        }
    }
}

struct ScopedSearchPage: View {
    let store: TransferStore
    @Bindable var session: TorrentSearchSession
    let scope: SearchScope
    @Binding var selectedTab: AppTab
    @State private var matches: [Torrent] = []
    @State private var preparedConfiguration: SearchConfiguration?
    @State private var preparedInstanceID: String?
    private var configuration: SearchConfiguration { session.configuration(for: scope) }
    var body: some View {
        TorrentScrollView {
            SearchInstanceRow(store: store, scope: scope)
            SearchConnectionNotice(store: store, selectedTab: $selectedTab)
            if preparedConfiguration == configuration && preparedInstanceID == store.activeInstanceID {
                SearchResultRows(
                    store: store, session: session, matches: matches,
                    configuration: configuration, scope: scope)
            } else {
                SearchLoadingRow()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(scope.value)
        .torrentSelection(store: store, visibleTorrents: matches)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await retryServerConnection(store, selectedTab: $selectedTab) }
        .task(
            id: SearchRequest(
                torrents: store.torrents, configuration: configuration, scope: scope,
                instanceID: store.activeInstanceID)
        ) {
            let request = SearchRequest(
                torrents: store.torrents, configuration: configuration, scope: scope,
                instanceID: store.activeInstanceID)
            if preparedConfiguration?.query != request.configuration.query
                && !request.configuration.term.isEmpty
            {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            let prepared = await session.processor.results(request)
            guard !Task.isCancelled else { return }
            matches = prepared.torrents
            preparedConfiguration = request.configuration
            preparedInstanceID = request.instanceID
        }
    }
}
