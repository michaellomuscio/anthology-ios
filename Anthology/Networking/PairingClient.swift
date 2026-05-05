import Foundation

/// Pure HTTP /pair client. Does not touch storage — caller persists the result.
enum PairingClient {
    static func pair(host: String, port: Int, code: String, label: String) async throws -> PairingResponse {
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = host
        comps.port = port
        comps.path = "/pair"
        guard let url = comps.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["code": code, "label": label]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 200 {
            return try JSONDecoder().decode(PairingResponse.self, from: data)
        } else {
            if let err = try? JSONDecoder().decode(PairingError.self, from: data) {
                throw err
            }
            throw URLError(.init(rawValue: http.statusCode))
        }
    }

    static func health(host: String, port: Int) async throws -> [String: Any] {
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = host
        comps.port = port
        comps.path = "/health"
        guard let url = comps.url else { throw URLError(.badURL) }
        let req = URLRequest(url: url, timeoutInterval: 4)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
