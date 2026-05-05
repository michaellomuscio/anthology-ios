import Foundation

struct Schedule: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var cwd: String
    var prompt: String
    var color: String
    var tag: String
    var kind: String      // "cron" | "oneshot"
    var cron: String?
    var when: String?     // ISO datetime for oneshot
    var enabled: Bool
    var createdAt: Double?
    var lastRunAt: Double?
    var nextRunAt: Double?
}
