import SwiftUI

struct TorrentDetail: View {
    let store: TransferStore
    let torrent: Torrent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var removal: RemovalAction?
    @State private var files: [TorrentFile] = []
    @State private var trackers: [TorrentTracker] = []
    @State private var loadingDetails = false
    @State private var changingFile: Int?
    private enum RemovalAction: String {
        case delete = "Delete"
        case purge = "Purge"
    }
    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }
    private var current: Torrent { store.torrents.first(where: { $0.id == torrent.id }) ?? torrent }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ServerMessage(store: store)
                header

                VStack(alignment: .leading, spacing: 12) {
                    CardSectionTitle("At a glance")
                    VStack(spacing: 10) {
                        HStack {
                            Text("Progress")
                                .foregroundStyle(AppTheme.secondaryText)
                            Spacer()
                            Text("\(Int(current.progress * 100))%")
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        ProgressView(value: current.progress)
                            .tint(current.state.color)
                            .accessibilityLabel("Download progress")
                            .accessibilityValue("\(Int(current.progress * 100)) percent")
                    }
                    .padding(16)
                    .darkCard(cornerRadius: 18)
                    LazyVGrid(columns: columns, spacing: 10) {
                        MetricCard("Size", value: current.size, symbol: "externaldrive")
                        MetricCard(
                            "Speed", value: store.hasFreshData ? current.speed : "—",
                            symbol: current.state == .seeding ? "arrow.up" : "arrow.down")
                        MetricCard(
                            "Peers", value: "\(current.state == .paused ? 0 : current.peers)",
                            symbol: "person.2")
                        MetricCard("Status", value: current.state.rawValue, symbol: current.state.symbol)
                        MetricCard("ETA", value: store.hasFreshData ? current.eta : "—", symbol: "clock")
                        MetricCard("Ratio", value: current.ratio, symbol: "arrow.up.arrow.down")
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CardSectionTitle("Files")
                        Spacer()
                        if loadingDetails { ProgressView().controlSize(.small) }
                    }
                    if files.isEmpty {
                        Text(loadingDetails ? "Loading files…" : "No file details available")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).darkCard(cornerRadius: 18)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(files) { file in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(file.name).font(.subheadline).lineLimit(2)
                                        Text("\(Torrent.bytes(file.size)) · \(Int(file.progress * 100))%")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    Menu {
                                        Button("Skip", systemImage: "minus.circle") {
                                            changePriority(file, to: 0)
                                        }
                                        Button("Normal", systemImage: "arrow.down") {
                                            changePriority(file, to: 1)
                                        }
                                        Button("High", systemImage: "arrow.up") {
                                            changePriority(file, to: 6)
                                        }
                                        Button("Maximum", systemImage: "arrow.up.to.line") {
                                            changePriority(file, to: 7)
                                        }
                                    } label: {
                                        if changingFile == file.id {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Text(priorityLabel(file.priority)).font(.caption.weight(.medium))
                                        }
                                    }
                                    .disabled(!store.canControl || changingFile != nil)
                                    .accessibilityLabel("Priority for \(file.name)")
                                }
                                .padding(.vertical, 12)
                                if file.id != files.last?.id { Divider().overlay(AppTheme.border) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .darkCard(cornerRadius: 18)
                    }
                }

                if !trackers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        CardSectionTitle("Trackers")
                        LazyVStack(spacing: 0) {
                            ForEach(Array(trackers.enumerated()), id: \.offset) { index, tracker in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tracker.url).font(.subheadline).lineLimit(2)
                                    if let message = tracker.msg, !message.isEmpty {
                                        Text(message).font(.caption)
                                            .foregroundStyle(
                                                (tracker.status ?? 0) >= 3 ? Color.red : Color.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                                if index < trackers.count - 1 { Divider().overlay(AppTheme.border) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .darkCard(cornerRadius: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    CardSectionTitle("Source")
                    VStack(spacing: 0) {
                        DetailRow("Category", current.category)
                        Divider().overlay(AppTheme.border)
                        DetailRow(
                            "Tracker", current.trackerURL.isEmpty ? current.trackerLabel : current.trackerURL,
                            copyable: true)
                        if let date = current.dateAdded {
                            Divider().overlay(AppTheme.border)
                            HStack {
                                Text("Date added").foregroundStyle(AppTheme.secondaryText)
                                Spacer()
                                Text(date, style: .date).foregroundStyle(.white)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 15)
                        }
                        Divider().overlay(AppTheme.border)
                        DetailRow("Save location", current.savePath, copyable: true)
                    }
                    .padding(.horizontal, 16)
                    .darkCard(cornerRadius: 18)
                }

                removalButtons
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .softScrollEdges()
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Torrent")
        .torrentDetailActions(store: store, torrent: current)
        .minimizeNavigationBarOnScroll()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: torrent.id) { await loadDetails() }
        .refreshable { await loadDetails() }
    }
    private func loadDetails() async {
        loadingDetails = true
        async let nextFiles = store.torrentFiles(torrent.id)
        async let nextTrackers = store.torrentTrackers(torrent.id)
        if let result = await nextFiles { files = result }
        if let result = await nextTrackers {
            trackers = result.filter { !$0.url.isEmpty && !$0.url.hasPrefix("**") }
        }
        loadingDetails = false
    }
    private func priorityLabel(_ value: Int) -> String {
        switch value {
        case 0: "Skipped"
        case 6: "High"
        case 7: "Maximum"
        default: "Normal"
        }
    }
    private func changePriority(_ file: TorrentFile, to priority: Int) {
        changingFile = file.id
        Task {
            if await store.setFilePriority(torrent: torrent.id, fileID: file.id, priority: priority) {
                files = await store.torrentFiles(torrent.id) ?? files
            }
            changingFile = nil
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: current.state.symbol)
                    .font(.title2)
                    .foregroundStyle(current.state.color)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(current.state.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(current.state.color)
                    Text("Torrent")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            Text(current.name)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .darkCard(cornerRadius: 22)
    }
    private var removalButtons: some View {
        HStack(spacing: 10) {
            Button {
                removal = .delete
            } label: {
                Label("Delete", systemImage: "minus.circle")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.glass)
            Button {
                removal = .purge
            } label: {
                Label("Purge", systemImage: "trash")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.glassProminent)
        }
        .tint(.red)
        .disabled(!store.canControl)
        .confirmationDialog(
            "\(removal?.rawValue ?? "Remove") torrent?",
            isPresented: Binding(
                get: { removal != nil },
                set: { if !$0 { removal = nil } }
            ),
            titleVisibility: .visible,
            presenting: removal
        ) { action in
            Button(action == .purge ? "Purge torrent and files" : "Delete torrent", role: .destructive) {
                remove(deleteFiles: action == .purge)
            }
            .disabled(!store.canControl)
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(
                action == .purge
                    ? "This deletes “\(current.name)” and its downloaded files from disk."
                    : "This removes “\(current.name)” and keeps its downloaded files."
            )
        }
    }
    private func remove(deleteFiles: Bool) {
        Task {
            if await store.delete(torrent.id, deleteFiles: deleteFiles) { dismiss() }
        }
    }
}
