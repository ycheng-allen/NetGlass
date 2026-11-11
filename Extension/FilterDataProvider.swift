import Foundation
import Network
import NetworkExtension
import Security

final class FilterDataProvider: NEFilterDataProvider {
    private let lock = NSLock()
    private var consumed = Set(UserDefaults.standard.stringArray(forKey: "consumed-rules") ?? [])

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        let settings = NEFilterSettings(rules: [], defaultAction: .filterData)
        apply(settings, completionHandler: completionHandler)
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard flow.direction == .outbound, let socket = flow as? NEFilterSocketFlow else { return .allow() }
        guard let token = flow.sourceAppAuditToken else { return .allow() }
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: token] as CFDictionary, [], &code) == errSecSuccess, let code else { return .allow() }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return .allow() }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let identifier = (information as? [String: Any])?[kSecCodeInfoIdentifier as String] as? String else { return .allow() }
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.allen.netglass")?.appendingPathComponent("rules.json"),
              let data = try? Data(contentsOf: url), let rules = try? JSONDecoder().decode([OutboundRule].self, from: data) else { return .allow() }
        var ip = ""
        if case let .hostPort(host, _) = socket.remoteFlowEndpoint { ip = "\(host)" }
        lock.lock()
        defer { lock.unlock() }
        let previous = consumed
        let allowed = OutboundDecision.allows(rules: rules, app: identifier, ip: ip, hostname: socket.remoteHostname, now: Date(), consumed: &consumed)
        if previous != consumed {
            UserDefaults.standard.set(Array(consumed), forKey: "consumed-rules")
            guard UserDefaults.standard.synchronize() else { return .drop() }
        }
        return allowed ? .allow() : .drop()
    }
}
