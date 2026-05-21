import Foundation
import SwiftUI

/// Mirror of the bridge protocol's `SessionMeta`. Decoded permissively so a
/// future server adding fields doesn't crash older clients.
struct SessionMeta: Codable, Identifiable, Hashable, Equatable {
    let id: String
    var name: String
    var cwd: String
    var color: String
    var tag: String?
    var pinned: Bool
    var status: SessionStatus
    var alive: Bool
    var createdAt: Double?
    var spawnedBySchedule: String?
    // v0.7+ fields — relayed by the Mac bridge. Older Macs omit these and the
    // decoder treats them as nil.
    var isPM: Bool
    var agentTool: String?
    var personaName: String?
    var groupId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, cwd, color, tag, pinned, status, alive, createdAt, spawnedBySchedule
        case isPM, agentTool, personaName, groupId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "session"
        cwd = (try? c.decode(String.self, forKey: .cwd)) ?? ""
        color = (try? c.decode(String.self, forKey: .color)) ?? "#7B2FBE"
        tag = try? c.decodeIfPresent(String.self, forKey: .tag)
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
        let raw = (try? c.decode(String.self, forKey: .status)) ?? "idle"
        status = SessionStatus(rawValue: raw) ?? .idle
        alive = (try? c.decode(Bool.self, forKey: .alive)) ?? false
        createdAt = try? c.decodeIfPresent(Double.self, forKey: .createdAt)
        spawnedBySchedule = try? c.decodeIfPresent(String.self, forKey: .spawnedBySchedule)
        isPM = (try? c.decodeIfPresent(Bool.self, forKey: .isPM)) ?? false
        agentTool = try? c.decodeIfPresent(String.self, forKey: .agentTool)
        personaName = try? c.decodeIfPresent(String.self, forKey: .personaName)
        groupId = try? c.decodeIfPresent(String.self, forKey: .groupId)
    }

    init(id: String, name: String, cwd: String, color: String = "#7B2FBE", tag: String? = nil,
         pinned: Bool = false, status: SessionStatus = .idle, alive: Bool = true,
         createdAt: Double? = nil, spawnedBySchedule: String? = nil,
         isPM: Bool = false, agentTool: String? = nil, personaName: String? = nil,
         groupId: String? = nil) {
        self.id = id; self.name = name; self.cwd = cwd; self.color = color
        self.tag = tag; self.pinned = pinned; self.status = status; self.alive = alive
        self.createdAt = createdAt; self.spawnedBySchedule = spawnedBySchedule
        self.isPM = isPM; self.agentTool = agentTool
        self.personaName = personaName; self.groupId = groupId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(cwd, forKey: .cwd)
        try c.encode(color, forKey: .color)
        try c.encodeIfPresent(tag, forKey: .tag)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(alive, forKey: .alive)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(spawnedBySchedule, forKey: .spawnedBySchedule)
        try c.encode(isPM, forKey: .isPM)
        try c.encodeIfPresent(agentTool, forKey: .agentTool)
        try c.encodeIfPresent(personaName, forKey: .personaName)
        try c.encodeIfPresent(groupId, forKey: .groupId)
    }
}

enum SessionStatus: String, Codable, CaseIterable {
    case running, idle, waiting, error, dead, exited

    var color: Color {
        switch self {
        case .running: return Color(red: 0.18, green: 0.64, blue: 0.31)
        case .waiting: return Color(red: 0.93, green: 0.71, blue: 0.18)
        case .error:   return Color(red: 0.86, green: 0.27, blue: 0.27)
        case .idle:    return Color(white: 0.55)
        case .dead, .exited: return Color(white: 0.30)
        }
    }

    var label: String {
        switch self {
        case .running: return "running"
        case .waiting: return "waiting"
        case .error:   return "error"
        case .idle:    return "idle"
        case .dead:    return "ended"
        case .exited:  return "exited"
        }
    }
}
