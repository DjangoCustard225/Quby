import SwiftUI

struct AddTorrentView: View {
    let store: TransferStore
    var source: TorrentSource = .magnet("")
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var options = TorrentAddDefaults()
    @State private var instanceID: String?
    @State private var categories: [String] = []
    @State private var categoryError: String?
    @State private var submitting = false

    private var valid: Bool {
        switch source {
        case .magnet: TorrentSource.isValidMagnet(link)
        case .file: true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if case .magnet = source, store.connectionIssue != nil {
                    Section { ServerMessage(store: store) }
                        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                }
                sourceSection
                TorrentAddOptions(
                    categories: categories, options: $options
                )
                .equatable()
                if let categoryError {
                    Section {
                        Text(categoryError).font(.footnote).foregroundStyle(.secondary)
                        Button("Retry loading categories") { Task { await loadCategories() } }
                    }
                }
            }
            .disabled(submitting)
            .appListBackground()
            .navigationTitle("Add torrent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "Adding…" : "Add", action: submit)
                        .disabled(
                            !valid || !store.canControl || submitting || instanceID != store.activeInstanceID)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(submitting)
        .task {
            instanceID = store.activeInstanceID
            options = TorrentAddDefaults.load(instanceID: instanceID)
            categories = store.categories.filter { $0 != Torrent.uncategorized }
            if case .magnet(let initialLink) = source, link.isEmpty { link = initialLink }
            await loadCategories()
        }
        .onChange(of: store.activeInstanceID) { _, _ in dismiss() }
    }

    @ViewBuilder private var sourceSection: some View {
        switch source {
        case .magnet:
            Section("Magnet link") {
                TextField("magnet:?xt=urn:…", text: $link, axis: .vertical)
                    .lineLimit(3...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        case .file(let file):
            Section("Torrent file") {
                Label(file.filename, systemImage: "doc.zipper").lineLimit(2)
                LabeledContent("Size", value: Torrent.bytes(Int64(file.data.count)))
            }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private func loadCategories() async {
        categoryError = nil
        if let names = await store.serverCategories(onFailure: { categoryError = $0 }),
            instanceID == store.activeInstanceID, !Task.isCancelled
        {
            categories = names
            if !options.category.isEmpty && !names.contains(options.category) { options.category = "" }
        }
    }

    private func submit() {
        submitting = true
        Task {
            let success: Bool
            switch source {
            case .magnet:
                success = await store.add(
                    link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: options.category, automaticManagement: options.automaticManagement,
                    location: options.location, startPaused: options.startPaused)
            case .file(let file):
                success = await store.add(
                    file: file.data, filename: file.filename,
                    category: options.category, automaticManagement: options.automaticManagement,
                    location: options.location, startPaused: options.startPaused)
            }
            submitting = false
            if success {
                options.save(instanceID: instanceID)
                dismiss()
            }
        }
    }
}

private struct TorrentAddOptions: View, Equatable {
    let categories: [String]
    @Binding var options: TorrentAddDefaults

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.categories == rhs.categories && lhs.options == rhs.options
    }

    var body: some View {
        Section("Options") {
            Picker(selection: $options.category) {
                Text("None").tag("")
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            } label: {
                Label("Category", systemImage: "tag")
            }
            Toggle(isOn: $options.startPaused) {
                Label("Start paused", systemImage: "pause.circle")
            }
        }
        .listRowBackground(AppTheme.formRowBackground)
        Section {
            Toggle(isOn: $options.automaticManagement) {
                Label("Automatic management", systemImage: "arrow.triangle.2.circlepath")
            }
            if !options.automaticManagement {
                TextField("Server default", text: $options.location)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Save location on server")
            }
        } header: {
            Text("Save location")
        } footer: {
            Text(
                options.automaticManagement
                    ? "qBittorrent chooses the folder using its category and server settings."
                    : "Enter a folder on the server, or leave blank to use its default. Options are remembered for this instance."
            )
        }
        .listRowBackground(AppTheme.formRowBackground)
    }
}
