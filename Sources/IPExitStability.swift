import Foundation

struct IPExitStability {
    static let window: TimeInterval = 3600
    static let changeThreshold = 3
    var sampleCount: Int
    var hostingChanges: Int
    var distinctHostingIPs: Int

    static func confirmedHosting(_ snapshot: IPAssessmentResult) -> Bool {
        guard snapshot.networkType.kind == .hosting else { return false }
        let risk = snapshot.risk
        let strongTypes = ["hosting", "datacenter", "cdn"]
        return risk?.is_datacenter == true || strongTypes.contains(risk?.company_type?.lowercased() ?? "")
            || strongTypes.contains(risk?.asnKind?.lowercased() ?? "") || snapshot.checkedIP?.risk?.is_datacenter == true
            || (snapshot.checkedIP?.type?.confidence == "high" && strongTypes.contains(snapshot.checkedIP?.type?.type ?? "")
                && snapshot.checkedIP?.type?.source?.hasPrefix("heuristic:") != true)
    }

    static func analyze(current: IPAssessmentResult, history: [IPAssessmentResult]) -> Self {
        let cutoff = current.date.addingTimeInterval(-window)
        var seen: Set<UUID> = []
        let samples = ([current] + history).filter { snapshot in
            snapshot.date >= cutoff && snapshot.date <= current.date && seen.insert(snapshot.id).inserted
                && snapshot.exits.first(where: { $0.name == "Claude" })?.ip.flatMap(IPsumFeed.canonical) != nil
        }.sorted { $0.date < $1.date }
        var changes = 0
        var addresses: Set<String> = []
        var previous: String?
        for sample in samples {
            guard confirmedHosting(sample), let ip = sample.exits.first(where: { $0.name == "Claude" })?.ip.flatMap(IPsumFeed.canonical) else {
                previous = nil
                continue
            }
            addresses.insert(ip)
            if let previous, previous != ip { changes += 1 }
            previous = ip
        }
        return .init(sampleCount: samples.count, hostingChanges: changes, distinctHostingIPs: addresses.count)
    }

    func clue(current: IPAssessmentResult) -> ClaudeRiskClue? {
        guard Self.confirmedHosting(current), hostingChanges >= Self.changeThreshold else { return nil }
        return .init(id: "hosting-churn", title: "机房 IP 频繁切换",
                     detail: "最近 1 小时的 \(sampleCount) 次有效评估中，连续机房记录发生 \(hostingChanges) 次地址切换，涉及 \(distinctHostingIPs) 个机房 IP。可核对负载均衡及节点策略；仅反映本地采样，不证明 Claude 已限速或触发风控。家宽偶尔换 IP 不按此规则提醒。",
                     icon: "arrow.triangle.swap", kind: .critical, evidence: .environment)
    }
}

extension IPRiskDetails {
    var trafficProfile: String? {
        if signals?["is_public_service"] == true { return "公共服务／任播类型" }
        if is_crawler == true { return "来源标记为爬虫／机器人" }
        if is_datacenter == true { return "托管网络类型" }
        if signals?["is_mobile"] == true { return "移动接入类型" }
        if isResidential == true { return "住宅接入类型" }
        return nil
    }
}
