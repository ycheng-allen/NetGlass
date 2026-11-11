import SwiftUI

struct IPRiskOverview: View {
    let result: IPAssessmentResult
    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette.for(scheme) }
    private var data: CheckMyIPResponse? { result.checkedIP }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                reputation.frame(maxWidth: .infinity)
                identity.frame(maxWidth: .infinity)
            }
            browserReputation
            clues
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
            ForEach(estimate?.components ?? []) { component in
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
            Divider()
            HStack {
                Label("源站风险分", systemImage: "exclamationmark.shield")
                Spacer()
                Text(data?.validRiskScore.map { "\($0) / 100 · 越高风险线索越多" } ?? "未知")
            }.font(.system(size: 10)).foregroundStyle(palette.sub)
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
        let identity = data?.networkIdentity
        return panel {
            Label("网络身份", systemImage: "person.crop.square.filled.and.at.rectangle").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 16) {
                Image(systemName: identity?.icon ?? "questionmark.circle").font(.system(size: 34)).foregroundStyle(palette.accent)
                    .frame(width: 68, height: 68).background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 7) {
                    Text(identity?.name ?? "身份待确认").font(.system(size: 20, weight: .semibold))
                    Text(identity?.detail ?? "等待 CheckMyIP 指定地址数据").font(.system(size: 10)).foregroundStyle(palette.sub).fixedSize(horizontal: false, vertical: true)
                    Text("数据来源 · CheckMyIP").font(.system(size: 10)).foregroundStyle(palette.accent)
                }
            }
            HStack(spacing: 5) {
                routeNode("本机", icon: "laptopcomputer")
                Image(systemName: "chevron.right").foregroundStyle(palette.sub)
                routeNode(identity?.name ?? "出口", icon: identity?.icon ?? "network")
                Image(systemName: "chevron.right").foregroundStyle(palette.sub)
                routeNode("Claude", icon: "sparkles")
            }.padding(14).background(palette.bg, in: RoundedRectangle(cornerRadius: 10))
            Text("连接身份示意 · 不是路由追踪").font(.system(size: 9)).foregroundStyle(palette.sub)
            HStack {
                Label(result.locationOrganization ?? "组织未知", systemImage: "building.2")
                Spacer()
                Text(result.locationASN.map { "AS\($0)" } ?? "ASN 未知")
            }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            if let consensus = data?.geo?.consensus {
                HStack {
                    Label("定位共识", systemImage: "mappin.and.ellipse")
                    Spacer()
                    Text(consensus.countryVoteSummary)
                }.font(.system(size: 11))
                ProgressView(value: Double(consensus.agreement_count ?? 0), total: Double(max(1, consensus.source_count ?? 0))).tint(palette.accent)
            }
            HStack {
                Label("地址名单", systemImage: "checklist")
                Spacer()
                Text(data.map { $0.checkedLists > 0 ? "\($0.directHits) 项命中 · \($0.checkedLists) 项完成" : "检查尚未完成" } ?? "未知")
            }.font(.system(size: 11))
            Text("网络类型、匿名工具、归属与名单复用同一次 CheckMyIP 查询。名称推断保留来源依据，未标记代理不等于直连或安全。")
                .font(.system(size: 10)).foregroundStyle(palette.sub).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var browserReputation: some View {
        let site = result.checkMyIPBrowser
        let sameExit = site?.matches(result.exits.first(where: { $0.name == "Claude" })?.ip) == true
        return panel {
            Label("CheckMyIP 现场信誉", systemImage: "safari.fill").font(.system(size: 14, weight: .semibold))
            HStack(alignment: .top, spacing: 16) {
                liveScore("浏览器信誉", value: site?.browserScore, icon: "macwindow", detail: "NetGlass 内置 WebKit")
                liveScore("页面 IP 信誉", value: sameExit ? site?.ipScore : nil, icon: "network", detail: sameExit ? "出口与 Claude 一致" : "页面出口与 Claude 不一致或未知")
                liveScore("页面综合信誉", value: sameExit ? site?.overallScore : nil, icon: "chart.bar.fill", detail: sameExit ? "直接读取源站结果" : "不用于 Claude 出口评估")
            }
            if let site {
                Text(site.summary ?? "源站未提供汇总说明").font(.system(size: 11)).foregroundStyle(palette.sub)
                if !sameExit {
                    Text("CheckMyIP 页面采用访问它时的出口；Claude 的 IP 信誉继续使用指定地址查询。浏览器信誉包含该现场环境的网络检查，不代表其他浏览器。")
                        .font(.system(size: 10)).foregroundStyle(palette.sub)
                }
                if let error = site.error { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(palette.up) }
                DisclosureGroup("源站检查明细（\(site.checks?.count ?? 0)）") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let identity = site.identity { Label(identity, systemImage: "person.crop.square.filled.and.at.rectangle").font(.system(size: 11)) }
                        ForEach(site.checks ?? []) { check in
                            Label(check.text, systemImage: check.state == "bad" ? "exclamationmark.circle.fill" : check.state == "ok" ? "checkmark.circle" : "info.circle")
                                .font(.system(size: 10)).foregroundStyle(check.state == "bad" ? palette.up : palette.sub)
                        }
                        Text("现场获取于 " + site.checkedAt.formatted()).font(.system(size: 10)).foregroundStyle(palette.sub)
                    }.padding(.top, 10)
                }.font(.system(size: 11))
            } else { Text("正在请求 CheckMyIP 并运行现场检查；旧记录可重新评估获取。").font(.system(size: 11)).foregroundStyle(palette.sub) }
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

    private func routeNode(_ name: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 21)).foregroundStyle(palette.accent)
            Text(name).font(.system(size: 10)).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }

    private var clues: some View {
        let items = result.claudeRiskClues
        return panel {
            HStack {
                Label("Claude 使用风险线索", systemImage: "exclamationmark.bubble.fill").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(items.filter { $0.kind != .context }.count) 项待核对").font(.system(size: 11)).foregroundStyle(palette.up)
            }
            Text("突出可能与访问验证、出口信誉或地区限制有关的项目，供排查潜在账号使用风险。第三方 IP 数据不能预测封号，以下标签不代表 Claude 官方风控结论。")
                .font(.system(size: 11)).foregroundStyle(palette.sub).fixedSize(horizontal: false, vertical: true)
            if items.isEmpty {
                Label("当前资料未发现上述重点线索；仍不能据此保证账号安全", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(palette.sub)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                ForEach(items) { item in clue(item) }
            }
            Link("核对 Claude 官方支持地区", destination: URL(string: "https://www.anthropic.com/legal/supported-regions")!).font(.system(size: 10))
        }
    }

    private func clue(_ item: ClaudeRiskClue) -> some View {
        let color = item.kind == .context ? palette.accent : palette.up
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon).font(.system(size: 20)).foregroundStyle(color).frame(width: 26)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Text(item.title).font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 4)
                    Text(item.kind == .attention ? "重点核对" : item.kind == .review ? "需要核对" : "环境参考")
                        .font(.system(size: 9)).foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(color.opacity(0.1), in: Capsule())
                }
                Text(item.detail).font(.system(size: 10)).foregroundStyle(palette.sub).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(palette.bg, in: RoundedRectangle(cornerRadius: 9))
    }
}
