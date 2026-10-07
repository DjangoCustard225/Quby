import SwiftUI

struct ActivityView: View {
    let store: TransferStore
    @Binding var selectedTab: AppTab
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ServerMessage(store: store)
                    if store.activeInstance == nil {
                        ContentUnavailableView {
                            Label("Add a server", systemImage: "server.rack")
                        } description: {
                            Text("Connect to qBittorrent to see transfer activity.")
                        } actions: {
                            Button("Open Settings") { selectedTab = .settings }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        header

                        VStack(alignment: .leading, spacing: 12) {
                            CardSectionTitle("Current speeds")
                            SpeedSummary(store: store)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            CardSectionTitle("Session")
                            NavigationLink {
                                ActiveTransfersView(store: store, selectedTab: $selectedTab)
                            } label: {
                                MetricCard(
                                    "Active transfers",
                                    value: store.hasFreshData ? "\(store.activeTransfers)" : "—",
                                    symbol: "arrow.up.arrow.down", monospacedDigits: true
                                )
                                .overlay(alignment: .trailing) {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .padding(.trailing, 16)
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Active transfers")
                            .accessibilityValue(
                                store.hasFreshData ? "\(store.activeTransfers)" : "Unavailable"
                            )
                            .accessibilityHint("Shows the active downloads and uploads")
                            HStack(spacing: 10) {
                                MetricCard(
                                    "Downloaded",
                                    value: store.lastUpdated == nil
                                        ? "—" : Torrent.bytes(store.info.downloadedBytes),
                                    symbol: "arrow.down.to.line", monospacedDigits: true)
                                MetricCard(
                                    "Uploaded",
                                    value: store.lastUpdated == nil
                                        ? "—" : Torrent.bytes(store.info.uploadedBytes),
                                    symbol: "arrow.up.to.line", monospacedDigits: true)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            CardSectionTitle("Connection")
                            VStack(spacing: 0) {
                                DetailRow("Status", store.status)
                                if !store.version.isEmpty {
                                    Divider().overlay(AppTheme.border)
                                    DetailRow("qBittorrent", store.version)
                                }
                            }
                            .padding(.horizontal, 16)
                            .darkCard(cornerRadius: 18)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .softScrollEdges()
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Activity")
            .minimizeNavigationBarOnScroll()
            .refreshable { await store.refresh() }
        }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 50, height: 50)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(store.activeInstance?.name ?? "qBittorrent")
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.online ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(store.status)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkCard(cornerRadius: 22)
    }
}
