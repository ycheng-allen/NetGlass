import Foundation
import CryptoKit
import Darwin

struct IPRiskEvidence: Codable, Identifiable {
    var label: String
    var severity: String?
    var id: String { label }
}

private enum IPValue: Decodable {
    case text(String), number(Double), boolean(Bool), object([String: IPValue]), array([IPValue]), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let boolean = try? value.decode(Bool.self) { self = .boolean(boolean) }
        else if let text = try? value.decode(String.self) { self = .text(text) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let object = try? value.decode([String: IPValue].self) { self = .object(object) }
        else if let array = try? value.decode([IPValue].self) { self = .array(array) }
        else { self = .null }
    }
    var text: String? {
        switch self {
        case .text(let value): return value
        case .number(let value): return value.isFinite ? String(format: "%.0f", value) : nil
        default: return nil
        }
    }
    var bool: Bool? {
        switch self {
        case .boolean(let value): return value
        case .number(1): return true
        case .number(0): return false
        case .text(let value):
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default: return nil
        }
    }
    var object: [String: IPValue] { if case .object(let value) = self { return value }; return [:] }
    var array: [IPValue] { if case .array(let value) = self { return value }; return [] }
}

extension IPRiskDetails {
    var hasInformation: Bool {
        countryCode != nil || asn != nil || [isResidential, is_datacenter, is_vpn, is_proxy, is_tor, is_crawler, is_abuser].contains(where: { $0 != nil }) || signals?.isEmpty == false || evidence?.isEmpty == false
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: IPValue].self)
        let security = raw["security"]?.object ?? [:]
        let company = raw["company"]?.object ?? [:]
        let asnObject = raw["asn"]?.object ?? [:]
        func text(_ key: String) -> String? {
            guard let value = raw[key]?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        func flag(_ key: String) -> Bool? { raw[key]?.bool ?? security[key]?.bool }
        let asnText = text("asn") ?? asnObject["asn"]?.text ?? asnObject["number"]?.text
        self.init(
            ip: text("ip"),
            cidr: text("cidr"),
            country: text("country"),
            countryCode: text("countryCode") ?? text("country_code"),
            region: text("region"),
            city: text("city"),
            asn: asnText.flatMap { Int($0.uppercased().replacingOccurrences(of: "AS", with: "")) },
            asOrganization: text("asOrganization") ?? asnObject["org"]?.text,
            isResidential: flag("isResidential"),
            is_datacenter: flag("is_datacenter"),
            is_vpn: flag("is_vpn"),
            is_proxy: flag("is_proxy"),
            is_tor: flag("is_tor"),
            is_crawler: flag("is_crawler"),
            is_abuser: flag("is_abuser"),
            company_name: text("company_name") ?? company["name"]?.text,
            company_type: text("company_type") ?? company["type"]?.text,
            timezone: text("timezone")
        )
        let keys = ["is_relay", "is_mobile", "is_bogon", "isBroadcast", "is_satellite", "is_public_proxy", "is_residential_proxy", "is_anonymous", "is_spam", "is_attacker"]
        var signals = raw["signals"]?.object.compactMapValues { $0.bool } ?? [:]
        for key in keys { if let value = flag(key) { signals[key] = value } }
        self.signals = signals
        datacenterName = text("datacenterName") ?? text("datacenter_name")
        reverseDNS = text("reverseDNS") ?? text("rdns")
        asnKind = text("asnKind") ?? text("asn_kind")
        registeredCountry = text("registeredCountry") ?? text("registered_country")
        rpki = text("rpki") ?? text("rpki_status")
        let threats = raw["evidence"]?.array ?? raw["intelligence"]?.object["threats"]?.array ?? []
        evidence = threats.compactMap {
            guard let label = $0.object["label"]?.text, !label.isEmpty else { return nil }
            return IPRiskEvidence(label: label, severity: $0.object["severity"]?.text)
        }
    }
}

struct IPReferenceRules: Codable {
    var restricted: [String: String]
    var timezones: [String: String]
    var languages: [String: [String]]
    var version: String
    var fetchedAt: Date

    static func parse(_ source: String, date: Date = Date()) -> IPReferenceRules? {
        func body(_ name: String) -> String {
            guard let start = source.range(of: "const " + name + " = {"),
                  let end = source[start.upperBound...].range(of: "};") else { return "" }
            return String(source[start.upperBound..<end.lowerBound])
        }
        func strings(_ content: String) -> [String: String] {
            guard let regex = try? NSRegularExpression(pattern: #"'([A-Z]{2})'\s*:\s*'([^']+)'"#) else { return [:] }
            var result: [String: String] = [:]
            for match in regex.matches(in: content, range: NSRange(content.startIndex..., in: content)) {
                if let key = Range(match.range(at: 1), in: content), let value = Range(match.range(at: 2), in: content) { result[String(content[key])] = String(content[value]) }
            }
            return result
        }
        let restricted = strings(body("CLAUDE_RESTRICTED_CC"))
        let timezones = strings(body("CC_TO_TZ"))
        let languageBody = body("langMap")
        var languages: [String: [String]] = [:]
        if let regex = try? NSRegularExpression(pattern: #"'([A-Z]{2})'\s*:\s*\[([^\]]+)\]"#) {
            for match in regex.matches(in: languageBody, range: NSRange(languageBody.startIndex..., in: languageBody)) {
                guard let key = Range(match.range(at: 1), in: languageBody), let values = Range(match.range(at: 2), in: languageBody) else { continue }
                languages[String(languageBody[key])] = languageBody[values].split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " '\t\n\r\"")) }
            }
        }
        guard !restricted.isEmpty, !timezones.isEmpty, !languages.isEmpty else { return nil }
        let version = SHA256.hash(data: Data(source.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return IPReferenceRules(restricted: restricted, timezones: timezones, languages: languages, version: version, fetchedAt: date)
    }

    func region(_ code: String?) -> String {
        guard let code, code.count == 2 else { return "出口地区未知" }
        if let name = restricted[code.uppercased()] { return "参考站地区规则标记为受限 · " + name }
        return "参考站地区规则未标记受限 · " + code.uppercased()
    }
}

