import SwiftUI

struct ServerEditorView: View {
    let store: TransferStore
    let instance: ServerInstance?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var apiKey = ""
    @State private var authentication: ServerAuthentication = .password
    @State private var remember = true
    @State private var saving = false
    @State private var connectionError: String?
    @State private var instanceID = UUID().uuidString
    @State private var retryConnection: SavedConnection?
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Home", text: $name)
                        .textInputAutocapitalization(.words)
                }
                .listRowBackground(AppTheme.formRowBackground)
                Section("Connection") {
                    TextField("https://server:8080", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                }
                .listRowBackground(AppTheme.formRowBackground)
                Section {
                    Picker("Login method", selection: $authentication) {
                        ForEach(ServerAuthentication.allCases) { Text($0.title).tag($0) }
                    }
                    if authentication == .password {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                        SecureField(
                            store.canReusePassword(id: instanceID, address: address, username: username)
                                || retryConnection?.password(matching: address, username: username) != nil
                                ? "Password (leave blank to reuse)" : "Password", text: $password
                        )
                        .textContentType(.password)
                    } else {
                        SecureField(
                            store.canReuseAPIKey(id: instanceID, address: address)
                                || retryConnection?.apiKey(matching: address) != nil
                                ? "API key (leave blank to reuse)" : "API key", text: $apiKey
                        )
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                    }
                    Toggle("Remember login", isOn: $remember)
                    if address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(
                        "http://")
                    {
                        Label(
                            "HTTP sends your login credentials without encryption. Use HTTPS outside a trusted local network.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    if authentication == .apiKey {
                        Text(
                            "Requires qBittorrent 5.2 or later. Generate an API key in its Web UI settings under Web UI → API Key."
                        )
                    }
                }
                .listRowBackground(AppTheme.formRowBackground)
                if let connectionError {
                    Section("Could not connect") {
                        Text(connectionError).foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    .listRowBackground(AppTheme.formRowBackground)
                }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden)
            .softScrollEdges()
            .listRowSeparatorTint(AppTheme.border)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(instance == nil ? "Add server" : "Edit server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Connecting…" : "Save & Connect") { save() }
                        .disabled(
                            saving || store.connecting
                                || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let instance { instanceID = instance.id }
                name = instance?.name ?? ""
                address = instance?.address ?? ""
                username = instance?.username ?? ""
                authentication = instance?.authentication ?? .password
                remember = instance?.remembersLogin ?? true
            }
            .interactiveDismissDisabled(saving)
        }
    }
    private func save() {
        guard !saving else { return }
        connectionError = nil
        let suppliedPassword =
            password.isEmpty
            ? retryConnection?.password(matching: address, username: username) ?? "" : password
        let loginPassword =
            authentication == .password
            ? store.passwordForConnection(
                id: instanceID, address: address, username: username, password: suppliedPassword) : ""
        let suppliedKey =
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? retryConnection?.apiKey(matching: address) ?? "" : apiKey
        let loginAPIKey =
            authentication == .apiKey
            ? store.apiKeyForConnection(
                id: instanceID, address: address, apiKey: suppliedKey) : ""
        // Keep retries usable after removing the Keychain entry, scoped to this endpoint.
        retryConnection = (try? QBittorrentAPI.serverURL(address)).map {
            SavedConnection(
                address: $0.absoluteString,
                username: authentication == .password
                    ? username.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                password: loginPassword, authentication: authentication,
                apiKey: authentication == .apiKey ? loginAPIKey : nil)
        }
        saving = true
        Task {
            let connected = await store.saveAndConnectInstance(
                name: name, address: address, username: username,
                password: loginPassword, remember: remember, authentication: authentication,
                apiKey: loginAPIKey, id: instanceID,
                onFailure: { connectionError = $0 })
            saving = false
            if connected { dismiss() }
        }
    }
}
