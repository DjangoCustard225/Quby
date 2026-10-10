import SwiftUI

struct SettingsView: View {
    let store: TransferStore
    @AppStorage("appearance") private var appearance = AppAppearance.dark
    @AppStorage("torrentDensity") private var density = TorrentDensity.comfortable
    @AppStorage("torrentScrollIntensity") private var scrollIntensity = TorrentScrollIntensity.full
    var body: some View {
        NavigationStack {
            Form {
                Section("Configure qBittorrent") {
                    NavigationLink {
                        InstancesView(store: store)
                    } label: {
                        Label("Instances", systemImage: "server.rack")
                    }
                    NavigationLink {
                        SpeedLimitsView(store: store)
                    } label: {
                        Label("Speed limits", systemImage: "speedometer")
                    }
                }
                .listRowBackground(AppTheme.formRowBackground)
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Torrent list density", selection: $density) {
                        ForEach(TorrentDensity.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Scroll effects", selection: $scrollIntensity) {
                        ForEach(TorrentScrollIntensity.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                .listRowBackground(AppTheme.formRowBackground)
            }
            .scrollContentBackground(.hidden)
            .softScrollEdges()
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .minimizeNavigationBarOnScroll()
        }
    }
}
