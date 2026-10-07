import SwiftUI

struct AddTorrentView: View {
    let store: TransferStore
    var source: TorrentSource = .magnet("")
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var category = ""
    @State private var automaticManagement = true
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
                    categories: store.categories.filter { $0 != Torrent.uncategorized },
                    category: $category, automaticManagement: $automaticManagement
                )
                .equatable()
            }
            .appListBackground()
            .navigationTitle("Add torrent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "Adding…" : "Add", action: submit)
                        .disabled(!valid || !store.canControl || submitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(submitting)
        .onAppear {
            if case .magnet(let initialLink) = source, link.isEmpty { link = initialLink }
        }
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

    private func submit() {
        submitting = true
        Task {
            let success: Bool
            switch source {
            case .magnet:
                success = await store.add(
                    link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: category, automaticManagement: automaticManagement)
            case .file(let file):
                success = await store.add(
                    file: file.data, filename: file.filename,
                    category: category, automaticManagement: automaticManagement)
            }
            submitting = false
            if success { dismiss() }
        }
    }
}

private struct TorrentAddOptions: View, Equatable {
    let categories: [String]
    @Binding var category: String
    @Binding var automaticManagement: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.categories == rhs.categories && lhs.category == rhs.category
            && lhs.automaticManagement == rhs.automaticManagement
    }

    var body: some View {
        Section("Options") {
            Picker(selection: $category) {
                Text("None").tag("")
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            } label: {
                Label("Category", systemImage: "folder")
            }
            Toggle(isOn: $automaticManagement) {
                Label("Automatic torrent management", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
    }
}
