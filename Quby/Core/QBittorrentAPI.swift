import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

enum QBError: LocalizedError {
    case invalidURL, loginFailed, loginBlocked, missingSession, expired
    case invalidAPIKey, apiKeyRejected, apiKeyUnsupported
    case http(Int)
    case unexpected, rejected, redirect
    case invalidSelection, invalidLocation, locationDenied
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return
                "Enter the full Web UI URL, such as https://your-server:8080. Include any reverse-proxy path, but not /api/v2."
        case .loginFailed: return "Login failed. Check your Web UI username and password."
        case .invalidAPIKey: return "Enter the API key from qBittorrent’s Web UI settings."
        case .apiKeyRejected:
            return
                "The API key was rejected or access was denied. Check the key and API access in qBittorrent’s Web UI settings. API key login requires qBittorrent 5.2 or later."
        case .apiKeyUnsupported:
            return
                "API key login requires qBittorrent 5.2 or later. Use username and password for this server."
        case .loginBlocked:
            return
                "The server blocked login. Check qBittorrent’s IP ban, Host header, and reverse-proxy access settings."
        case .missingSession:
            return
                "Login succeeded, but the server did not return its session cookie. Check the reverse proxy’s Set-Cookie handling."
        case .expired: return "Session expired or access was denied. Reconnect through Instances in Settings."
        case .http(let code):
            return "The server returned HTTP \(code). Check its Web UI address and access settings."
        case .unexpected:
            return "The server response was not a qBittorrent API response. Check the Web UI URL."
        case .rejected: return "qBittorrent rejected the torrent."
        case .redirect:
            return "The server redirected this request. Edit the instance to use the final Web UI URL."
        case .invalidSelection: return "Select at least one available torrent."
        case .invalidLocation: return "Enter a save path on your qBittorrent server."
        case .locationDenied: return "qBittorrent does not have permission to write to that folder."
        }
    }

    static func message(for error: Error) -> String {
        guard let error = error as? URLError else { return error.localizedDescription }
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            return
                "The server hostname could not be resolved. Check the address and your DNS or VPN connection."
        case .cannotConnectToHost:
            return
                "The server could not be reached. Check the Web UI port and whether this device can access it."
        case .timedOut:
            return "The server took too long to respond. Check the address, port, and network connection."
        case .notConnectedToInternet, .networkConnectionLost:
            return
                "The network connection is unavailable. Check Wi-Fi or your VPN, and allow Quby’s Local Network access in iOS Settings for a local server."
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "The HTTPS certificate could not be verified. Use a certificate trusted by this device."
        default:
            return error.localizedDescription
        }
    }
}

