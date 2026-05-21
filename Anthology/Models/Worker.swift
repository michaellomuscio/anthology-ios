import Foundation

/// Mirror of a worker .md entry as returned by the Mac bridge's
/// `list_workers` response. `name` is the bare name (without the
/// `worker-` filename prefix); `fullName` is the actual subagent-name
/// the Mac side stores. Spawn-as-worker uses `name`.
struct Worker: Codable, Identifiable, Hashable {
    let name: String
    let fullName: String
    let description: String
    let category: String
    let emoji: String?
    let color: String?

    var id: String { fullName }
}

/// Mirror of a group as returned by `list_groups`. Groups are bench-style
/// folders on the Mac sidebar; iOS reads-only for v1.
///
/// Named SessionGroup (rather than Group) to avoid collision with SwiftUI's
/// own `Group` view container.
struct SessionGroup: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    var color: String?
    var collapsed: Bool?
    var createdAt: Double?
}
