import Foundation
import Observation

@MainActor @Observable
final class TransferStore {
    private static let instancesKey = "serverInstances"
    private static let activeKey = "activeServerInstanceID"
    private(set) var instances: [ServerInstance] = []
    private(set) var activeInstanceID: String?
    var activeInstance: ServerInstance? { instances.first { $0.id == activeInstanceID } }
    private(set) var torrents: [Torrent] = []
    private(set) var info = TransferInfo.zero
    private(set) var connected = false
    private(set) var online = false
    private(set) var connecting = false
    @ObservationIgnored private var working = false
    @ObservationIgnored private var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    var error: String?
    private(set) var connectionIssue: String?
    private(set) var lastUpdated: Date?
    private(set) var version = ""
    var status: String {
        connecting
            ? "Connecting…" : online ? "Connected" : connected ? "Reconnecting…" : "Not connected"
    }
    var hasFreshData: Bool { connected && online && lastUpdated != nil }
    private(set) var pendingToggles: Set<String> = []
    private(set) var activeTransfers = 0
    var activeTorrents: [Torrent] { torrents.filter(\.isActive) }
    private(set) var sortOrder =
        TorrentSort(rawValue: UserDefaults.standard.string(forKey: "torrentSort") ?? "") ?? .dateAdded
    var canControl: Bool { online && !connecting }
    private(set) var categories: [String] = []
    private(set) var trackers: [String] = []
    @ObservationIgnored private var api: QBittorrentAPI?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var restored = false
    @ObservationIgnored private let processor = TorrentProcessor()
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var remoteRecords: [RemoteTorrent] = []

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.instancesKey),
            let saved = try? JSONDecoder().decode([ServerInstance].self, from: data)
        {
            instances = saved
        } else if let oldAddress = defaults.string(forKey: "serverAddress"), !oldAddress.isEmpty {
            instances = [
                ServerInstance(
                    id: "legacy", name: "Home", address: oldAddress,
                    username: defaults.string(forKey: "serverUsername") ?? "",
                    remembersLogin: Credentials.load(id: "legacy") != nil
                )
            ]
            persistInstances()
        }
        activeInstanceID =
            defaults.string(forKey: Self.activeKey).flatMap { id in
                instances.first(where: { $0.id == id })?.id
            } ?? instances.first?.id
    }

    private func persistInstances() {
        if let data = try? JSONEncoder().encode(instances) {
            UserDefaults.standard.set(data, forKey: Self.instancesKey)
        }
        UserDefaults.standard.set(activeInstanceID, forKey: Self.activeKey)
    }

    private func upsert(_ instance: ServerInstance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        } else {
            instances.append(instance)
        }
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        if UserDefaults.standard.bool(forKey: "reconnect"),
            let instance = activeInstance, instance.remembersLogin,
            hasSavedLogin(for: instance.id)
        {
            await connectSavedInstance(instance)
        }
    }

    func canReusePassword(id: String?, address: String, username: String) -> Bool {
        reusablePassword(id: id, address: address, username: username) != nil
    }

    func passwordForConnection(id: String?, address: String, username: String, password: String) -> String {
        password.isEmpty ? reusablePassword(id: id, address: address, username: username) ?? "" : password
    }

    private func reusablePassword(id: String?, address: String, username: String) -> String? {
        guard let id else { return nil }
        return Credentials.load(id: id)?.password(matching: address, username: username)
    }

    func canReuseAPIKey(id: String?, address: String) -> Bool {
        guard let id else { return false }
        return Credentials.load(id: id)?.apiKey(matching: address) != nil
    }

    func apiKeyForConnection(id: String?, address: String, apiKey: String) -> String {
        let cleanedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedKey.isEmpty, let id else { return cleanedKey }
        return Credentials.load(id: id)?.apiKey(matching: address) ?? ""
    }

    private func connectionCredentials(
        address: String, username: String, password: String,
        authentication: ServerAuthentication, apiKey: String, id: String?
    ) throws -> SavedConnection {
        let url = try QBittorrentAPI.serverURL(address)
        switch authentication {
        case .password:
            let cleanedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
            return SavedConnection(
                address: url.absoluteString, username: cleanedUser,
                password: passwordForConnection(
                    id: id, address: address, username: cleanedUser, password: password))
        case .apiKey:
            let key = try QBittorrentAPI.validatedAPIKey(
                apiKeyForConnection(id: id, address: address, apiKey: apiKey))
            return SavedConnection(
                address: url.absoluteString, username: "", password: "", authentication: .apiKey, apiKey: key)
        }
    }

    private func saveInstance(
        name: String, login: SavedConnection, remember: Bool,
        id: String? = nil, onFailure: ((String) -> Void)? = nil
    ) -> String? {
        let instanceID = id ?? UUID().uuidString
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            reportConnectionFailure("Enter an instance name.", onFailure: onFailure)
            return nil
        }
        let savedLogin = persistLogin(login, id: instanceID, remember: remember, onFailure: onFailure)
        let profile = ServerInstance(
            id: instanceID, name: cleanedName,
            address: login.address,
            username: login.username, remembersLogin: savedLogin, authentication: login.authentication)
        let previous = activeInstance
        upsert(profile)
        if activeInstanceID == nil { activeInstanceID = instanceID }
        if activeInstanceID == instanceID {
            if previous?.address != profile.address || previous?.username != profile.username
                || previous?.authentication != profile.authentication
            {
                resetConnection()
            }
            UserDefaults.standard.set(savedLogin, forKey: "reconnect")
        }
        persistInstances()
        return instanceID
    }

    private func persistLogin(
        _ login: SavedConnection, id: String, remember: Bool, onFailure: ((String) -> Void)? = nil
    ) -> Bool {
        guard remember else {
            Credentials.remove(id: id)
            return false
        }
        do {
            try Credentials.save(login, id: id)
            return true
        } catch {
            // A Keychain failure must not prevent using the provided login.
            reportConnectionFailure(error.localizedDescription, onFailure: onFailure)
            return false
        }
    }

    // Resolve the saved login before saving can remove it from Keychain.
    // Failed connections still leave the instance saved for offline use.
    func saveAndConnectInstance(
        name: String, address: String, username: String, password: String,
        remember: Bool, authentication: ServerAuthentication = .password, apiKey: String = "",
        id: String?, onFailure: @escaping (String) -> Void
    ) async -> Bool {
        guard !connecting else {
            onFailure("Wait for the current connection attempt to finish.")
            return false
        }
        do {
            let login = try connectionCredentials(
                address: address, username: username, password: password,
                authentication: authentication, apiKey: apiKey, id: id)
            guard
                let instanceID = saveInstance(
                    name: name, login: login, remember: remember,
                    id: id, onFailure: onFailure)
            else { return false }
            return await connect(
                name: name, login: login, remember: remember,
                id: instanceID, onFailure: onFailure)
        } catch {
            onFailure(QBError.message(for: error))
            return false
        }
    }

    private func reportConnectionFailure(_ message: String, onFailure: ((String) -> Void)?) {
        if let onFailure { onFailure(message) } else { error = message }
    }

    private func connect(
        name: String, login: SavedConnection, remember: Bool,
        id: String, onFailure: ((String) -> Void)? = nil
    ) async -> Bool {
        guard !connecting else { return false }
        error = nil
        connecting = true
        generation = UUID()
        let token = generation
        var newClient: QBittorrentAPI?
        do {
            let client = try QBittorrentAPI(address: login.address)
            newClient = client
            switch login.authentication {
            case .password: try await client.login(username: login.username, password: login.password)
            case .apiKey: try await client.login(apiKey: login.apiKey ?? "")
            }
            let snapshot = try await client.snapshot()
            guard generation == token else {
                client.close()
                return false
            }
            resetConnection()
            connecting = true
            api = client
            version = client.version
            connected = true
            online = true
            let savedLogin = persistLogin(login, id: id, remember: remember)
            let profile = ServerInstance(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                address: client.baseURL.absoluteString, username: login.username, remembersLogin: savedLogin,
                authentication: login.authentication)
            upsert(profile)
            activeInstanceID = id
            persistInstances()
            UserDefaults.standard.set(savedLogin, forKey: "reconnect")
            let activeToken = generation
            await apply(snapshot, token: activeToken, revision: revision)
            guard generation == activeToken else { return false }
            connecting = false
            return true
        } catch {
            newClient?.close()
            guard generation == token else { return false }
            reportConnectionFailure(QBError.message(for: error), onFailure: onFailure)
            connecting = false
            return false
        }
    }

    private func connectSavedInstance(_ instance: ServerInstance) async {
        do {
            let login = try connectionCredentials(
                address: instance.address, username: instance.username, password: "",
                authentication: instance.authentication, apiKey: "", id: instance.id)
            _ = await connect(name: instance.name, login: login, remember: true, id: instance.id)
        } catch {
            self.error = QBError.message(for: error)
        }
    }

    func activateInstance(_ id: String) async {
        guard let instance = instances.first(where: { $0.id == id }), activeInstanceID != id else {
            return
        }
        resetConnection()
        activeInstanceID = id
        persistInstances()
        if instance.remembersLogin, hasSavedLogin(for: id) {
            await connectSavedInstance(instance)
        }
    }

    func reconnectActive() async {
        guard let instance = activeInstance,
            hasSavedLogin(for: instance.id)
        else { return }
        await connectSavedInstance(instance)
    }

    func hasSavedLogin(for id: String) -> Bool {
        guard let instance = instances.first(where: { $0.id == id }),
            let saved = Credentials.load(id: id)
        else { return false }
        switch instance.authentication {
        case .password: return saved.password(matching: instance.address, username: instance.username) != nil
        case .apiKey: return saved.apiKey(matching: instance.address) != nil
        }
    }

    func deleteInstance(_ id: String) async {
        guard instances.contains(where: { $0.id == id }) else { return }
        let wasActive = activeInstanceID == id
        instances.removeAll { $0.id == id }
        Credentials.remove(id: id)
        UserDefaults.standard.removeObject(forKey: "addDefaults." + id)
        if wasActive {
            resetConnection()
            activeInstanceID = nil
            if let next = instances.first {
                await activateInstance(next.id)
            }
        }
        persistInstances()
    }

    private func resetConnection() {
        generation = UUID()
        api?.close()
        api = nil
        connected = false
        online = false
        connecting = false
        working = false
        let waiters = mutationWaiters
        mutationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        refreshing = false
        remoteRecords = []
        revision += 1
        activeTransfers = 0
        pendingToggles = []
        categories = []
        trackers = []
        torrents = []
        info = .zero
        lastUpdated = nil
        version = ""
        error = nil
        connectionIssue = nil
    }
    func disconnect() {
        resetConnection()
        UserDefaults.standard.set(false, forKey: "reconnect")
    }
    func forgetSavedLogin() {
        guard let id = activeInstanceID else { return }
        Credentials.remove(id: id)
        if let index = instances.firstIndex(where: { $0.id == id }) {
            instances[index].remembersLogin = false
            persistInstances()
        }
        UserDefaults.standard.set(false, forKey: "reconnect")
    }

    private func apply(_ snapshot: TransferSnapshot, token: UUID, revision: Int) async {
        let prepared = await processor.prepare(snapshot.torrents, sort: sortOrder)
        guard generation == token, self.revision == revision else { return }
        remoteRecords = snapshot.torrents
        publish(prepared, info: snapshot.info)
    }
    func changeSort(_ sort: TorrentSort) async {
        guard sortOrder != sort else { return }
        sortOrder = sort
        UserDefaults.standard.set(sort.rawValue, forKey: "torrentSort")
        revision += 1
        let token = generation
        let snapshotRevision = revision
        let prepared = await processor.prepare(remoteRecords, sort: sort)
        guard generation == token, revision == snapshotRevision else { return }
        publishRows(prepared)
    }
    private func publishRows(_ prepared: PreparedTorrents) {
        if torrents != prepared.items { torrents = prepared.items }
        if activeTransfers != prepared.activeTransfers { activeTransfers = prepared.activeTransfers }
        if categories != prepared.categories { categories = prepared.categories }
        if trackers != prepared.trackers { trackers = prepared.trackers }
    }
    private func publish(_ prepared: PreparedTorrents, info nextInfo: TransferInfo) {
        publishRows(prepared)
        if info != nextInfo { info = nextInfo }
        lastUpdated = Date()
        if !online { online = true }
        if connectionIssue != nil { connectionIssue = nil }
    }
    private func handle(_ failure: Error, notify: Bool = true, onFailure: ((String) -> Void)? = nil) {
        if let onFailure {
            onFailure(failure.localizedDescription)
        } else if notify {
            error = failure.localizedDescription
        } else {
            connectionIssue = failure.localizedDescription
        }
        switch failure {
        case QBError.expired, QBError.apiKeyRejected:
            connected = false
            online = false
            api?.close()
            api = nil
            UserDefaults.standard.set(false, forKey: "reconnect")
        default: break
        }
    }
    func refresh() async {
        guard connected, let api, !working, !connecting, !refreshing else { return }
        let token = generation
        let snapshotRevision = revision
        refreshing = true
        defer { if token == generation { refreshing = false } }
        do {
            let snapshot = try await api.snapshot()
            guard token == generation else { return }
            await apply(snapshot, token: token, revision: snapshotRevision)
        } catch {
            guard token == generation, snapshotRevision == revision, !Task.isCancelled else { return }
            online = false
            handle(error, notify: false)
        }
    }
    func toggle(_ id: String) async {
        guard canControl, !pendingToggles.contains(id),
            let item = torrents.first(where: { $0.id == id })
        else { return }
        pendingToggles.insert(id)
        let token = generation
        defer { if generation == token { pendingToggles.remove(id) } }
        _ = await mutate {
            guard self.torrents.contains(where: { $0.id == id }) else { throw QBError.invalidSelection }
            try await $0.setPaused(hash: id, paused: item.state != .paused)
        }
    }
    func delete(_ id: String, deleteFiles: Bool) async -> Bool {
        guard torrents.contains(where: { $0.id == id }) else { return false }
        return await mutate { try await $0.delete(hash: id, deleteFiles: deleteFiles) }
    }
    func torrentFiles(_ id: String) async throws -> [TorrentFile] {
        guard let api, connected else { throw QBError.expired }
        let token = generation
        do {
            let files = try await api.files(hash: id)
            guard token == generation else { throw CancellationError() }
            return files
        } catch {
            if token == generation { handleDetailFailure(error) }
            throw error
        }
    }
    func torrentTrackers(_ id: String) async throws -> [TorrentTracker] {
        guard let api, connected else { throw QBError.expired }
        let token = generation
        do {
            let trackers = try await api.trackers(hash: id)
            guard token == generation else { throw CancellationError() }
            return trackers
        } catch {
            if token == generation { handleDetailFailure(error) }
            throw error
        }
    }
    private func handleDetailFailure(_ error: Error) {
        switch error {
        case QBError.expired, QBError.apiKeyRejected: handle(error, notify: false)
        default: break
        }
    }
    func setFilePriority(torrent id: String, fileID: Int, priority: Int) async -> Bool {
        await mutate { try await $0.setFilePriority(hash: id, fileID: fileID, priority: priority) }
    }

    func serverCategories(onFailure: @escaping (String) -> Void) async -> [String]? {
        guard let api, connected else {
            onFailure("Reconnect to your server first.")
            return nil
        }
        let token = generation
        do {
            let names = try await api.categories()
            return token == generation ? names : nil
        } catch {
            if token == generation, !Task.isCancelled { handle(error, onFailure: onFailure) }
            return nil
        }
    }

    func perform(_ command: TorrentCommand, ids: Set<String>, instanceID: String?) async
        -> TorrentCommandResult
    {
        guard activeInstanceID == instanceID, !ids.isEmpty,
            ids.isSubset(of: Set(torrents.map(\.id)))
        else {
            return .failed("The selected torrents are no longer available on this instance.")
        }
        guard canControl else {
            return .failed("Reconnect to your server first.")
        }
        var failure: String?
        let accepted = await mutate(
            acceptedWithoutRefresh: true, onFailure: { failure = $0 },
            { api in
                guard self.activeInstanceID == instanceID,
                    ids.isSubset(of: Set(self.torrents.map(\.id)))
                else { throw QBError.invalidSelection }
                let hashes = ids.sorted()
                switch command {
                case .location(let path): try await api.setLocation(hashes: hashes, location: path)
                case .category(let name): try await api.setCategory(hashes: hashes, category: name)
                case .recheck: try await api.recheck(hashes: hashes)
                case .reannounce: try await api.reannounce(hashes: hashes)
                case .pause: try await api.setPaused(hashes: hashes, paused: true)
                case .resume: try await api.setPaused(hashes: hashes, paused: false)
                case .delete(let deleteFiles): try await api.delete(hashes: hashes, deleteFiles: deleteFiles)
                }
            })
        return accepted ? .accepted : .failed(failure ?? "The request was interrupted. Try again.")
    }
    func add(
        link: String, category: String, automaticManagement: Bool, location: String = "",
        startPaused: Bool = false
    ) async -> Bool {
        guard canControl else {
            error = "Connect to your server first."
            return false
        }
        return await mutate(acceptedWithoutRefresh: true) {
            try await $0.add(
                link: link, category: category, automaticManagement: automaticManagement, location: location,
                startPaused: startPaused)
        }
    }
    func add(
        file: Data, filename: String, category: String, automaticManagement: Bool, location: String = "",
        startPaused: Bool = false
    ) async -> Bool {
        guard canControl else {
            error = "Connect to your server first."
            return false
        }
        return await mutate(acceptedWithoutRefresh: true) {
            try await $0.add(
                file: file, filename: filename, category: category, automaticManagement: automaticManagement,
                location: location, startPaused: startPaused
            )
        }
    }
    func speedLimits() async throws -> SpeedLimits {
        guard connected, let api else { throw QBError.expired }
        let token = generation
        do {
            let limits = try await api.speedLimits()
            guard token == generation else { throw CancellationError() }
            return limits
        } catch {
            if token == generation { handle(error, notify: false) }
            throw error
        }
    }

    func setSpeedLimits(_ limits: SpeedLimits, onFailure: @escaping (String) -> Void) async -> Bool {
        await mutate(acceptedWithoutRefresh: true, onFailure: onFailure) {
            try await $0.setSpeedLimits(limits)
        }
    }

    func setAlternativeSpeedLimits(_ enabled: Bool, onFailure: @escaping (String) -> Void) async -> Bool {
        await mutate(onFailure: onFailure) { try await $0.setAlternativeSpeedLimits(enabled) }
    }

    private func mutate(
        acceptedWithoutRefresh: Bool = false, onFailure: ((String) -> Void)? = nil,
        _ action: (QBittorrentAPI) async throws -> Void
    ) async -> Bool {
        guard canControl else { return false }
        let token = generation
        if working { await withCheckedContinuation { mutationWaiters.append($0) } }
        guard token == generation else { return false }
        // A queued request belongs to the connection on which it was submitted.
        guard canControl, !Task.isCancelled, let api else {
            releaseMutation(token: token)
            return false
        }
        revision += 1
        let snapshotRevision = revision
        working = true
        defer { releaseMutation(token: token) }
        do {
            try await action(api)
            guard token == generation else { return false }
            if acceptedWithoutRefresh {
                Task { await refresh() }
                return true
            }
            do {
                let snapshot = try await api.snapshot()
                guard token == generation else { return false }
                await apply(snapshot, token: token, revision: snapshotRevision)
            } catch {
                if token == generation {
                    online = false
                    handle(error, notify: false)
                }
            }
            return token == generation
        } catch {
            if token == generation { handle(error, onFailure: onFailure) }
            return false
        }
    }

    private func releaseMutation(token: UUID) {
        guard token == generation else { return }
        if mutationWaiters.isEmpty { working = false } else { mutationWaiters.removeFirst().resume() }
    }
}