struct IPServiceResponse: Codable {
    struct Status: Codable { var description: String; var indicator: String? }
    struct Component: Codable, Identifiable { var id: String; var name: String; var status: String }
    struct Incident: Codable, Identifiable { var id: String; var name: String; var status: String; var shortlink: String? }
    var status: Status
    var components: [Component]?
    var incidents: [Incident]?
}

extension IPAssessmentHTTP {
    static func publicIP(_ ip: String) -> Bool {
        guard validIP(ip) else { return false }
        if ip.contains(":") {
            var bytes = [UInt8](repeating: 0, count: 16)
            if inet_pton(AF_INET6, ip, &bytes) == 1, bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
                return publicIP(bytes.suffix(4).map(String.init).joined(separator: "."))
            }
        }
        let reserved = ip.contains(":") ? ["::/128", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8", "2001:db8::/32"] : ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "198.18.0.0/15", "192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4"]
        return !reserved.contains { contains($0, ip: ip) }
    }

    func geography(_ exit: IPExit) async -> IPExit {
        guard let ip = exit.ip else { return exit }
        var output = exit
        do {
            output.geo = try await json(IPGeo.self, "https://ip.net.coffee/api/geoip/\(ip)")
            output.country = output.geo?.country_code ?? output.country
        } catch { output.geoError = error.localizedDescription }
        return output
    }

    static func udpMessage(_ addresses: [String], claudeIP: String?, error: String?) -> String {
        if let error { return "WebRTC 探测未完成 · " + error }
        guard !addresses.isEmpty else { return "未观察到公网 UDP 候选地址，无法判断是否泄露" }
        guard let claudeIP else { return "已取得 UDP 出口，Claude HTTP 出口未知，无法比较" }
        return addresses.contains(where: { $0 != claudeIP }) ? "存在与 Claude HTTP 不同的 UDP 出口，请核对分流" : "本次观察到的 UDP 与 Claude HTTP 出口一致"
    }
}

extension IPAssessmentResult {
    var claudeCountry: String? { checkedIP?.geo?.consensus?.country ?? risk?.countryCode ?? exits.first(where: { $0.name == "Claude" })?.country }
    var timezoneComparison: String {
        guard let localName = device["时区"], let local = TimeZone(identifier: localName) else { return "本地时区未知" }
        let sourceName = locationTimezone ?? rules?.timezones[claudeCountry?.uppercased() ?? ""]
        guard let sourceName, let remote = TimeZone(identifier: sourceName) else { return "Claude 出口时区未知" }
        let difference = remote.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
        let match = abs(difference) <= 3600
        let estimate = locationTimezone == nil ? "（参考地区估算）" : ""
        return "\(match ? "UTC 偏移相近" : "UTC 偏移不同") · \(localName) ↔ \(sourceName)\(estimate) · 相差 \(String(format: "%.1f", Double(abs(difference)) / 3600)) 小时"
    }
    var languageComparison: String {
        guard let primary = device["语言"]?.split(separator: ",").first?.trimmingCharacters(in: .whitespaces).split(separator: "-").first?.lowercased(),
              let accepted = rules?.languages[claudeCountry?.uppercased() ?? ""], !accepted.isEmpty else { return "缺少地区语言规则，无法比较" }
        return "\(accepted.contains(primary) ? "匹配参考地区语言" : "与参考地区常用语言不同") · 当地常用 \(accepted.joined(separator: " / "))"
    }
}

extension IPAssessmentHTTP {
    func geographies(_ exits: [IPExit]) async -> [IPExit] {
        var result = exits
        await withTaskGroup(of: (Int, IPExit).self) { group in
            let initialCount = min(6, exits.count)
            for index in 0..<initialCount { group.addTask { (index, await geography(exits[index])) } }
            var next = initialCount
            for await (index, exit) in group {
                result[index] = exit
                if next < exits.count {
                    let index = next
                    next += 1
                    group.addTask { (index, await geography(exits[index])) }
                }
            }
        }
        return result
    }

    static func dnsMessage(_ exits: [IPExit], claudeCountry: String?) -> String {
        guard !exits.isEmpty else { return "未取得 DNS 出口，无法判断是否泄露" }
        guard let claudeCountry else { return "Claude 出口地区未知，无法比较 DNS 出口" }
        if claudeCountry.uppercased() != "CN", exits.contains(where: { $0.country?.uppercased() == "CN" }) {
            return "DNS 与 Claude 出口地区不同 · 同时观察到中国大陆解析器，请核对预期分流"
        }
        if exits.contains(where: { $0.country != nil && $0.country?.uppercased() != claudeCountry.uppercased() }) { return "DNS 与 Claude 出口地区不同，请核对预期分流；地区差异本身不能证明泄露" }
        if exits.contains(where: { $0.country == nil }) { return "解析器地区信息不完整，无法完成地区比较" }
        return "已取得解析器观测；地区相同也不能证明 DNS 使用了预期路径"
    }
}
