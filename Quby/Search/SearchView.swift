import SwiftUI

struct TorrentSearchView: View {
    let store: TransferStore
    @Binding var selectedTab: AppTab
    @Bindable var session: TorrentSearchSession
    @State private var matches: [Torrent] = []
    @State private var matchingScopes: [SearchSuggestion] = []
    @State private var preparedConfiguration: SearchConfiguration?
    @State private var preparedInstanceID: String?
    private var configuration: SearchConfiguration { session.frame.root }
    var body: some View {
        NavigationStack(path: $session.frame.path) {
            content
                .torrentSelection(store: store, visibleTorrents: configuration.hasSearch ? matches : [])
                .navigationTitle("Search")
                .navigationDestination(for: SearchRoute.self) { route in
                    switch route {
                    case .browse(let kind):
                        SearchBrowsePage(
                            store: store, session: session, kind: kind, selectedTab: $selectedTab)
                    case .results(let scope):
                        ScopedSearchPage(
                            store: store, session: session, scope: scope, selectedTab: $selectedTab)
                    case .torrent(let id):
                        if let torrent = store.torrents.first(where: { $0.id == id })
                            ?? session.frame.snapshots[id]
                        {
                            TorrentDetail(store: store, torrent: torrent)
                        }
                    }
                }
                .refreshable { await retryServerConnection(store, selectedTab: $selectedTab) }
                .task(
                    id: SearchRequest(
                        torrents: store.torrents, configuration: configuration,
                        instanceID: store.activeInstanceID)
                ) {
                    let configuration = configuration
                    guard configuration.hasSearch else { return }
                    let request = SearchRequest(
                        torrents: store.torrents, configuration: configuration,
                        instanceID: store.activeInstanceID)
                    if preparedConfiguration?.query != configuration.query {
                        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    }
                    let prepared = await session.processor.results(request, includingSuggestions: true)
                    guard !Task.isCancelled else { return }
                    matches = prepared.torrents
                    matchingScopes = prepared.suggestions
                    preparedConfiguration = configuration
                    preparedInstanceID = request.instanceID
                }
        }
        .searchable(
            text: Binding(get: { session.query }, set: { session.query = $0 }),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(session.prompt)
        )
        .onSubmit(of: .search) { session.rememberCurrent() }
    }
    @ViewBuilder private var content: some View {
        if configuration.hasSearch {
            TorrentScrollView { rows }
                .scrollDismissesKeyboard(.interactively)
        } else {
            List { rows }.searchListStyle()
                .contentMargins(.bottom, 68, for: .scrollContent)
        }
    }
    @ViewBuilder private var rows: some View {
        SearchInstanceRow(store: store)
        SearchConnectionNotice(store: store, selectedTab: $selectedTab)
        if store.activeInstance == nil {
            ContentUnavailableView {
                Label("Add a server", systemImage: "server.rack")
            } description: {
                Text("Connect to qBittorrent to search your torrents.")
            } actions: {
                Button("Open Settings") { selectedTab = .settings }
                    .buttonStyle(.borderedProminent)
            }
            .searchEmptyRow()
        } else if store.lastUpdated == nil && !store.online {
            ContentUnavailableView(
                "Connect to search", systemImage: "magnifyingglass",
                description: Text("Your torrents will appear after the first successful connection.")
            )
            .searchEmptyRow()
        } else if !configuration.hasSearch {
            home
        } else {
            suggestions
            if preparedConfiguration == configuration && preparedInstanceID == store.activeInstanceID {
                SearchResultRows(
                    store: store, session: session, matches: matches,
                    configuration: configuration, scope: nil)
            } else {
                SearchLoadingRow()
            }
        }
    }
    private var home: some View {
        Group {
            if !session.recents.isEmpty {
                Section {
                    ForEach(session.recents) { recent in
                        Button {
                            session.chooseRecent(recent)
                            dismissSearchKeyboard()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recent.title).foregroundStyle(.primary)
                                    if !recent.subtitle.isEmpty {
                                        Text(recent.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { session.removeRecents(at: $0) }
                } header: {
                    HStack {
                        Text("Recent")
                        Spacer()
                        Button("Clear") { session.clearRecents() }
                            .accessibilityLabel("Clear recent searches")
                    }.textCase(nil)
                }
                .listRowBackground(Color.clear)
            }
            Section("Browse") {
                ForEach([SearchBrowse.categories, .trackers], id: \.self) { kind in
                    NavigationLink(value: SearchRoute.browse(kind)) {
                        HStack(spacing: 12) {
                            Label(kind.title, systemImage: kind.symbol)
                            Spacer()
                            Text(
                                kind == .categories ? store.categories.count : store.trackers.count,
                                format: .number
                            )
                            .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
    }
    private var suggestions: some View {
        return Group {
            if preparedConfiguration == configuration && preparedInstanceID == store.activeInstanceID
                && !matchingScopes.isEmpty
            {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Matching filters").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    ForEach(matchingScopes) { suggestion in
                        Button {
                            session.openScope(suggestion.scope, configuration: configuration)
                            dismissSearchKeyboard()
                        } label: {
                            HStack(spacing: 12) {
                                Label(suggestion.scope.value, systemImage: suggestion.scope.symbol)
                                    .foregroundStyle(
                                        .primary)
                                Spacer(minLength: 8)
                                Text(suggestion.count, format: .number).foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        .tertiary)
                            }
                        }.buttonStyle(.plain)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}
