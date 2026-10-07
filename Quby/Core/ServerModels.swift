import Foundation

enum ServerAuthentication: String, Codable, CaseIterable, Identifiable {
    case password, apiKey
    var id: Self { self }
    var title: String { self == .password ? "Username & password" : "API key" }
}

struct SavedConnection: Codable {
    let address: String
    let username: String
    let password: String
    var authentication: ServerAuthentication = .password
    var apiKey: String? = nil

    func password(matching address: String, username: String) -> String? {
        guard authentication == .password, matches(address),
            self.username == username.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return password
    }

    func apiKey(matching address: String) -> String? {
        guard authentication == .apiKey, matches(address),
            let apiKey, !apiKey.isEmpty
        else { return nil }
        return apiKey
    }

    private func matches(_ address: String) -> Bool {
        guard let url = try? QBittorrentAPI.serverURL(address) else { return false }
        return URL(string: self.address) == url
    }
}

struct ServerInstance: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var address: String
    var username: String
    var remembersLogin: Bool
    var authentication: ServerAuthentication = .password
}

// Older profiles and Keychain records have no authentication field.
extension SavedConnection {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        address = try values.decode(String.self, forKey: .address)
        username = try values.decode(String.self, forKey: .username)
        password = try values.decode(String.self, forKey: .password)
        authentication =
            try values.decodeIfPresent(ServerAuthentication.self, forKey: .authentication) ?? .password
        apiKey = try values.decodeIfPresent(String.self, forKey: .apiKey)
    }
}

extension ServerInstance {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        address = try values.decode(String.self, forKey: .address)
        username = try values.decode(String.self, forKey: .username)
        remembersLogin = try values.decode(Bool.self, forKey: .remembersLogin)
        authentication =
            try values.decodeIfPresent(ServerAuthentication.self, forKey: .authentication) ?? .password
    }
}
