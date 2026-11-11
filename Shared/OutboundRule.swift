import Foundation

struct OutboundRule: Codable, Identifiable {
    enum Action: String, Codable, CaseIterable {
        case block = "始终阻止", once = "允许一次", tenMinutes = "允许十分钟"
    }
    var id = UUID()
    var app: String
    var target: String
    var action: Action
    var created = Date()
    var expires: Date? { action == .tenMinutes ? created.addingTimeInterval(600) : nil }

    func matches(app identifier: String, ip: String, hostname: String?, now: Date) -> Bool {
        guard app == identifier else { return false }
        let value = target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "*" { return true }
        if value == ip.lowercased() { return true }
        guard let host = hostname?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else { return false }
        if value.hasPrefix("*.") {
            let suffix = String(value.dropFirst(2))
            return host.hasSuffix("." + suffix)
        }
        return host == value
    }
}

// Newer matching rules override older rules, including broader app rules.
enum OutboundDecision {
    static func allows(rules: [OutboundRule], app: String, ip: String, hostname: String?, now: Date, consumed: inout Set<String>) -> Bool {
        for rule in rules.sorted(by: { $0.created > $1.created }) where rule.matches(app: app, ip: ip, hostname: hostname, now: now) {
            switch rule.action {
            case .block: return false
            case .tenMinutes: return now < rule.expires!
            case .once: return consumed.insert(rule.id.uuidString).inserted
            }
        }
        return true
    }
}
