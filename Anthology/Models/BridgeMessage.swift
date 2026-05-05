import Foundation

/// Outbound (client → server) request envelope. Encoded as a flat JSON object,
/// not the tagged enum form, to match the protocol exactly.
struct OutboundMessage {
    let type: String
    let id: String?
    let payload: [String: AnyCodable]

    func jsonData() throws -> Data {
        var dict: [String: AnyCodable] = payload
        dict["type"] = AnyCodable(type)
        if let id = id { dict["id"] = AnyCodable(id) }
        return try JSONEncoder().encode(dict)
    }
}

/// Inbound message — only the discriminator + raw container; per-type payloads
/// pulled out by the BridgeClient via partial decoding.
struct InboundMessage: Decodable {
    let type: String
    let id: String?
    let raw: [String: AnyCodable]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        var dict: [String: AnyCodable] = [:]
        for k in c.allKeys {
            if let v = try? c.decode(AnyCodable.self, forKey: k) {
                dict[k.stringValue] = v
            }
        }
        type = dict["type"]?.stringValue ?? ""
        id = dict["id"]?.stringValue
        raw = dict
    }

    func value<T: Decodable>(_ key: String, as: T.Type = T.self) -> T? {
        guard let any = raw[key] else { return nil }
        do {
            let data = try JSONEncoder().encode(any)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    func string(_ key: String) -> String? { raw[key]?.stringValue }
    func int(_ key: String) -> Int? { raw[key]?.intValue }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { Int(stringValue) }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = String(intValue) }
}

/// JSON value wrapper that round-trips arbitrary structure. We need this because
/// the protocol's payload shape varies per `type`.
struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            value = NSNull()
        } else if let b = try? c.decode(Bool.self) {
            value = b
        } else if let i = try? c.decode(Int.self) {
            value = i
        } else if let d = try? c.decode(Double.self) {
            value = d
        } else if let s = try? c.decode(String.self) {
            value = s
        } else if let arr = try? c.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let dict = try? c.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull: try c.encodeNil()
        case let b as Bool: try c.encode(b)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let arr as [Any]: try c.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]: try c.encode(dict.mapValues { AnyCodable($0) })
        default:
            try c.encodeNil()
        }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        return nil
    }
    var doubleValue: Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
    var boolValue: Bool? { value as? Bool }
    var dictValue: [String: AnyCodable]? {
        guard let d = value as? [String: Any] else { return nil }
        return d.mapValues { AnyCodable($0) }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        let l = (try? JSONEncoder().encode(lhs)) ?? Data()
        let r = (try? JSONEncoder().encode(rhs)) ?? Data()
        return l == r
    }
}
