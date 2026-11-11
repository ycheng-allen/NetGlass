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
    enum Kind { case attention, review, context }
    var id: String
    var title: String
    var detail: String
    var icon: String
    var kind: Kind
}

extension IPAssessmentResult {
    var claudeRiskClues: [ClaudeRiskClue] {
        var clues: [ClaudeRiskClue] = []
        if let data = checkedIP {
            if data.directHits > 0 { clues.append(.init(id: "lists", title: "地址存在名单记录", detail: "\(data.directHits) 项地址级命中；属于第三方信誉线索，需要核对名单用途与时效。", icon: "exclamationmark.shield.fill", kind: .attention)) }
            if data.risk?.factors?.contains(where: { $0.id == "botnet-c2" }) == true { clues.append(.init(id: "abuse", title: "僵尸网络来源记录", detail: "来源标记 botnet-c2，请优先核查地址是否被复用或存在历史滥用。", icon: "ant.fill", kind: .attention)) }
            if data.risk?.is_tor == true || data.risk?.is_proxy == true || data.risk?.is_vpn == true || data.risk?.is_relay == true {
                clues.append(.init(id: "anon", title: "匿名／中继出口线索", detail: data.networkIdentity.name + "；可作为访问验证问题的排查项，不能据此认定账号违规。", icon: "lock.shield.fill", kind: .review))
            }
            if data.type?.type == "datacenter" || data.risk?.is_datacenter == true {
                clues.append(.init(id: "hosting", title: "机房／云网络出口", detail: "托管属性可能意味着共享出口；不等于已被 Claude 屏蔽，也不能证明账号会被封禁。", icon: "server.rack", kind: .review))
            }
            if data.checkedLists == 0 || data.reputation.completed < 3 { clues.append(.init(id: "missing", title: "部分信誉检查缺失", detail: "缺失项不能视作通过，建议重新评估或查看来源详情。", icon: "questionmark.diamond", kind: .review)) }
        } else { clues.append(.init(id: "missing", title: "信誉资料尚未取得", detail: "等待或重新获取 CheckMyIP 指定地址数据。", icon: "questionmark.circle", kind: .review)) }
        if let country = claudeCountry, rules?.restricted[country.uppercased()] != nil {
            clues.append(.init(id: "region", title: "地区限制参考线索", detail: "参考站规则标记该出口地区受限；请以当前官方支持地区为准。", icon: "globe.badge.chevron.backward", kind: .review))
        }
        if let ip = exits.first(where: { $0.name == "Claude" })?.ip, udp.contains(where: { $0 != ip }) {
            clues.append(.init(id: "path", title: "HTTP 与 UDP 出口不同", detail: "说明观测路径存在差异，需核对预期分流；不是封号判断。", icon: "arrow.triangle.branch", kind: .context))
        }
        let environment = checkMyIPBrowser?.checks?.filter { ["dns", "webrtc", "tz", "lang", "fp", "ua"].contains($0.id) && ["bad", "warn"].contains($0.state) } ?? []
        if !environment.isEmpty {
            clues.append(.init(id: "browser", title: "源站现场环境提示", detail: "CheckMyIP 的浏览器检查提示 \(environment.count) 项环境问题，详情见现场检查明细；这是环境观测，不是 Claude 封号依据。", icon: "macwindow.badge.plus", kind: .context))
        }
        return clues
    }
}
