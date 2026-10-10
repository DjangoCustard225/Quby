import SwiftUI

@main
struct QubyApp: App {
    var body: some Scene {
        WindowGroup { QubyRoot().tint(.blue) }
    }
}

enum AppTab: Hashable { case transfers, activity, settings, search }

struct QubyRoot: View {
    @AppStorage("appearance") private var appearance = AppAppearance.dark
    @State private var store = TransferStore()
    @State private var selectedTab: AppTab = .transfers
    @State private var searchSession = TorrentSearchSession()
    @State private var incomingTorrent: TorrentSource?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Transfers", systemImage: "arrow.up.arrow.down", value: .transfers) {
                TransfersView(store: store, selectedTab: $selectedTab)
            }
            Tab("Activity", systemImage: "chart.xyaxis.line", value: .activity) {
                ActivityView(store: store, selectedTab: $selectedTab)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) { SettingsView(store: store) }
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                TorrentSearchView(
                    store: store, selectedTab: $selectedTab,
                    session: searchSession)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: store.activeInstanceID, initial: true) { _, id in
            searchSession.activateInstance(id)
        }
        .preferredColorScheme(appearance.colorScheme)
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .onOpenURL { url in
            if url.scheme?.lowercased() == "magnet" {
                selectedTab = .transfers
                incomingTorrent = .magnet(url.absoluteString)
            } else if url.isFileURL && url.pathExtension.lowercased() == "torrent" {
                Task {
                    do {
                        let file = try TorrentFileDraft(importing: url)
                        selectedTab = .transfers
                        incomingTorrent = .file(file)
                    } catch { store.error = error.localizedDescription }
                }
            }
        }
        .sheet(item: $incomingTorrent) { source in AddTorrentView(store: store, source: source) }
        .alert(
            "Request Failed",
            isPresented: Binding(
                get: { store.error != nil },
                set: { if !$0 { store.error = nil } }
            )
        ) {
            Button("OK") { store.error = nil }
        } message: {
            Text(store.error ?? "Please try again.")
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.restore()
            while !Task.isCancelled {
                await store.refresh()
                let tabInterval: Double =
                    switch selectedTab {
                    case .transfers: 2
                    case .activity: 5
                    case .search, .settings: 12
                    }
                let seconds = store.online ? tabInterval : 15.0
                do { try await Task.sleep(for: .seconds(seconds)) } catch { break }
            }
        }
    }
}

#if !SWIFT_PACKAGE
    #Preview { QubyRoot() }
#endif
