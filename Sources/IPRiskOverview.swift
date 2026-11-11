import SwiftUI

struct IPRiskOverview: View {
    let result: IPAssessmentResult
    var history: [IPAssessmentResult] = []
    var evaluating = false
    private var displayedClues: [ClaudeRiskClue] {
        let churn = IPExitStability.analyze(current: result, history: history).clue(current: result)
        return result.claudeRiskClues.filter { churn == nil || $0.id != "hosting" } + [churn].compactMap { $0 }
    }
    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette.for(scheme) }
    private var data: CheckMyIPResponse? { result.checkedIP }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            clues
            HStack(alignment: .top, spacing: 20) {
                if data?.reputation.value != nil || data?.validRiskScore != nil { reputation.frame(maxWidth: .infinity) }
                if data?.networkIdentity.name != nil && data?.networkIdentity.name != "身份待确认" || result.networkType.kind != .unknown { identity.frame(maxWidth: .infinity) }
            }
            if result.checkMyIPBrowser?.hasVisibleResults == true {
                DisclosureGroup("浏览器现场检查") { browserReputation.padding(.top, 8) }
            }
        }
    }

    private func panel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border))
    }

    private func scoreColor(_ value: Int?) -> Color {
        guard let value else { return palette.sub }
        return value >= 75 ? palette.accent : palette.up
    }

    private var reputation: some View {
        let estimate = data?.reputation
        let value = estimate?.value
        return panel {
            Label("IP 信誉评分", systemImage: "gauge.with.dots.needle.67percent").font(.system(size: 14, weight: .semibold))
            if value != nil {
            HStack(spacing: 24) {
                ZStack {
                    Circle().stroke(palette.border, lineWidth: 9)
                    Circle().trim(from: 0, to: CGFloat(value ?? 0) / 100)
                        .stroke(scoreColor(value), style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 3) {
                        Text(value.map(String.init) ?? "—").font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text("/ 100 · 越高越好").font(.system(size: 9)).foregroundStyle(palette.sub)
                    }
                }.frame(width: 108, height: 108).accessibilityElement(children: .ignore)
                    .accessibilityLabel("IP 信誉评分 \(value.map(String.init) ?? "未知")，满分 100，越高越好")
                VStack(alignment: .leading, spacing: 9) {
                    Text(estimate?.band ?? "等待数据").font(.system(size: 20, weight: .semibold)).foregroundStyle(scoreColor(value))
                    Text("\(estimate?.completed ?? 0) / 3 类资料可用" + ((estimate?.completed ?? 0) < 3 ? " · 部分评估" : ""))
                        .font(.system(size: 11)).foregroundStyle(palette.sub)
                    Label("估算值 · 非 Claude 评分", systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(palette.sub)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            ForEach((estimate?.components ?? []).filter { $0.deduction != nil }) { component in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label(component.title, systemImage: component.id == "lists" ? "list.bullet.rectangle" : component.id == "abuse" ? "shield.lefthalf.filled" : "person.crop.square.filled.and.at.rectangle")
                        Spacer()
                        Text(component.deduction.map { $0 == 0 ? "未扣分" : "−\($0)" } ?? "未评估")
                    }.font(.system(size: 11))
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.border)
                            Capsule().fill(component.deduction == nil ? palette.sub : palette.up)
                                .frame(width: proxy.size.width * CGFloat(component.deduction ?? 0) / 45)
                        }
                    }.frame(height: 4)
                    Text(component.detail).font(.system(size: 10)).foregroundStyle(palette.sub).fixedSize(horizontal: false, vertical: true)
                }
            }
            }
            if let riskScore = data?.validRiskScore {
            Divider()
            HStack {
                Label("源站风险分", systemImage: "exclamationmark.shield")
                Spacer()
                Text("\(riskScore) / 100 · 越高风险线索越多")
            }.font(.system(size: 10)).foregroundStyle(palette.sub)
            }
            DisclosureGroup("评分方法与范围") {
                VStack(alignment: .leading, spacing: 7) {
                    Text("IP 信誉使用 CheckMyIP 指定地址资料，按其公开 IP 信誉公式在本机复算。网络身份采用接口类型与匿名工具标记，可能与源站浏览器综合识别结果不同；不直接反转接口风险分。")
                    Text("名单首项扣 25、追加项扣 10（最多 45）；僵尸网络扣 40、开放代理扣 20（最多 45）；Tor／代理／VPN／机房按公开权重与置信度扣分（最多 30）。至少 2 类资料可用才给出分数。")
                    Text("浏览器信誉另行现场读取 CheckMyIP 页面；与 Claude 出口不一致时，页面 IP 分和综合分不用于 Claude。缺失检查不算通过。")
                    Link("CheckMyIP 公开公式与来源", destination: URL(string: "https://checkmyip.com/zh-cn/methodology")!)
                }.font(.system(size: 10)).foregroundStyle(palette.sub).padding(.top, 8)
            }.font(.system(size: 10))
        }
    }

    private var identity: some View {
        let identity = data?.networkIdentity ?? (name: result.networkType.title, icon: result.networkType.kind == .residential ? "house.fill" : "server.rack", detail: "Net.Coffee 网络归类")
        return panel {
            Label("使用场景 / 类型", systemImage: "person.crop.square.filled.and.at.rectangle").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 16) {
                Image(systemName: identity.icon).font(.system(size: 34)).foregroundStyle(palette.accent)
                    .frame(width: 68, height: 68).background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 7) {
                    Text(identity.name).font(.system(size: 20, weight: .semibold))
                    Text(identity.detail).font(.system(size: 10)).foregroundStyle(palette.sub).fixedSize(horizontal: false, vertical: true)
                    Text(data == nil ? "数据来源 · Net.Coffee" : "类型 · CheckMyIP　详情 · Net.Coffee").font(.system(size: 10)).foregroundStyle(palette.accent)
                }
            }
            if let origin = result.usageNative {
                usageRow("IP 原生性", regionName(origin.country) + " · " + (origin.same ? "原生 IP" : "广播 IP（注册于 " + regionName(origin.registration) + "）"))
                    .help("按 Net.Coffee 规则比较定位地区与注册地区。")
            }
            if let risk = result.risk {
                usageRow("标记", result.networkType.title)
                usageRow("运营商类型", risk.company_type.map { $0.capitalized })
                usageRow("服务商", risk.isp ?? risk.asOrganization ?? risk.company_name)
            }
            if let traffic = result.usageHuman { humanTraffic(traffic.percent, source: traffic.source) }
            if !result.usageScenes.isEmpty { usageScenes }
            if IPExitStability.confirmedHosting(result) {
                let stability = IPExitStability.analyze(current: result, history: history)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: stability.hostingChanges >= IPExitStability.changeThreshold ? "exclamationmark.arrow.triangle.2.circlepath" : "clock.arrow.circlepath")
                    Text("近 1 小时 · \(stability.sampleCount) 次有效采样 · \(stability.hostingChanges) 次机房 IP 切换")
                        .fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 10)).foregroundStyle(stability.hostingChanges >= IPExitStability.changeThreshold ? palette.up : palette.sub)
                    .help("相邻记录均明确为机房时计数，达到 3 次切换会在风险区提醒。采样之间的变化未知。")
            }
            DisclosureGroup("类型来源与判断依据") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.networkType.evidence, id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(palette.sub) }
                    Link("Net.Coffee 使用场景来源", destination: URL(string: "https://ip.net.coffee/ip/")!).font(.system(size: 10))
                }.padding(.top, 8)
            }.font(.system(size: 11))
        }
    }

    private func regionName(_ code: String) -> String {
        let name = Locale(identifier: "zh_CN").localizedString(forRegionCode: code) ?? code
        let flag = String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
        return flag + " " + name
    }

    private func humanTraffic(_ human: Double, source: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("人机流量").foregroundStyle(palette.sub)
                Spacer()
                Label(human >= 55 ? "人类偏多" : human >= 40 ? "人机混合" : "机器偏多",
                      systemImage: human >= 40 ? "person.fill" : "desktopcomputer")
                    .foregroundStyle(human >= 55 ? palette.accent : palette.up)
            }.font(.system(size: 11))
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle().fill(palette.accent).frame(width: geometry.size.width * human / 100)
                    Rectangle().fill(palette.up.opacity(0.75))
                }.clipShape(Capsule())
            }.frame(height: 8)
            HStack {
                Label(String(format: "人类 %.1f%%", human), systemImage: "person.fill").foregroundStyle(palette.accent)
                Spacer()
                Label(String(format: "机器 %.1f%%", 100 - human), systemImage: "desktopcomputer").foregroundStyle(palette.up)
            }.font(.system(size: 10)).monospacedDigit()
            Text(source).font(.system(size: 9)).foregroundStyle(palette.sub)
        }.padding(12).background(palette.bg, in: RoundedRectangle(cornerRadius: 10))
            .help("Net.Coffee 来源估计，描述 ASN 网络群体及 IP 标记，无法代表本机真实人机流量比例。")
    }

    private var usageScenes: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("场景评估").font(.system(size: 11, weight: .medium))
                Image(systemName: "info.circle").foregroundStyle(palette.sub)
                    .help("按 Net.Coffee 公开规则复算，满分 10 分。地区与 IP 属性推断的参考值，服务实际可用性需实测。")
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(result.usageScenes) { scene in
                    let color = scene.score >= 8 ? palette.accent : palette.up
                    VStack(spacing: 7) {
                        ZStack {
                            Circle().stroke(palette.border, lineWidth: 5)
                            Circle().trim(from: 0, to: CGFloat(scene.score) / 10)
                                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(scene.score)").font(.system(size: 22, weight: .semibold, design: .rounded))
                        }.frame(width: 58, height: 58)
                        Text(scene.name).font(.system(size: 11, weight: .medium))
                        Text(scene.verdict).font(.system(size: 10)).foregroundStyle(color)
                    }.frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(scene.name)，\(scene.score) 分，满分 10 分，\(scene.verdict)")
                }
            }
            Text("Net.Coffee 规则估算 · 实际可用性请以访问结果为准")
                .font(.system(size: 9)).foregroundStyle(palette.sub)
        }
    }

    @ViewBuilder
    private func usageRow(_ title: String, _ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(alignment: .top) {
                Text(title).foregroundStyle(palette.sub)
                Spacer()
                Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
            }.font(.system(size: 11))
        }
    }

    private var browserReputation: some View {
        let site = result.checkMyIPBrowser
        let sameExit = site?.matches(result.exits.first(where: { $0.name == "Claude" })?.ip) == true
        return panel {
            Label("CheckMyIP 现场信誉", systemImage: "safari.fill").font(.system(size: 14, weight: .semibold))
            HStack(alignment: .top, spacing: 16) {
                if let value = site?.browserScore { liveScore("浏览器信誉", value: value, icon: "macwindow", detail: "NetGlass 内置 WebKit") }
                if sameExit, let value = site?.ipScore { liveScore("页面 IP 信誉", value: value, icon: "network", detail: "出口与 Claude 一致") }
                if sameExit, let value = site?.overallScore { liveScore("页面综合信誉", value: value, icon: "chart.bar.fill", detail: "直接读取源站结果") }
            }
            if let site {
                if let summary = site.summary { Text(summary.replacingOccurrences(of: #" · \d+ 项检查无法运行"#, with: "", options: .regularExpression)).font(.system(size: 11)).foregroundStyle(palette.sub) }
                if !sameExit {
                    Text("CheckMyIP 页面采用访问它时的出口；Claude 的 IP 信誉继续使用指定地址查询。浏览器信誉包含该现场环境的网络检查，不代表其他浏览器。")
                        .font(.system(size: 10)).foregroundStyle(palette.sub)
                }
                if !site.visibleChecks.isEmpty {
                DisclosureGroup("源站检查明细（\(site.visibleChecks.count)）") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let identity = site.identity { Label(identity, systemImage: "person.crop.square.filled.and.at.rectangle").font(.system(size: 11)) }
                        ForEach(site.visibleChecks) { check in
                            Label(check.text, systemImage: check.state == "bad" ? "exclamationmark.circle.fill" : check.state == "ok" ? "checkmark.circle" : "info.circle")
                                .font(.system(size: 10)).foregroundStyle(check.state == "bad" ? palette.up : palette.sub)
                        }
                        Text("现场获取于 " + site.checkedAt.formatted()).font(.system(size: 10)).foregroundStyle(palette.sub)
                    }.padding(.top, 10)
                }.font(.system(size: 11))
                }
            }
        }
    }

    private func liveScore(_ title: String, value: Int?, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium))
            Text(value.map { "\($0) / 100" } ?? "—").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(scoreColor(value))
            ProgressView(value: Double(value ?? 0), total: 100).tint(scoreColor(value))
            Text(detail).font(.system(size: 10)).foregroundStyle(palette.sub).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(palette.bg, in: RoundedRectangle(cornerRadius: 10))
    }

    private var clues: some View {
        let items = displayedClues
        let major = items.filter { $0.kind == .critical }
        let priority = items.filter { $0.kind == .attention }
        let review = items.filter { $0.kind == .review }
        return panel {
            HStack {
                Label("本次风险提示", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                if !items.isEmpty {
                    Text("\(items.count) 项").font(.callout.monospacedDigit()).foregroundStyle(palette.sub)
                }
            }
            if items.isEmpty {
                Text(evaluating ? "正在比对出口和检测结果…" : "本次取得的数据未触发风险提示。")
                    .font(.callout).foregroundStyle(palette.sub)
            }
            ForEach(major + priority + review) { item in
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    let color = item.kind == .critical || item.kind == .attention ? palette.danger : palette.up
                    Image(systemName: item.icon).font(.system(size: 16)).foregroundStyle(color)
                        .frame(width: 32, height: 32).background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if item.kind == .critical {
                                Text("重大风险").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(palette.danger).padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(palette.danger.opacity(0.1), in: Capsule())
                            } else {
                                Text(item.evidence.rawValue).font(.caption).foregroundStyle(palette.sub)
                            }
                        }
                        Text(item.detail).font(.system(size: 12)).foregroundStyle(palette.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
