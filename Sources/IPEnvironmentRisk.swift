import Foundation

extension IPAssessmentResult {
    /// Use time-zone offsets at the observation date so aliases and DST are handled.
    var observedTimezoneDifference: (local: String, remote: String, seconds: Int)? {
        guard let name = device["时区"], let local = TimeZone(identifier: name),
              let remoteName = locationTimezone, let remote = TimeZone(identifier: remoteName) else { return nil }
        return (name, remoteName, abs(local.secondsFromGMT(for: date) - remote.secondsFromGMT(for: date)))
    }

    var environmentRiskClues: [ClaudeRiskClue] {
        let guide = "https://ip.net.coffee/claude/claudecode.html"
        let methodology = "https://checkmyip.com/zh-cn/methodology"
        let claude = exits.first { $0.name == "Claude" }?.ip.flatMap(IPsumFeed.canonical)
        let site = checkMyIPBrowser
        func siteFlag(_ id: String) -> Bool {
            site?.visibleChecks.contains { $0.id == id && ["bad", "warn"].contains($0.state) } == true
        }
        let scope = site?.matches(claude) == true ? "CheckMyIP 现场出口与 Claude HTTP 出口一致。" : "该结果针对 CheckMyIP 页面出口，不代表 Claude 的实际请求路径。"
        var items: [ClaudeRiskClue] = []
        let publicUDP = Set(udp.filter(IPAssessmentHTTP.publicIP).compactMap(IPsumFeed.canonical))
        // Each address family has its own address. Compare like with like.
        let differentUDP = publicUDP.filter { $0 != claude && $0.contains(":") == claude?.contains(":") }
        if let claude, !differentUDP.isEmpty {
            let family = claude.contains(":") ? "IPv6" : "IPv4"
            items.append(.init(id: "webrtc", title: "WebRTC 与网页出口不同", detail: "WebKit 测到 \(differentUDP.count) 个 \(family) 公网 UDP 地址，与同协议族的 Claude 网页出口不同。使用 WebRTC 的服务可能看到另一个地址，可在下方查看 UDP 测量结果。", icon: "point.3.connected.trianglepath.dotted", kind: .review, evidence: .environment, sourceURL: guide))
        } else if let claude, let country = claudeCountry?.uppercased(), country.count == 2,
                  let other = udpExits?.first(where: { exit in
                      guard let ip = exit.ip.flatMap(IPsumFeed.canonical), publicUDP.contains(ip),
                            ip.contains(":") != claude.contains(":"), let code = exit.country, code.count == 2 else { return false }
                      return code.uppercased() != country
                  }), let remote = other.country {
            let family = other.ip?.contains(":") == true ? "IPv6" : "IPv4"
            items.append(.init(id: "webrtc", title: "双栈出口的定位地区不同", detail: "WebRTC 的 \(family) 出口定位在 \(remote)，Claude 网页出口定位在 \(country)。两个协议族可能采用不同路径，定位数据库也可能有误。", icon: "arrow.triangle.branch", kind: .review, evidence: .environment, sourceURL: guide))
        } else if (publicUDP.isEmpty || claude == nil), siteFlag("webrtc") {
            items.append(.init(id: "webrtc", title: "WebRTC UDP 泄露检测提示", detail: "CheckMyIP 现场检查标记 WebRTC 异常。" + scope + "请核对代理对 UDP／STUN 的处理。", icon: "point.3.connected.trianglepath.dotted", kind: .review, evidence: .environment, sourceURL: methodology))
        }
        let country = claudeCountry?.uppercased()
        let differentDNS = dns.filter { exit in
            guard let ip = exit.ip, IPAssessmentHTTP.validIP(ip), let resolverCountry = exit.country?.uppercased(), let country else { return false }
            return !resolverCountry.isEmpty && resolverCountry != country
        }
        if let country, !country.isEmpty, !differentDNS.isEmpty {
            items.append(.init(id: "dns", title: "DNS 疑似绕行 · 地区不一致", detail: "Claude 网页出口位于 \(country)，\(differentDNS.count) 个解析器定位在 \(Set(differentDNS.compactMap { $0.country?.uppercased() }).sorted().joined(separator: "、"))。DNS 可能走了另一条路径，公共 DNS 和定位误差也可能产生这种差异。", icon: "server.rack", kind: .review, evidence: .environment, sourceURL: guide))
        } else if (country == nil || !dns.contains { $0.ip.flatMap(IPsumFeed.canonical) != nil && $0.country?.isEmpty == false }), siteFlag("dns") {
            items.append(.init(id: "dns", title: "DNS 泄露检测提示", detail: "CheckMyIP 现场检查标记 DNS 异常。" + scope + "建议查看源站明细，核对解析器和代理内 DNS 配置。", icon: "server.rack", kind: .review, evidence: .environment, sourceURL: methodology))
        }
        if let offset = observedTimezoneDifference, offset.seconds > 0 {
            let hours = String(format: "%.1f", Double(offset.seconds) / 3600)
            items.append(.init(id: "timezone", title: "设备时区与 IP 时区不一致", detail: "\(offset.local) ↔ \(offset.remote)，本次 UTC 偏移相差 \(hours) 小时（已考虑夏令时）。IP 时区来自定位数据；出差、远程网络或定位误差也会造成差异。", icon: "clock.arrow.2.circlepath", kind: .review, evidence: .environment, sourceURL: "https://ip.net.coffee/claude/identity.html"))
        } else if observedTimezoneDifference == nil, siteFlag("tz") {
            items.append(.init(id: "timezone", title: "现场时区与 IP 不一致", detail: "CheckMyIP 现场检查提示设备与页面 IP 时区不同。" + scope + "这是环境一致性线索，不是账号违规判定。", icon: "clock.arrow.2.circlepath", kind: .review, evidence: .environment, sourceURL: methodology))
        }
        // Compare endpoints from a single probe batch, including after a connectivity refresh.
        let traces = connectivity ?? exits
        let domains = ["Claude": "claude.ai", "Claude API": "api.anthropic.com", "Anthropic": "www.anthropic.com"]
        let endpoints = traces.compactMap { probe -> (domain: String, ip: String)? in
            guard let domain = domains[probe.name], let ip = probe.ip.flatMap(IPsumFeed.canonical) else { return nil }
            return (domain, ip)
        }
        let mismatches = Dictionary(grouping: endpoints) { $0.ip.contains(":") }.values
            .filter { Set($0.map(\.ip)).count > 1 }
        if !mismatches.isEmpty {
            let names = mismatches.flatMap { $0.map(\.domain) }.sorted().joined(separator: "、")
            items.append(.init(id: "domain-route", title: "不同域名使用了不同出口", detail: "\(names) 在同一轮、同一地址协议下返回了不同公网地址。若预期使用同一出口，请查看各域名的分流规则。这次测量来自 NetGlass。", icon: "arrow.triangle.branch", kind: .review, evidence: .environment, sourceURL: guide))
        }
        if let first = traces.first(where: { $0.name == "Claude API" })?.milliseconds,
           let second = apiRecheck?.milliseconds,
           min(first, second) >= IPAssessmentHTTP.slowAPIThresholdMS {
            let times = String(format: "%.1f 秒和 %.1f 秒", first / 1000, second / 1000)
            items.append(.init(id: "api-latency", title: "API 域名连续两次响应较慢", detail: "api.anthropic.com 的两次 HTTP 探测分别耗时 \(times)，均达到本地 2 秒提醒阈值。耗时包含连接和服务端响应，可稍后刷新连通性复测。", icon: "timer", kind: .review, evidence: .environment))
        }
        return items
    }
}
