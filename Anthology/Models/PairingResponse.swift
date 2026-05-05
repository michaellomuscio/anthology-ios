import Foundation

struct PairingResponse: Decodable {
    let tokenId: String
    let token: String
    let serverName: String
    let serverVersion: String
    let `protocol`: String?
}

struct PairingError: Decodable, Error, CustomStringConvertible {
    let error: String
    var description: String { "pair_failed: \(error)" }
}

/// Decoded from the QR payload: anthology://pair?host=<host>&port=<port>&code=<code>
struct PairingURL {
    let host: String
    let port: Int
    let code: String

    init?(from string: String) {
        guard let url = URL(string: string),
              url.scheme == "anthology",
              url.host == "pair" || url.path.hasSuffix("pair") || url.path.contains("pair")
        else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        let h = items.first(where: { $0.name == "host" })?.value ?? ""
        let pStr = items.first(where: { $0.name == "port" })?.value ?? ""
        let c = items.first(where: { $0.name == "code" })?.value ?? ""
        guard !h.isEmpty, let p = Int(pStr), !c.isEmpty else { return nil }
        self.host = h
        self.port = p
        self.code = c
    }
}
