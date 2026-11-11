import Foundation

// Preserve provider evidence and scores; reputation is separately reproduced from its public formula.
struct CheckMyIPResponse: Codable {
    var ip: String
    var hostname: String?
    var schema_version: String?
    var hosted_domains: HostedDomains?
    var mode: String?
    var cache: String?
    var generated_at: String?
    var network: Network?
    var type: Identity?
    var geo: Geography?
    var risk: Risk?

    struct Network: Codable {
        var asn: Int?
        var as_name: String?
        var as_org: String?
        var prefix: String?
        var rir: String?
        var registry_country: String?
        var multi_origin: Bool?
        var note: String?
        var origins: [Origin]?
    }
    struct Origin: Codable {
        var asn: Int?
        var as_name: String?
        var as_org: String?
        var named_by: [String]?
        var prefix_count: Int?
        var address_count_v4: Int?
        var primary: Bool?
    }
    struct HostedDomains: Codable {
        var status: String?
        var total_domains: Int?
        var source: String?
        var freshness: String?
        var error: String?
        var retry_after: String?
    }
    struct Identity: Codable {
        var type: String?
        var source: String?
        var confidence: String?
        var reasons: [String]?
        var title: String {
            let names = ["datacenter": "机房 IP", "hosting": "机房 IP", "residential": "住宅网络", "mobile": "移动网络", "isp": "运营商网络", "business": "企业网络", "education": "教育网络"]
            return type.flatMap { names[$0] } ?? "属性待确认"
        }
    }
    struct Geography: Codable {
        var consensus: Consensus?
        var sources: [Source]?
    }
    struct Consensus: Codable {
        var country: String?
        var region: String?
        var city: String?
        var timezone: String?
        var timezone_source: String?
        var agreement_count: Int?
        var source_count: Int?
        var city_agreement_count: Int?
        var spread_km: Double?
        var anycast: Bool?
        var disagreement: Bool?
        var notes: [String]?
        var countryVoteSummary: String {
            guard let agreement_count, let source_count, source_count > 0 else { return "来源数量未知" }
            return "\(agreement_count) / \(source_count) 个来源一致"
        }
    }
    struct Source: Codable, Identifiable {
        var id: String
        var name: String?
        var kind: String?
        var country: String?
        var region: String?
        var city: String?
        var updated: String?
        var freshness: String?
        var licence: String?
    }
    struct Risk: Codable {
        var score: Int?
        var level: String?
        var reasons: [String]?
        var blacklist_hits: Int?
        var blacklists_checked: Int?
        var is_proxy: Bool?
        var is_vpn: Bool?
        var is_tor: Bool?
        var is_datacenter: Bool?
        var is_relay: Bool?
        var blacklists: [Blocklist]?
        var factors: [Factor]?
    }
    struct Factor: Codable {
        var id: String?
        var label: String?
        var points: Int?
        var source: String?
    }
    struct Blocklist: Codable, Identifiable {
        var list: String
        var name: String?
        var listed: Bool?
        var informational: Bool?
        var checked_at: String?
        var error: String?
        var id: String { list }
        var checked: Bool { listed != nil && checked_at != nil && error == nil }
        var status: String {
            guard checked else { return "未完成／未知" }
            if informational == true { return listed == true ? "网段／ASN 关联命中" : "网段／ASN 未命中" }
            return listed == true ? "地址命中" : "地址未命中"
        }
    }
    var directLists: [Blocklist] { (risk?.blacklists ?? []).filter { $0.informational == false } }
    var checkedLists: Int { directLists.filter(\.checked).count }
    var directHits: Int { directLists.filter { $0.checked && $0.listed == true }.count }

    static func validated(_ data: Data, requestedIP: String) throws -> Self {
        let response = try JSONDecoder().decode(Self.self, from: data)
        guard let expected = IPsumFeed.canonical(requestedIP), IPsumFeed.canonical(response.ip) == expected else {
            throw NSError(domain: "CheckMyIP", code: 1, userInfo: [NSLocalizedDescriptionKey: "返回地址与 Claude 出口不一致，已忽略该结果"])
        }
        guard response.network != nil || response.geo != nil || response.risk != nil || response.type != nil else { throw URLError(.cannotParseResponse) }
        return response
    }
}

struct CheckMyIPObservation: Codable {
    var requestedIP: String?
    var checkedAt: Date
    var response: CheckMyIPResponse?
    var error: String?
}

