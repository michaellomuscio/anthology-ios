import Foundation

/// One paired Mac. Token plaintext lives in Keychain; everything else lives
/// in UserDefaults.
struct ServerHandle: Codable, Hashable, Identifiable {
    var id: String { tokenId }
    var host: String
    var port: Int
    var tokenId: String        // matches the Keychain account key
    var serverName: String
    var serverVersion: String
    var pairedAt: Double

    var keychainAccount: String { tokenId }
    var displayName: String { serverName }
    var address: String { "\(host):\(port)" }
}

enum ServerStore {
    private static let key = "anthology.bridge.servers.v1"

    static func list() -> [ServerHandle] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ServerHandle].self, from: data)) ?? []
    }

    static func save(_ servers: [ServerHandle]) {
        let data = (try? JSONEncoder().encode(servers)) ?? Data()
        UserDefaults.standard.set(data, forKey: key)
    }

    static func upsert(_ s: ServerHandle) {
        var all = list()
        if let i = all.firstIndex(where: { $0.tokenId == s.tokenId }) {
            all[i] = s
        } else {
            all.append(s)
        }
        save(all)
    }

    static func remove(tokenId: String) {
        let all = list().filter { $0.tokenId != tokenId }
        save(all)
        KeychainStore.delete(account: tokenId)
    }
}
