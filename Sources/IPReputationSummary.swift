import Foundation

struct IPReputationEstimate {
    struct Component: Identifiable {
        var id: String
        var title: String
        var deduction: Int?
        var detail: String
    }
    var components: [Component]
    var completed: Int { components.filter { $0.deduction != nil }.count }
    var value: Int? { completed >= 2 ? max(0, 100 - components.compactMap(\.deduction).reduce(0, +)) : nil }
    var band: String {
        guard let value else { return "资料不足" }
        switch value { case 90...100: return "优秀"; case 75..<90: return "良好"; case 55..<75: return "一般"; case 35..<55: return "较差"; default: return "高风险线索" }
    }
}

extension CheckMyIPResponse {
    var validRiskScore: Int? { risk?.score.flatMap { (0...100).contains($0) ? $0 : nil } }
    var networkIdentity: (name: String, icon: String, detail: String) {
        if risk?.is_tor == true { return ("Tor 出口", "network.badge.shield.half.filled", "Tor 列表标记") }
        if risk?.is_relay == true { return ("iCloud Private Relay", "cloud.fill", "Apple 中继出口标记") }
        if risk?.is_proxy == true {
            return type?.type == "residential" ? ("住宅代理线索", "house.lodge.fill", "住宅归类与代理标记同时存在") : ("代理出口", "arrow.triangle.branch", "代理标记")
        }
        if risk?.is_vpn == true { return ("VPN 出口", "lock.shield.fill", "VPN 标记") }
        switch type?.type {
        case "datacenter", "hosting": return ("机房／云网络", "server.rack", type?.source ?? "网络归类")
        case "residential": return ("住宅网络", "house.fill", "住宅归类，不能证明无代理")
        case "mobile": return ("移动网络", "antenna.radiowaves.left.and.right", "移动网络归类")
        case "business": return ("企业网络", "building.2.fill", "企业网络归类")
        case "education": return ("教育网络", "graduationcap.fill", "教育网络归类")
        case "isp": return ("运营商网络", "network", "无法仅凭 ISP 确认家宽")
        default:
            if risk?.is_datacenter == true { return ("机房／云网络", "server.rack", "数据中心名单标记") }
            return ("身份待确认", "questionmark.circle", "未标记匿名工具不代表直连")
        }
    }
    var reputation: IPReputationEstimate {
        let listPenalty = checkedLists > 0 ? min(45, directHits > 0 ? 25 + (directHits - 1) * 10 : 0) : nil
        let factors = risk?.factors
        let botnet = factors?.contains { $0.id == "botnet-c2" } == true
        let openProxy = factors?.contains { $0.id == "proxy" } == true
        let abusePenalty: Int? = factors.flatMap { _ in (mode == "full" || botnet || openProxy) ? min(45, (botnet ? 40 : 0) + (openProxy ? 20 : 0)) : nil }
        var penalty: Int?
        var identity = type?.type ?? "unknown"
        var confidence = type?.confidence
        if risk?.is_tor == true { identity = "tor"; confidence = "high" }
        else if risk?.is_proxy == true { identity = "proxy"; confidence = "high" }
        else if risk?.is_vpn == true || risk?.is_relay == true { identity = "vpn"; confidence = "high" }
        else if risk?.is_datacenter == true { identity = "datacenter"; confidence = "high" }
        let weights = ["tor": 30, "proxy": 25, "residential_proxy": 25, "vpn": 15, "datacenter": 15, "hosting": 15,
                       "mobile": 0, "residential": 0, "business": 0, "education": 0, "isp": 0, "broadband": 0]
        if let weight = weights[identity] {
            if weight == 0 { penalty = 0 }
            else if let confidence, let multiplier = ["high": 1.0, "medium": 0.75, "low": 0.5][confidence] {
                penalty = Int((Double(weight) * multiplier).rounded())
            }
        }
        return IPReputationEstimate(components: [
            .init(id: "lists", title: "地址名单", deduction: listPenalty, detail: checkedLists > 0 ? "\(directHits) 项命中／\(checkedLists) 项已完成；网段与 ASN 项不计分" : "名单核查未完成"),
            .init(id: "abuse", title: "滥用线索", deduction: abusePenalty, detail: factors == nil ? "来源未提供完整滥用线索" : (botnet || openProxy ? "Feodo／开放代理来源线索" : "来源未标记僵尸网络或开放代理")),
            .init(id: "identity", title: "网络身份", deduction: penalty, detail: networkIdentity.name + " · " + (confidence ?? "置信度未知"))
        ])
    }
}

