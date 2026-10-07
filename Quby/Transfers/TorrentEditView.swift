import SwiftUI

struct TorrentEditView: View {
    let store: TransferStore
    let request: TorrentActionRequest
    @Bindable var actions: TorrentActionController
    @Environment(\.dismiss) private var dismiss
    @State private var location: String
    @State private var category: String?
    @State private var categories: [String] = []
    @State private var loading = false
    @State private var categoriesLoaded = false

    init(store: TransferStore, request: TorrentActionRequest, actions: TorrentActionController) {
        self.store = store
        self.request = request
        self.actions = actions
        let paths = Set(request.torrents.map(\.savePath))
        let commonPath = paths.count == 1 ? paths.first : nil
        _location = State(initialValue: commonPath == "—" ? "" : commonPath ?? "")
        let names = Set(request.torrents.map(\.categoryName))
        _category = State(initialValue: names.count == 1 ? names.first : nil)
    }

    private var canSubmit: Bool {
        store.canControl && !actions.running && store.activeInstanceID == request.instanceID
            && (request.action == .location
                ? !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                : categoriesLoaded && category != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if request.torrents.count == 1 {
                        Text(request.torrents[0].name).font(.headline)
                    } else {
                        Text("\(request.torrents.count) selected torrents").font(.headline)
                    }
                    if let instance = store.activeInstance {
                        Label(instance.name, systemImage: "server.rack")
                    }
                }
                .listRowBackground(AppTheme.formRowBackground)
                if request.action == .location {
                    Section {
                        TextField("/path/on/server", text: $location)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: {
                        Text("Save location")
                    } footer: {
                        Text("qBittorrent moves the downloaded files to this folder on the server.")
                    }
                    .listRowBackground(AppTheme.formRowBackground)
                } else {
                    Section {
                        if loading {
                            ProgressView("Loading categories…")
                        } else if categoriesLoaded {
                            Picker("Category", selection: $category) {
                                if category == nil { Text("Choose category").tag(nil as String?) }
                                Text("No category").tag(Optional(""))
                                ForEach(categories, id: \.self) { Text($0).tag(Optional($0)) }
                            }
                            .pickerStyle(.inline)
                        } else {
                            Button("Retry loading categories") { Task { await loadCategories() } }
                        }
                    } header: {
                        Text("Category")
                    } footer: {
                        Text("Automatically managed torrents may move to the category’s save path.")
                    }
                    .listRowBackground(AppTheme.formRowBackground)
                }
            }
            .scrollContentBackground(.hidden).softScrollEdges()
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(request.action.rawValue).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(actions.running)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actions.running ? "Applying…" : "Apply") {
                        let command: TorrentCommand =
                            request.action == .location
                            ? .location(location.trimmingCharacters(in: .whitespacesAndNewlines))
                            : .category(category ?? "")
                        Task {
                            if await actions.submit(command, request: request, store: store) { dismiss() }
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .interactiveDismissDisabled(actions.running)
            .alert(
                "Request failed",
                isPresented: Binding(
                    get: { actions.failure != nil }, set: { if !$0 { actions.failure = nil } }
                )
            ) {
                Button("OK") { actions.failure = nil }
            } message: {
                Text(actions.failure ?? "Please try again.")
            }
            .task { if request.action == .category { await loadCategories() } }
        }
    }

    private func loadCategories() async {
        loading = true
        defer { loading = false }
        guard let names = await store.serverCategories(onFailure: { actions.failure = $0 }),
            !Task.isCancelled,
            store.activeInstanceID == request.instanceID
        else { return }
        categories = names
        if let category, !category.isEmpty, !names.contains(category) { self.category = nil }
        categoriesLoaded = true
    }
}