extension IPAssessmentHTTP {
    func checkMyIP(ip: String?) async -> CheckMyIPObservation {
        guard let ip, Self.validIP(ip) else { return CheckMyIPObservation(checkedAt: Date(), error: "Claude 出口未知，无法查询") }
        do {
            var url = URLComponents(string: "https://checkmyip.com/json")!
            url.queryItems = [URLQueryItem(name: "ip", value: ip), URLQueryItem(name: "mode", value: "full")]
            let response = try CheckMyIPResponse.validated(await data(url.string!), requestedIP: ip)
            return CheckMyIPObservation(requestedIP: ip, checkedAt: Date(), response: response)
        } catch { return CheckMyIPObservation(requestedIP: ip, checkedAt: Date(), error: error.localizedDescription) }
    }
}

extension IPAssessmentResult {
    var checkedIP: CheckMyIPResponse? { checkMyIP?.response }
    var locationCity: String? { checkedIP?.geo?.consensus?.city ?? risk?.city }
    var locationRegion: String? { checkedIP?.geo?.consensus?.region ?? risk?.region }
    var locationTimezone: String? { checkedIP?.geo?.consensus?.timezone ?? risk?.timezone }
    var locationASN: Int? { checkedIP?.network?.asn ?? risk?.asn }
    var locationOrganization: String? { checkedIP?.network?.as_org ?? checkedIP?.network?.as_name ?? risk?.asOrganization ?? risk?.company_name }
    func riskValues(_ key: String) -> (Bool?, Bool?) {
        switch key {
        case "VPN": return (risk?.is_vpn, checkedIP?.risk?.is_vpn)
        case "代理 Proxy": return (risk?.is_proxy, checkedIP?.risk?.is_proxy)
        case "Tor": return (risk?.is_tor, checkedIP?.risk?.is_tor)
        case "Private Relay": return (risk?.signals?["is_relay"], checkedIP?.risk?.is_relay)
        default: return (nil, nil)
        }
    }
    func combinedRisk(_ key: String) -> Bool? {
        let (first, second) = riskValues(key)
        if first == true || second == true { return true }
        return first ?? second
    }
    func riskSourceSummary(_ key: String) -> String {
        let (first, second) = riskValues(key)
        func label(_ value: Bool?) -> String { value.map { $0 ? "已标记" : "未标记" } ?? "未知" }
        return "Net.Coffee：\(label(first)) · CheckMyIP：\(label(second))" + (first != nil && second != nil && first != second ? " · 来源有差异" : "")
    }
}

extension IPRiskDetails {
    // Net.Coffee can return a cached subnet representative rather than this IP.
    // Network ownership remains a clue; address-specific intelligence cannot transfer.
    func scoped(to requestedIP: String) throws -> (IPRiskDetails, String?) {
        if let ip, let canonical = IPsumFeed.canonical(ip), canonical == IPsumFeed.canonical(requestedIP) { return (self, nil) }
        guard let cidr, IPAssessmentHTTP.contains(cidr, ip: requestedIP) else { throw URLError(.cannotParseResponse) }
        var network = self
        network.is_vpn = nil
        network.is_proxy = nil
        network.is_tor = nil
        network.is_crawler = nil
        network.is_abuser = nil
        network.signals = signals?.filter { $0.key == "is_mobile" }
        network.evidence = nil
        network.reverseDNS = nil
        return (network, "Net.Coffee 返回同网段的代表记录；地址级 VPN、代理、Tor、爬虫与滥用标记已忽略。归属和网络分类仅作网段参考。")
    }
}

extension IPAssessmentResult {
    func audited() -> Self {
        var snapshot = self
        if let record = risk, record.ip != nil || record.cidr != nil, let requestedIP = exits.first(where: { $0.name == "Claude" })?.ip {
            if let scoped = try? record.scoped(to: requestedIP) {
                snapshot.risk = scoped.0
                snapshot.riskSourceNote = scoped.1 ?? riskSourceNote
            } else {
                snapshot.risk = nil
                snapshot.riskSourceNote = "历史记录的属性地址无法与 Claude 出口匹配，已忽略，请重新评估。"
            }
        }
        if !dns.isEmpty {
            snapshot.dnsMessage = IPAssessmentHTTP.dnsMessage(dns, claudeCountry: snapshot.claudeCountry)
        }
        return snapshot
    }
}

struct CheckMyIPBrowserObservation: Codable {
    var checkedAt: Date
    var ip: String?
    var browserScore: Int?
    var ipScore: Int?
    var overallScore: Int?
    var identity: String?
    var summary: String?
    var checks: [Check]?
    var error: String?
    struct Check: Codable, Identifiable {
        var id: String
        var state: String
        var text: String
    }
    func matches(_ ip: String?) -> Bool {
        guard let own = self.ip, let ip, let normalized = IPsumFeed.canonical(own) else { return false }
        return normalized == IPsumFeed.canonical(ip)
    }
}