struct ClaudeRiskClue: Identifiable {
    enum Kind { case critical, attention, review, context }
    enum Evidence: String {
        case officialRule = "官方规则关联"
        case reputation = "第三方信誉"
        case environment = "环境观测"
        case reference = "第三方地区参考"
    }
    var id: String
    var title: String
    var detail: String
    var icon: String
    var kind: Kind
    var evidence: Evidence = .reputation
    var sourceURL: String?
}

extension IPAssessmentResult {
    var claudeRiskClues: [ClaudeRiskClue] {
        var clues: [ClaudeRiskClue] = []
        if let data = checkedIP {
            if data.directHits > 0 {
                clues.append(.init(id: "lists", title: "地址存在名单记录", detail: "\(data.directHits) 份 DNS 黑名单收录了本次出口地址。展开 IP 情报可查看名单名称和查询时间。", icon: "exclamationmark.shield.fill", kind: .attention, sourceURL: "https://checkmyip.com/zh-cn/methodology"))
            }
            if data.risk?.factors?.contains(where: { $0.id == "botnet-c2" }) == true {
                clues.append(.init(id: "abuse", title: "僵尸网络来源记录", detail: "CheckMyIP 将此地址关联到僵尸网络控制服务器。地址可能已重新分配，记录描述的是出口历史。", icon: "ant.fill", kind: .attention, sourceURL: "https://checkmyip.com/zh-cn/methodology"))
            }
        }
        if let ip = exits.first(where: { $0.name == "Claude" })?.ip, let canonical = IPsumFeed.canonical(ip),
           let observation = ipsum, IPsumFeed.canonical(observation.ip ?? "") == canonical,
           observation.error == nil, let count = observation.occurrences, count > 0 {
            clues.append(.init(id: "ipsum", title: "IPsum 收录此出口", detail: "来源显示 \(count) 份名单收录了本次出口地址。IPsum 汇总多个来源，可在 IP 情报中查看名单的更新时间。", icon: "list.bullet.rectangle", kind: .attention, sourceURL: "https://github.com/stamparm/ipsum"))
        }
        let anonymous = ["VPN", "代理 Proxy", "Tor", "Private Relay"].filter { combinedRisk($0) == true }
        if !anonymous.isEmpty {
            clues.append(.init(id: "anon", title: "出口被标记为匿名或中继网络", detail: "地址资料标记了 \(anonymous.joined(separator: "、"))。流量可能与其他用户共用出口，其历史信誉也可能影响这次查询结果。", icon: "lock.shield.fill", kind: .review))
        }
        if networkType.kind == .hosting {
            let detail = IPExitStability.confirmedHosting(self)
                ? "来源将当前出口归类为机房／托管网络。此类地址可能由多个用户或服务共享，其信誉会受历史使用影响。NetGlass 会继续比对本地评估历史，频繁换出口时升级提醒。"
                : "来源根据网络名称推断当前出口可能为机房网络。类型尚待核实，建议结合运营商信息查看。"
            clues.append(.init(id: "hosting", title: IPExitStability.confirmedHosting(self) ? "机房 IP 使用风险" : "疑似机房 IP 使用风险",
                               detail: detail, icon: "server.rack", kind: .review))
        }
        if let ip = exits.first(where: { $0.name == "Claude" })?.ip.flatMap(IPsumFeed.canonical),
           let risk, risk.ip.flatMap(IPsumFeed.canonical) == ip {
            let level = risk.abuseLevel?.lowercased()
            if risk.is_abuser == true || ["high", "very high", "critical"].contains(level) {
                let observation = risk.is_abuser == true ? "Net.Coffee 对这个地址返回了滥用标记" : "Net.Coffee 将这个地址的滥用等级列为 \(level ?? "")"
                clues.append(.init(id: "address-abuse", title: "出口有滥用信誉记录", detail: observation + "。记录可能来自过去使用同一地址的人，可在 IP 情报中查看原始指标。", icon: "exclamationmark.shield", kind: .attention))
            }
        }
        if let assessment = regionAssessment, assessment.countryCode == claudeCountry?.uppercased(), assessment.status == .unlisted {
            clues.append(.init(id: "region", title: "出口地区未列入支持范围", detail: "本次定位地区（\(assessment.countryCode ?? "")）未出现在当前生效的支持列表中，可能影响服务可用性。这里只观测到网络出口。", icon: "globe", kind: .attention, evidence: .officialRule))
        }
        clues.append(contentsOf: environmentRiskClues)
        return clues
    }
}
