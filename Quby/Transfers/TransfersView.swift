import SwiftUI
import UniformTypeIdentifiers

struct TransfersView: View {
    let store: TransferStore
    @Binding var selectedTab: AppTab
    @State private var statusFilter: TransferState?
    @State private var adding = false
    @State private var importing = false
    @State private var importedFile: TorrentFileDraft?
    @State private var selected: Torrent?
    @State private var categoryFilter: String?
    @State private var trackerFilter: String?
    @State private var filterCategories: [String] = []
    @State private var filterTrackers: [String] = []
    var body: some View {
        let items = store.torrents.filter {
            (statusFilter == nil || $0.state == statusFilter)
                && (categoryFilter == nil || $0.category == categoryFilter)
                && (trackerFilter == nil || $0.trackerLabel == trackerFilter)
        }
        NavigationStack {
            TorrentScrollView(onRefresh: {
                await store.refresh()
                refreshFilterOptions()
            }) {
                if store.connectionIssue != nil {
                    ServerMessage(store: store)
                        .padding(.vertical, 4)
                }
                if items.isEmpty {
                    ContentUnavailableView {
                        Label(
                            store.activeInstance == nil
                                ? "Add a server"
                                : !store.online
                                    ? "Server unavailable"
                                    : store.torrents.isEmpty ? "No transfers" : "No matches",
                            systemImage: "tray")
                    } description: {
                        Text(
                            store.activeInstance == nil
                                ? "Configure qBittorrent to see your transfers."
                                : !store.online
                                    ? "Check the connection or try again."
                                    : store.torrents.isEmpty
                                        ? "Add a magnet link or torrent file to get started."
                                        : "Try clearing the current filters.")
                    } actions: {
                        if store.activeInstance == nil {
                            Button("Open Settings") { selectedTab = .settings }
                        } else if !store.online {
                            Button("Retry") {
                                Task { await retryServerConnection(store, selectedTab: $selectedTab) }
                            }
                        } else if !store.torrents.isEmpty {
                            Button("Clear filters") {
                                statusFilter = nil
                                categoryFilter = nil
                                trackerFilter = nil
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    TorrentRows(store: store, torrents: items) { selected = $0 }
                }
            }
            .navigationTitle("Quby")
            .torrentSelection(store: store, visibleTorrents: items)
            .navigationDestination(
                isPresented: Binding(
                    get: { selected != nil },
                    set: { if !$0 { selected = nil } }
                )
            ) {
                if let selected { TorrentDetail(store: store, torrent: selected) }
            }
            .onAppear(perform: refreshFilterOptions)
            .onChange(of: store.torrents.isEmpty) { _, isEmpty in
                if !isEmpty { refreshFilterOptions() }
            }
            .onChange(of: store.activeInstanceID) { _, _ in
                statusFilter = nil
                categoryFilter = nil
                trackerFilter = nil
                selected = nil
                refreshFilterOptions()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        TransferFilterMenu(
                            sortOrder: store.sortOrder,
                            statusValue: statusFilter, categoryValue: categoryFilter,
                            trackerValue: trackerFilter,
                            statusFilter: $statusFilter, categoryFilter: $categoryFilter,
                            trackerFilter: $trackerFilter,
                            categories: filterCategories, trackers: filterTrackers,
                            onSort: { value in Task { await store.changeSort(value) } }
                        )
                        .equatable()
                        .disabled(!store.connected)
                        Divider().frame(height: 18)
                        AddTorrentMenu(
                            canControl: store.canControl,
                            onMagnet: { adding = true },
                            onFile: { importing = true }
                        )
                        .equatable()
                    }
                }
            }
            .sheet(isPresented: $adding) { AddTorrentView(store: store) }
            .sheet(item: $importedFile) { file in AddTorrentView(store: store, source: .file(file)) }
            .fileImporter(
                isPresented: $importing, allowedContentTypes: [UTType(importedAs: "org.bittorrent.torrent")]
            ) { result in
                importTorrent(result)
            }
        }
    }
    private func refreshFilterOptions() {
        let categories = store.categories
        let trackers = store.trackers
        if filterCategories != categories { filterCategories = categories }
        if filterTrackers != trackers { filterTrackers = trackers }
    }
    private func importTorrent(_ result: Result<URL, Error>) {
        do {
            importedFile = try TorrentFileDraft(importing: result.get())
        } catch {
            store.error = error.localizedDescription
        }
    }
}