// Do not forward session cookies or credentials through HTTP redirects.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class QBittorrentAPI {
    let baseURL: URL
    private let session: URLSession
    private let delegate = NoRedirects()
    private var sessionCookie: HTTPCookie?
    private var apiKey: String?
    private var sync = TorrentSync()
    private(set) var version = ""

    init(address: String) throws {
        baseURL = try Self.serverURL(address)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    static func serverURL(_ address: String) throws -> URL {
        guard
            let parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
            let host = parts.host, !host.isEmpty,
            parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
            let url = parts.url, !url.path.contains("/api/v2")
        else { throw QBError.invalidURL }
        return url
    }

    func close() {
        session.invalidateAndCancel()
        sessionCookie = nil
        apiKey = nil
    }

    static func form(_ fields: [String: String]) -> Data {
        let safe = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encoded = fields.sorted(by: { $0.key < $1.key }).map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: safe)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: safe)!)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    private func request(
        _ path: String, query: [String: String]? = nil, fields: [String: String]? = nil,
        multipart: Data? = nil, boundary: String? = nil, forbidden: QBError? = nil,
        unauthorized: QBError? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard
            var parts = URLComponents(
                url: baseURL.appendingPathComponent("api/v2/" + path), resolvingAgainstBaseURL: false)
        else { throw QBError.invalidURL }
        if let query {
            parts.queryItems = query.sorted { $0.key < $1.key }.map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
        }
        guard let url = parts.url else { throw QBError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(
            baseURL.absoluteString + (baseURL.absoluteString.hasSuffix("/") ? "" : "/"),
            forHTTPHeaderField: "Referer")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else if let sessionCookie {
            request.setValue(
                HTTPCookie.requestHeaderFields(with: [sessionCookie])["Cookie"],
                forHTTPHeaderField: "Cookie")
        }
        if let fields {
            request.httpMethod = "POST"
            request.httpBody = Self.form(fields)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        if let multipart, let boundary {
            request.httpMethod = "POST"
            request.httpBody = multipart
            request.setValue(
                "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QBError.unexpected }
        if (300...399).contains(http.statusCode) { throw QBError.redirect }
        if http.statusCode == 401, let unauthorized { throw unauthorized }
        if http.statusCode == 403, let forbidden { throw forbidden }
        if http.statusCode == 403 || http.statusCode == 401 {
            throw apiKey == nil ? QBError.expired : QBError.apiKeyRejected
        }
        guard (200...299).contains(http.statusCode) else { throw QBError.http(http.statusCode) }
        updateSessionCookie(from: http)
        return (data, http)
    }

    private func updateSessionCookie(from response: HTTPURLResponse) {
        guard apiKey == nil else { return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let name = pair.key as? String, let value = pair.value as? String { result[name] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: response.url ?? baseURL)
        // qBittorrent 5.2 names cookies after its listening port. A reverse proxy's
        // external port can differ, so preserve the name returned by the server.
        let cookie =
            cookies.first {
                $0.name.range(of: "^QBT_SID_[0-9]+$", options: .regularExpression) != nil
            } ?? cookies.first { $0.name == "SID" }
        guard let cookie else { return }
        sessionCookie =
            cookie.value.isEmpty || cookie.expiresDate.map { $0 <= Date() } == true
            ? nil : cookie
    }

    private func readVersion() async throws -> String {
        let (data, _) = try await request("app/version")
        let value =
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard value.range(of: "^v?[0-9]+\\.[0-9]+", options: .regularExpression) != nil else {
            throw QBError.unexpected
        }
        return value
    }

    func login(username: String, password: String) async throws {
        sync = TorrentSync()
        apiKey = nil
        sessionCookie = nil
        version = ""
        // qBittorrent may exempt trusted IPs from authentication. Do not send
        // an unnecessary login (or count an empty password as a failed attempt).
        do {
            version = try await readVersion()
            return
        } catch QBError.expired {
            // A session is required; continue with login.
        }
        guard !username.isEmpty || !password.isEmpty else { throw QBError.loginFailed }
        let (data, _) = try await request(
            "auth/login", fields: ["username": username, "password": password], forbidden: .loginBlocked,
            unauthorized: .loginFailed)
        guard let body = String(data: data, encoding: .utf8) else { throw QBError.unexpected }
        let result = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if result == "Fails." { throw QBError.loginFailed }
        // v4/v5.1 return "Ok."; v5.2 returns an empty 204 response.
        // Neither response is sufficient without a session and authenticated version check.
        guard result.isEmpty || result == "Ok." else { throw QBError.unexpected }
        guard sessionCookie != nil else { throw QBError.missingSession }
        version = try await readVersion()
    }

    static func validatedAPIKey(_ input: String) throws -> String {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw QBError.invalidAPIKey
        }
        return key
    }

    func login(apiKey input: String) async throws {
        sync = TorrentSync()
        apiKey = nil
        sessionCookie = nil
        version = ""
        apiKey = try Self.validatedAPIKey(input)
        do {
            version = try await readVersion()
            let numbers = version.drop(while: { $0 == "v" }).split(separator: ".")
            let major = Int(numbers[0]) ?? 0
            let minor = numbers.count > 1 ? Int(numbers[1]) ?? 0 : 0
            guard major > 5 || (major == 5 && minor >= 2) else { throw QBError.apiKeyUnsupported }
        } catch {
            apiKey = nil
            version = ""
            throw error
        }
    }

    private func decode<Response: Decodable>(
        _ type: Response.Type, path: String, query: [String: String]? = nil
    ) async throws -> Response {
        let (data, _) = try await request(path, query: query)
        do { return try JSONDecoder().decode(type, from: data) } catch { throw QBError.unexpected }
    }

    func snapshot() async throws -> TransferSnapshot {
        try await sync.snapshot { rid in
            try await self.request("sync/maindata", query: ["rid": String(rid)]).0
        }
    }

    func setPaused(hash: String, paused: Bool) async throws {
        try await setPaused(hashes: [hash], paused: paused)
    }

    private var majorVersion: Int {
        Int(version.drop(while: { $0 == "v" }).split(separator: ".").first ?? "5") ?? 5
    }

    func setPaused(hashes: [String], paused: Bool) async throws {
        let action = majorVersion >= 5 ? (paused ? "stop" : "start") : (paused ? "pause" : "resume")
        _ = try await request("torrents/" + action, fields: ["hashes": try hashList(hashes)])
    }

    func delete(hash: String, deleteFiles: Bool) async throws {
        try await delete(hashes: [hash], deleteFiles: deleteFiles)
    }

    func delete(hashes: [String], deleteFiles: Bool) async throws {
        _ = try await request(
            "torrents/delete",
            fields: ["hashes": try hashList(hashes), "deleteFiles": deleteFiles ? "true" : "false"])
    }

    func speedLimits() async throws -> SpeedLimits {
        try await decode(SpeedLimits.self, path: "app/preferences")
    }

    func setSpeedLimits(_ limits: SpeedLimits) async throws {
        let data = try JSONEncoder().encode(limits)
        _ = try await request("app/setPreferences", fields: ["json": String(decoding: data, as: UTF8.self)])
    }

    func setAlternativeSpeedLimits(_ enabled: Bool) async throws {
        let mode = try await decode(Int.self, path: "transfer/speedLimitsMode")
        if (mode == 1) != enabled {
            _ = try await request("transfer/toggleSpeedLimitsMode", fields: [:])
        }
    }

    private func hashList(_ hashes: [String]) throws -> String {
        guard !hashes.isEmpty,
            hashes.allSatisfy({ !$0.isEmpty && $0 != "all" && !$0.contains("|") })
        else { throw QBError.invalidSelection }
        return Set(hashes).sorted().joined(separator: "|")
    }

    func categories() async throws -> [String] {
        let categories = try await decode([String: RemoteCategory].self, path: "torrents/categories")
        return categories.keys.filter { !$0.isEmpty }.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    func setLocation(hashes: [String], location: String) async throws {
        guard !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QBError.invalidLocation
        }
        do {
            _ = try await request(
                "torrents/setLocation", fields: ["hashes": try hashList(hashes), "location": location],
                forbidden: .locationDenied)
        } catch QBError.locationDenied {
            // This endpoint also uses 403 for filesystem permissions. Probe authentication
            // before treating the response as a lost session.
            _ = try await readVersion()
            throw QBError.locationDenied
        }
    }

    func setCategory(hashes: [String], category: String) async throws {
        _ = try await request(
            "torrents/setCategory", fields: ["hashes": try hashList(hashes), "category": category])
    }

    func recheck(hashes: [String]) async throws {
        _ = try await request("torrents/recheck", fields: ["hashes": try hashList(hashes)])
    }

    func reannounce(hashes: [String]) async throws {
        _ = try await request("torrents/reannounce", fields: ["hashes": try hashList(hashes)])
    }

    func files(hash: String) async throws -> [TorrentFile] {
        try await decode([TorrentFile].self, path: "torrents/files", query: ["hash": hash])
    }

    func trackers(hash: String) async throws -> [TorrentTracker] {
        try await decode([TorrentTracker].self, path: "torrents/trackers", query: ["hash": hash])
    }

    func setFilePriority(hash: String, fileID: Int, priority: Int) async throws {
        _ = try await request(
            "torrents/filePrio",
            fields: [
                "hash": hash, "id": String(fileID), "priority": String(priority),
            ])
    }

    private func addFields(category: String, automaticManagement: Bool, location: String, startPaused: Bool)
        -> [String: String]
    {
        var fields = [
            "category": category, "autoTMM": automaticManagement ? "true" : "false",
            majorVersion >= 5 ? "stopped" : "paused": startPaused ? "true" : "false",
        ]
        let path = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !automaticManagement && !path.isEmpty { fields["savepath"] = path }
        return fields
    }

    func add(
        link: String, category: String, automaticManagement: Bool, location: String = "",
        startPaused: Bool = false
    ) async throws {
        let boundary = "Quby-" + UUID().uuidString
        var fields = addFields(
            category: category, automaticManagement: automaticManagement, location: location,
            startPaused: startPaused)
        fields["urls"] = link
        var body = multipart(fields, boundary: boundary)
        body.append(Data("--\(boundary)--\r\n".utf8))
        try await submit(body, boundary: boundary)
    }

    func add(
        file: Data, filename: String, category: String, automaticManagement: Bool, location: String = "",
        startPaused: Bool = false
    ) async throws {
        guard !file.isEmpty else { throw QBError.rejected }
        let boundary = "Quby-" + UUID().uuidString
        let safeName =
            filename
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\"", with: "")
        var body = multipart(
            addFields(
                category: category, automaticManagement: automaticManagement, location: location,
                startPaused: startPaused), boundary: boundary)
        body.append(
            Data(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"torrents\"; filename=\"\(safeName)\"\r\nContent-Type: application/x-bittorrent\r\n\r\n"
                    .utf8))
        body.append(file)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        try await submit(body, boundary: boundary)
    }

    private func multipart(_ fields: [String: String], boundary: String) -> Data {
        fields.sorted(by: { $0.key < $1.key }).reduce(into: Data()) { body, field in
            body.append(
                Data(
                    "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field.key)\"\r\n\r\n\(field.value)\r\n"
                        .utf8))
        }
    }

    private func submit(_ body: Data, boundary: String) async throws {
        let (data, _) = try await request("torrents/add", multipart: body, boundary: boundary)
        let response =
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !response.hasPrefix("fail") else { throw QBError.rejected }
    }
}
