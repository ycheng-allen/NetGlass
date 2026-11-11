import Foundation
import AppKit

// Isolate regression tests from the user's saved monitoring history.
enum Store {
    static var data: [String: Data] = [:]
    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        data[name].flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
    static func save<T: Encodable>(_ value: T, _ name: String) { data[name] = try! JSONEncoder().encode(value) }
    static func remove(_ name: String) { data.removeValue(forKey: name) }
}
enum Shell {
    static func run(_ path: String, _ args: [String]) -> (out: String, err: String, code: Int32) { ("", "", 1) }
}
enum NetUtil {
    static func primaryInterface() -> (name: String, ip: String, mask: String)? { nil }
    static func defaultGateway() -> String? { nil }
}
enum Fmt {
    static func speed(_ value: Double) -> String { "\(value) B/s" }
}
final class AppIdentity {
    static let shared = AppIdentity()
    func meta(for key: String) -> AppMeta { AppMeta(key: key, name: key, icon: nil, bundlePath: nil, isSystem: false) }
}
final class AlertCenter {
    var alerts: [AppAlert] = []
    func add(_ type: AlertType, title: String, detail: String) {
        alerts.append(AppAlert(type: type, title: title, detail: detail, date: Date()))
    }
}
final class AppState {
    let store = TrafficStore()
    let alertCenter = AlertCenter()
}

let insights = NetworkInsights()
let alerts = AlertCenter()
let first = ("app", "App", "127.0.0.1:1000->192.0.2.1:443", "TCP")
let second = ("app", "App", "127.0.0.1:1001->192.0.2.1:443", "TCP")
insights.recordConnections([first], alert: alerts, enabled: false)
assert(insights.connections.count == 1 && insights.connections[0].ended == nil)
let firstID = insights.connections[0].id
insights.recordConnections([first, second], alert: alerts, enabled: false)
assert(insights.connections.count == 2 && insights.connections[0].id == firstID)
insights.recordConnections([second], alert: alerts, enabled: false)
assert(insights.connections.first(where: { $0.id == firstID })?.ended != nil)
let restored = NetworkInsights()
assert(restored.connections.allSatisfy { $0.ended != nil })
assert(restored.connections.contains { $0.interrupted })
for _ in 0..<30 { insights.recordUploads(["app": (0, 0)], alert: alerts, enabled: false) }
insights.recordUploads(["app": (0, 1048576)], alert: alerts, enabled: true)
assert(alerts.alerts.count == 1 && alerts.alerts[0].title == "应用上传行为变化")
insights.recordUploads(["app": (0, 2097152)], alert: alerts, enabled: true)
assert(alerts.alerts.count == 1, "burst alerts must respect cooldown")
insights.resetHistory()
assert(insights.connections.isEmpty && insights.health.isEmpty && insights.usage.isEmpty)
assert(NetworkInsights().connections.isEmpty)
print("PASS connection lifecycle, parallel sockets, restart interruption, upload anomalies, cooldown, reset")
