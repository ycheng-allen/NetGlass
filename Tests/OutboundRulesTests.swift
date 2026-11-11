import Foundation

let now = Date()
let app = "com.example.app"
let block = OutboundRule(app: app, target: "*", action: .block, created: now.addingTimeInterval(-10))
let once = OutboundRule(app: app, target: "api.example.com", action: .once, created: now)
let temporary = OutboundRule(app: app, target: "192.0.2.1", action: .tenMinutes, created: now)
var consumed = Set<String>()
func permits(_ rules: [OutboundRule], app identifier: String = app, ip: String = "192.0.2.1", hostname: String? = nil, date: Date = now) -> Bool {
    OutboundDecision.allows(rules: rules, app: identifier, ip: ip, hostname: hostname, now: date, consumed: &consumed)
}
assert(!permits([block]))
assert(permits([block], app: "com.other.app"))
assert(permits([block, once], hostname: "api.example.com"))
assert(!permits([block, once], hostname: "api.example.com"))
assert(!permits([block, once], hostname: "other.example.com"))
assert(permits([temporary]))
assert(!permits([temporary], date: now.addingTimeInterval(601)))
let wildcard = OutboundRule(app: app, target: "*.example.com", action: .block)
assert(!permits([wildcard], hostname: "api.example.com"))
assert(permits([wildcard], hostname: "badexample.com"))
assert(permits([wildcard], hostname: nil))
let encoded = try JSONEncoder().encode(consumed)
consumed = try JSONDecoder().decode(Set<String>.self, from: encoded)
assert(!permits([once], hostname: "api.example.com"))
print("PASS outbound rules: app isolation, one-time grants, expiry, wildcard boundaries, durable consumption")
