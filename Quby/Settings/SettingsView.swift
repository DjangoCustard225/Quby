import SwiftUI

struct SettingsView: View {
    let store: TransferStore
    var body: some View {
        NavigationStack {
            Form {
                Section("Configure qBittorrent") {
                    NavigationLink {
                        InstancesView(store: store)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .foregroundStyle(.blue)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Instances")
                                    .font(.headline)
                                Text(
                                    store.activeInstance.map { "Active: \($0.name)" }
                                        ?? "Add your first server"
                                )
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                .listRowBackground(AppTheme.formRowBackground)
                Section("Privacy & Security") {
                    Label("Saved passwords and API keys stay in this device’s Keychain.", systemImage: "key")
                    Label("Instance details and recent searches stay on this device.", systemImage: "iphone")
                    Label("Quby contacts only the servers you configure.", systemImage: "network")
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
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
