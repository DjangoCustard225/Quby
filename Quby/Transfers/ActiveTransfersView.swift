import SwiftUI

struct ActiveTransfersView: View {
    let store: TransferStore
    @Binding var selectedTab: AppTab
    @State private var selected: Torrent?

    var body: some View {
        let items = store.activeTorrents
        TorrentScrollView(onRefresh: { await store.refresh() }) {
            if let instance = store.activeInstance {
                HStack {
                    Label(instance.name, systemImage: "server.rack")
                    Spacer(minLength: 8)
                    Text(items.count, format: .number).monospacedDigit()
                        .accessibilityLabel("\(items.count) torrents")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            ServerMessage(store: store)
            if store.connecting {
                ProgressView("Connecting…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label(
                        store.hasFreshData ? "No active transfers" : "Server unavailable",
                        systemImage: "arrow.up.arrow.down")
                } description: {
                    Text(
                        store.hasFreshData
                            ? "Torrents appear here while downloading or uploading data."
                            : "Reconnect to see active downloads and uploads.")
                } actions: {
                    if !store.hasFreshData {
                        Button("Retry") {
                            Task { await retryServerConnection(store, selectedTab: $selectedTab) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                TorrentRows(store: store, torrents: items) { selected = $0 }
            }
        }
        .navigationTitle("Active transfers")
        .torrentSelection(store: store, visibleTorrents: items)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(
            isPresented: Binding(
                get: { selected != nil },
                set: { if !$0 { selected = nil } }
            )
        ) {
            if let selected { TorrentDetail(store: store, torrent: selected) }
        }
        .onChange(of: store.activeInstanceID) { _, _ in selected = nil }
        .task { await store.refresh() }
    }
}
