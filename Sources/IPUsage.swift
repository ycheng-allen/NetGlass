import Foundation

struct IPUsageRadar: Codable {
    var asn: Int?
    var ok: Bool?
    var human: Double?
    var range: String?
    var fetched_at: Double?
    var cached: Bool?
    var stale: Bool?

    var validHuman: Double? {
        guard ok == true, let human, human.isFinite, (0...100).contains(human) else { return nil }
        return human
    }
}

extension IPAssessmentHTTP {
    func usageRadar(asn: Int?) async -> IPUsageRadar? {
        guard let asn, asn > 0,
              let observation = try? await json(IPUsageRadar.self, "https://ip.net.coffee/api/ipv2/radar/\(asn)"),
              observation.asn == asn, observation.validHuman != nil else { return nil }
        return observation
    }
}

struct IPUsageScene: Identifiable {
    var id: String
    var name: String
    var score: Int
    var verdict: String
}

/// Mirrors Net.Coffee's public usage heuristics. The scores describe source estimates.
extension IPAssessmentResult {
    var usageDetails: IPRiskDetails? {
        guard let risk, let queried = exits.first(where: { $0.name == "Claude" })?.ip.flatMap(IPsumFeed.canonical),
              risk.ip.flatMap(IPsumFeed.canonical) == queried else { return nil }
        return risk
    }

    var usageNative: (country: String, registration: String, same: Bool)? {
        guard let d = usageDetails, d.signals?["is_public_service"] != true,
              let country = d.countryCode?.uppercased(), country.count == 2,
              let registration = d.registeredCountry?.uppercased(), registration.count == 2 else { return nil }
        return (country, registration, country == registration)
    }

    var usageHuman: (percent: Double, source: String)? {
        guard let d = usageDetails, d.ip?.contains(":") == false else { return nil }
        var human: Double
        var note: String
        if let radar = usageRadar, radar.asn == d.asn, let measured = radar.validHuman {
            human = measured
            note = "ASN \(radar.range == "28d" ? "近 28 天" : radar.range ?? "")统计 · 按 IP 标记调整"
            if radar.stale == true { note += " · 来源缓存已过期" }
        } else {
            let type = d.company_type?.lowercased(), kind = d.asnKind?.lowercased()
            if d.signals?["is_public_service"] == true { human = 2 }
            else if d.is_crawler == true { human = 6 }
            else if d.signals?["is_mobile"] == true || kind == "mobile" { human = 93 }
            else if usageHosting(d) { human = 18 }
            else if type == "business" { human = 65 }
            else if d.isResidential == true || type == "isp" { human = 88 }
            else { return nil }
            note = "Net.Coffee 类型规则估算"
        }
        if d.is_tor == true { human *= 0.4 }
        else if d.is_proxy == true || d.is_vpn == true { human *= 0.6 }
        if d.is_crawler == true { human = min(human, human * 0.3 + 2) }
        if d.is_abuser == true { human -= 5 }
        return (max(1, min(99, human)), note)
    }

    private func usageHosting(_ d: IPRiskDetails) -> Bool {
        d.is_datacenter == true || d.company_type == "hosting" || ["hosting", "cdn"].contains(d.asnKind ?? "")
    }

    var usageScenes: [IPUsageScene] {
        guard let d = usageDetails, d.ip?.contains(":") == false,
              let trust = d.sceneTrustScore, trust.isFinite, (0...100).contains(trust),
              let cc = d.countryCode?.uppercased(), cc.count == 2 else { return [] }
        let dc = usageHosting(d)
        let native = usageNative
        let human = !dc && d.is_crawler != true && d.signals?["is_public_service"] != true
        let proxy = d.is_proxy == true || d.is_vpn == true || d.is_tor == true
        let abuse: Double
        if let raw = d.abuseScoreRaw?.split(whereSeparator: \.isWhitespace).first.flatMap({ Double($0) }), raw.isFinite {
            abuse = raw > 0.05 ? 2 : raw > 0.025 ? 1 : raw > 0.01 ? 0.5 : 0
        } else {
            let level = d.abuseLevel?.lowercased() ?? ""
            abuse = ["high", "very_high", "veryhigh"].contains(level) ? 2 : level == "elevated" ? 1 : 0
        }
        let hp = d.honeypotThreat ?? 0
        let honeypot: Double = hp > 0 ? (hp <= 25 ? 1 : 2) : 0
        let risky = d.is_abuser == true || abuse > 0 || honeypot > 0 || d.is_crawler == true || proxy
        let blocked = [
            "tiktok": ["CN","HK","IN","IR","AF","KP","JO","SO","SN","KG","UZ"],
            "social": ["CN","IR","KP","TM"],
            "ai": ["CN","RU","BY","IR","KP","CU","SY","AF"]
        ]
        let partial = ["tiktok": [], "social": ["RU","MM"], "ai": ["HK","MO","VE","MM"]]
        return [("tiktok", "TikTok"), ("social", "社媒运营"), ("ai", "AI 应用")].map { kind, name in
            var score = floor(trust / 10 + 0.5)
            if native?.same == true { score += 0.5 }
            if human { score += 0.5 }
            if d.company_type == "business" { score -= 0.5 }
            if dc { score -= kind == "ai" ? 2 : 3 }
            if native?.same == false { score -= 1 }
            if proxy { score -= kind == "ai" ? 2 : 3 }
            if d.is_abuser == true { score -= kind == "ai" ? 0.5 : 1 }
            score -= abuse + honeypot
            if d.is_crawler == true { score -= 0.5 }
            score = max(0, min(10, floor(score + 0.5)))
            if risky { score = min(9, score) }
            if blocked[kind]?.contains(cc) == true {
                return .init(id: kind, name: name, score: 0, verdict: "地区不可用")
            }
            if partial[kind]?.contains(cc) == true {
                return .init(id: kind, name: name, score: Int(min(5, score)), verdict: "部分可用")
            }
            let verdict = score >= 10 ? "极佳" : score >= 8 ? "推荐" : score >= 5 ? (kind == "ai" ? "可以尝试" : "可用") : "不推荐"
            return .init(id: kind, name: name, score: Int(score), verdict: verdict)
        }
    }
}
