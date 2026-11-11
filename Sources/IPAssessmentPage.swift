import SwiftUI

struct IPAssessmentPage: View {
    @ObservedObject var model: IPAssessment
    @Environment(\.colorScheme) private var scheme
    @State private var hideIPs = false
    @State private var confirmClear = false
    private var palette: Palette { Palette.for(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            card {
                HStack(spacing: 14) {
                    Image(systemName: "globe").font(.system(size: 22)).foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Claude风险检测").font(.system(size: 18, weight: .semibold))
                        Text(model.running ? model.phase : "每次点击重新查询出口、IP 属性和实时探测结果")
                            .font(.system(size: 11)).foregroundStyle(palette.sub)
                    }
                    Spacer()
                    Toggle("隐藏 IP", isOn: $hideIPs).toggleStyle(.switch).controlSize(.small)
                    Button { model.evaluate() } label: {
                        HStack(spacing: 8) {
                            if model.running { ProgressView().controlSize(.small) }
                            Label(model.running ? "评估中…" : "评估", systemImage: "arrow.clockwise")
                        }
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.running || model.connectivityRunning)
                }
                DisclosureGroup("检测范围与数据来源") {
                    Text("出口通过 NetGlass 请求目标取得，设备与 UDP 使用独立 WebKit 环境。其他应用可能使用不同代理。Claude 出口 IP 会发送至 Net.Coffee 与 CheckMyIP 查询属性；IPsum 名单下载后在本机匹配。现场信誉会在临时 WebKit 会话加载 CheckMyIP 并运行源站检测，读取浏览器信誉与检查明细。探测还访问 IP138／IP.cn、Cloudflare、Anthropic 与 STUN 服务。")
                        .font(.system(size: 11)).foregroundStyle(palette.sub).padding(.top, 6)
                }.font(.system(size: 10)).foregroundStyle(palette.sub)
            }
            if let result = model.result {
                HStack {
                    Label(result.date.formatted(date: .abbreviated, time: .standard), systemImage: "clock")
                    Spacer()
                    Text("本次查询时间 · 各来源更新时间见详情")
                }.font(.system(size: 10)).foregroundStyle(palette.sub)
                if result.exits.contains(where: { $0.ip?.contains(":") == true }) {
                    Label("本轮包含 IPv6 出口，部分属性或探测可能缺失", systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(palette.up)
                }
                IPRiskOverview(result: result)
                if result.exits.contains(where: { $0.ip != nil && $0.name != "Anthropic" }) { exits(result) }
                HStack(alignment: .top, spacing: 20) {
                    if result.risk != nil || result.checkedIP != nil { attributes(result).frame(maxWidth: .infinity) }
                    if result.hasRiskResults { riskFlags(result).frame(maxWidth: .infinity) }
                }
                if result.checkedIP != nil { checkMyIP(result) }
                if result.serviceDetails != nil || (result.connectivity ?? []).contains(where: { $0.milliseconds != nil }) { connectivity(result) }
                HStack(alignment: .top, spacing: 20) {
                    if !result.dns.isEmpty { dns(result).frame(maxWidth: .infinity) }
                    if !result.udp.isEmpty { udp(result).frame(maxWidth: .infinity) }
                }
                if !result.device.isEmpty { device(result) }
            } else if !model.running {
                card {
                    VStack(spacing: 12) {
                        Image(systemName: "network").font(.system(size: 30)).foregroundStyle(palette.accent)
                        Text("点击评估，检查当前网络出口与环境").font(.system(size: 13))
                        Text("仅展示本次成功获取的数据").font(.system(size: 11)).foregroundStyle(palette.sub)
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
            exitHistory
            history
            HStack(spacing: 16) {
                Link("功能参考 Net.Coffee", destination: URL(string: "https://ip.net.coffee/claude/")!)
                Link("官方地区条款", destination: URL(string: "https://www.anthropic.com/legal/supported-regions")!)
                Link("Anthropic 服务状态", destination: URL(string: "https://status.claude.com/")!)
            }.font(.system(size: 10)).foregroundStyle(palette.sub)
        }.tint(palette.accent)
            .alert("清空本地 IP 评估历史？", isPresented: $confirmClear) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { model.clearHistory() }
            } message: { Text("将删除本地保存的评估记录。") }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border))
    }

    private func visibleValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !["未知", "未取得", "无法", "缺少", "未提供", "失败", "未完成"].contains(where: clean.contains) else { return nil }
        return clean
    }

    private func address(_ ip: String?) -> String { ip.map { hideIPs ? "••••••••" : $0 } ?? "未取得" }

    @ViewBuilder
    private func line(_ label: String, value: String?, color: Color? = nil) -> some View {
        if let value = visibleValue(value) {
        HStack(alignment: .top, spacing: 14) {
            Text(label).font(.system(size: 11)).foregroundStyle(palette.sub).frame(width: 95, alignment: .leading)
            Text(value)
                .font(.system(size: 12)).foregroundStyle(color ?? palette.text)
                .frame(maxWidth: .infinity, alignment: .trailing).textSelection(.enabled)
        }
        }
    }

    private func exits(_ result: IPAssessmentResult) -> some View {
        card {
            HStack {
                Label("出口 IP", systemImage: "arrow.up.right.circle").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(result.serviceStatus ?? "").font(.system(size: 11)).foregroundStyle(palette.sub)
            }
            HStack(alignment: .top, spacing: 16) {
                ForEach(result.exits.filter { $0.name != "Anthropic" && $0.ip != nil }) { exit in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(exit.name == "国内查询服务" ? "国内网站出口" : exit.name + " 出口").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.sub)
                        Text(address(exit.ip)).font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        if let ip = exit.ip, !hideIPs, let url = URL(string: "https://ip.net.coffee/ip/" + ip) {
                            Link("IP 详情", destination: url).font(.system(size: 10))
                        }
                        if let country = exit.country {
                            Text(countryLabel(country)).font(.system(size: 10)).foregroundStyle(palette.sub)
                        }
                        if let geo = exit.geo {
                            Text([geo.region, geo.city, geo.isp].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 10)).foregroundStyle(palette.sub).fixedSize(horizontal: false, vertical: true)
                        }
                        if let source = exit.source { Text("来源 " + source).font(.system(size: 9)).foregroundStyle(palette.sub) }
                        if let time = exit.milliseconds {
                            Text(String(format: "HTTP 响应 %.0f ms", time)).font(.system(size: 10)).foregroundStyle(palette.accent)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading).padding(16)
                        .background(exit.name == "Claude" ? palette.accent.opacity(0.06) : palette.bg, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(exit.name == "Claude" ? palette.accent.opacity(0.35) : .clear))
                }
            }
            Text("HTTP trace 响应表示端点可达，业务登录与 Claude 使用可用性需要单独验证。")
                .font(.system(size: 10)).foregroundStyle(palette.sub)
        }
    }

    private func typeColor(_ type: IPNetworkType) -> Color {
        switch type.kind {
        case .hosting, .conflict: return palette.up
        case .residential: return palette.down
        default: return palette.accent
        }
    }

    private func attributes(_ result: IPAssessmentResult) -> some View {
        let type = result.networkType
        return card {
            Label("Claude AI 出口 IP 属性", systemImage: "mappin.and.ellipse").font(.system(size: 14, weight: .semibold))
            HStack {
                if type.kind != .unknown {
                Text("IP 属性").font(.system(size: 12)).foregroundStyle(palette.sub)
                Spacer()
                Label(type.title, systemImage: type.kind == .residential ? "house.fill" : "network")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(typeColor(type))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(typeColor(type).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
                }
            line("地区", value: result.claudeCountry.map(countryLabel) ?? result.risk?.country)
            line("城市", value: [result.locationRegion, result.locationCity].compactMap { $0 }.joined(separator: " · "))
            line("ASN", value: result.locationASN.map { "AS\($0)" })
            line("运营商", value: result.locationOrganization)
            Divider()
            if type.kind != .unknown || result.risk != nil {
            DisclosureGroup("分类依据与网络详情") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(type.kind == .unknown ? [] : type.evidence, id: \.self) { evidence in
                        Label(evidence, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(palette.sub)
                    }
                    line("公司", value: result.risk?.company_name)
                    line("公司类型", value: result.risk?.company_type)
                    line("ASN 类型", value: result.risk?.asnKind)
                    line("机房名称", value: result.risk?.datacenterName)
                    line("IP 时区", value: result.locationTimezone)
                    line("注册国家", value: result.risk?.registeredCountry)
                    line("反向 DNS", value: (result.checkedIP?.hostname ?? result.risk?.reverseDNS).map { hideIPs ? "已隐藏" : $0 })
                    line("路由认证", value: result.risk?.rpki)
                    if let cidr = result.risk?.cidr { line("来源匹配网段", value: hideIPs ? "••••••••" : cidr) }
                    line("住宅标记", value: result.risk?.isResidential.map { $0 ? "来源标记为住宅" : "来源未标记为住宅" })
                    Text("分类规则 ip-type-v2 · 结合来源证据；名称推断会单独注明")
                        .font(.system(size: 10)).foregroundStyle(palette.sub)
                }.padding(.top, 12)
            }.font(.system(size: 11))
            }
            if let rules = result.rules, result.claudeCountry != nil { Text(rules.region(result.claudeCountry)).font(.system(size: 11)).foregroundStyle(palette.sub) }
            if let message = visibleValue(result.regionMessage) { DisclosureGroup("官方地区政策") { Text(message).font(.system(size: 11)).foregroundStyle(palette.sub).padding(.top, 6) }.font(.system(size: 11)) }
        }
    }

    @ViewBuilder
    private func riskTile(_ title: String, value: Bool?) -> some View {
        if value != nil {
        HStack(spacing: 10) {
            Image(systemName: value == nil ? "questionmark.circle" : (["VPN": "lock.shield", "代理 Proxy": "arrow.triangle.branch", "Tor": "network.badge.shield.half.filled", "Private Relay": "cloud", "爬虫 Crawler": "ant", "滥用记录": "exclamationmark.shield", "保留地址 Bogon": "network.slash"][title] ?? "shield"))
                .font(.system(size: 17)).foregroundStyle(value == true ? palette.up : palette.sub)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(value.map { $0 ? "来源已标记" : "来源未标记" } ?? "未知").font(.system(size: 10)).foregroundStyle(value == true ? palette.up : palette.sub)
            }
            Spacer(minLength: 0)
        }.padding(12).background(palette.bg, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func riskFlags(_ result: IPAssessmentResult) -> some View {
        card {
            Label("安全检测", systemImage: "shield.lefthalf.filled").font(.system(size: 14, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(["VPN", "代理 Proxy", "Tor", "Private Relay"].filter { result.combinedRisk($0) != nil }, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 4) {
                        riskTile(name, value: result.combinedRisk(name))
                        Text(result.riskSourceSummary(name)).font(.system(size: 9)).foregroundStyle(palette.sub).fixedSize(horizontal: false, vertical: true)
                    }
                }
                riskTile("爬虫 Crawler", value: result.risk?.is_crawler)
                riskTile("滥用记录", value: result.risk?.is_abuser)
                riskTile("保留地址 Bogon", value: result.risk?.signals?["is_bogon"])
            }
            if result.ipsum?.occurrences != nil { ipsum(result.ipsum) }
            DisclosureGroup("更多标记与来源依据") {
                VStack(alignment: .leading, spacing: 12) {
                    flag("Net.Coffee 数据中心", value: result.risk?.is_datacenter)
                    flag("CheckMyIP 数据中心名单", value: result.checkedIP?.risk?.is_datacenter)
                    flag("移动网络", value: result.risk?.signals?["is_mobile"])
                    flag("广播网络标记", value: result.risk?.signals?["isBroadcast"])
                    ForEach(extraSignals(result), id: \.0) { item in flag(item.0, value: item.1) }
                    ForEach(result.risk?.evidence ?? []) { item in
                        Label(item.label, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(palette.up)
                    }
                    if let date = result.riskCheckedAt { Text("来源查询于 \(date.formatted())").font(.system(size: 10)).foregroundStyle(palette.sub) }
                }.padding(.top, 12)
            }.font(.system(size: 11))
            if let note = result.riskSourceNote { Text(note).font(.system(size: 10)).foregroundStyle(palette.up) }
            Text("未标记或未命中名单，均不能证明没有风险。")
                .font(.system(size: 10)).foregroundStyle(palette.sub)
        }
    }

    private func checkMyIP(_ result: IPAssessmentResult) -> some View {
        card {
            HStack {
                Label("来源核对 · CheckMyIP", systemImage: "square.stack.3d.up").font(.system(size: 14, weight: .semibold))
                Spacer()
                Link("查询方法", destination: URL(string: "https://checkmyip.com/zh-cn/methodology")!).font(.system(size: 11))
            }
            if let data = result.checkedIP {
                Text("已核对查询地址与 Claude 出口一致").font(.system(size: 11)).foregroundStyle(palette.accent)
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 12) {
                        line("定位来源", value: "CheckMyIP 多源定位；缺失时使用 Net.Coffee")
                        line("地区投票", value: data.geo?.consensus?.countryVoteSummary)
                        line("城市定位", value: [data.geo?.consensus?.region, data.geo?.consensus?.city].compactMap { $0 }.joined(separator: " · "))
                        line("城市来源分散", value: data.geo?.consensus?.spread_km.map { String(format: "约 %.1f km", $0) })
                        flag("地理来源分歧", value: data.geo?.consensus?.disagreement)
                        flag("Anycast 标记", value: data.geo?.consensus?.anycast)
                    }.frame(maxWidth: .infinity)
                    VStack(spacing: 12) {
                        line("注册国家", value: data.network?.registry_country.map(countryLabel))
                        line("注册管理机构", value: data.network?.rir)
                        line("路由前缀", value: data.network?.prefix.map { hideIPs ? "已隐藏" : $0 })
                        flag("多起源 ASN", value: data.network?.multi_origin)
                        line("IP 时区依据", value: data.geo?.consensus?.timezone_source)
                        line("分类置信度", value: data.type?.confidence.map { ["high": "高", "medium": "中", "low": "低"][$0] ?? $0 })
                    }.frame(maxWidth: .infinity)
                }
                Text("定位是数据库估计；注册国家表示资源登记地。分类置信度是来源自身判断，住宅属性无法证明实际家宽。")
                    .font(.system(size: 10)).foregroundStyle(palette.sub)
                DisclosureGroup("地理定位与分类来源详情") {
                    VStack(alignment: .leading, spacing: 12) {
                        line("Net.Coffee 地区", value: [result.risk?.countryCode, result.risk?.region, result.risk?.city].compactMap { $0 }.joined(separator: " · "))
                        line("CheckMyIP 地区", value: [data.geo?.consensus?.country, data.geo?.consensus?.region, data.geo?.consensus?.city].compactMap { $0 }.joined(separator: " · "))
                        line("Net.Coffee ASN", value: result.risk?.asn.map { "AS\($0)" })
                        line("CheckMyIP ASN", value: data.network?.asn.map { "AS\($0)" })
                        ForEach(data.geo?.sources ?? []) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text((source.name ?? source.id) + (source.kind == "registry" ? " · 注册资料，单独展示" : " · 地理定位"))
                                    .font(.system(size: 11, weight: .medium))
                                Text([source.country, source.region, source.city].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 11))
                                Text([source.updated, source.freshness, source.licence].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(palette.sub)
                            }
                        }
                        ForEach(data.geo?.consensus?.notes ?? [], id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(palette.sub) }
                        line("网络归类", value: data.type?.title)
                        line("归类来源", value: data.type?.source)
                        line("反向 DNS", value: data.hostname.map { hideIPs ? "已隐藏" : $0 })
                        line("接口版本", value: data.schema_version)
                        ForEach(Array((data.network?.origins ?? []).enumerated()), id: \.offset) { _, origin in
                            Text([origin.asn.map { "AS\($0)" }, origin.as_org ?? origin.as_name, origin.named_by?.joined(separator: " / ")].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(palette.sub)
                        }
                        if let hosted = data.hosted_domains, hosted.status == "ok", let count = hosted.total_domains {
                            line("同 IP 托管域名", value: "\(count) 个")
                            Text([hosted.source, hosted.freshness, hosted.error].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(palette.sub)
                        }
                        ForEach(data.type?.reasons ?? [], id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(palette.sub) }
                        ForEach(Array((data.risk?.factors ?? []).enumerated()), id: \.offset) { _, factor in
                            Text([factor.label, factor.source].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(palette.sub)
                        }
                    }.padding(.top, 12)
                }.font(.system(size: 11))
                if data.checkedLists > 0 {
                Divider()
                HStack {
                    Label("DNSBL 名单核查", systemImage: "checklist").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(data.checkedLists > 0 ? "地址命中 \(data.directHits) / 已完成 \(data.checkedLists) 项" : "未知 · 尚无已完成的地址核查")
                        .font(.system(size: 11)).foregroundStyle(data.directHits > 0 ? palette.up : palette.sub)
                }
                DisclosureGroup("逐项查看名单结果（\(data.risk?.blacklists?.filter(\.checked).count ?? 0)）") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach((data.risk?.blacklists ?? []).filter(\.checked)) { list in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top) {
                                    Text(list.name ?? list.list).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(list.status).font(.system(size: 11)).foregroundStyle(list.checked && list.listed == true ? palette.up : palette.sub)
                                }
                                Text(list.error ?? list.checked_at ?? "未提供核查时间").font(.system(size: 10)).foregroundStyle(palette.sub)
                            }
                        }
                    }.padding(.top, 12)
                }.font(.system(size: 11))
                Text("网段／ASN 关联命中单独展示，不计作此地址命中；DNSBL 覆盖垃圾邮件和滥用等不同范围。未命中不能排除代理。")
                    .font(.system(size: 10)).foregroundStyle(palette.sub)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let observed = result.checkMyIP { Text("本轮查询 · " + observed.checkedAt.formatted()) }
                    Text([data.generated_at.map { "来源生成 · " + $0 }, data.cache.map { "缓存策略 " + $0 }].compactMap { $0 }.joined(separator: " · "))
                    Text("每次评估重新请求；CheckMyIP 及其上游仍可能返回缓存资料。")
                    HStack {
                        Link("CheckMyIP", destination: URL(string: "https://checkmyip.com/zh-cn")!)
                        Link("IP Geolocation by DB-IP · CC BY 4.0", destination: URL(string: "https://db-ip.com")!)
                        Link("IP2Location.io", destination: URL(string: "https://www.ip2location.io")!)
                        Link("iptoasn · PDDL", destination: URL(string: "https://iptoasn.com")!)
                    }
                }.font(.system(size: 10)).foregroundStyle(palette.sub)
            }
        }
    }

    private func ipsum(_ observation: IPsumObservation?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("IPsum 黑名单线索", systemImage: "list.bullet.rectangle").font(.system(size: 12, weight: .medium))
                Spacer()
                if let count = observation?.occurrences {
                    Text(count > 0 ? "\(count) 个来源收录" : "本次名单未命中")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(count > 0 ? palette.up : palette.sub)
                } else { Text("未知").font(.system(size: 11)).foregroundStyle(palette.sub) }
            }
            DisclosureGroup("名单来源与更新时间") {
                VStack(alignment: .leading, spacing: 7) {
                    if let observation {
                        if let error = observation.error { Text("名单查询失败 · " + error).foregroundStyle(palette.up) }
                        if let updated = observation.sourceUpdated { Text("名单更新 · " + updated) }
                        Text("本轮获取 · " + observation.checkedAt.formatted())
                        if let count = observation.recordCount { Text("\(count) 条地址 · 版本 \(observation.version ?? "未知")") }
                    } else { Text(model.running ? "名单正在获取…" : "本次记录尚无 IPsum 数据，可重新评估") }
                    Text("数字为来源名单的收录数量，按 Claude 出口地址精确匹配。")
                    Link("stamparm/ipsum · Unlicense", destination: URL(string: "https://github.com/stamparm/ipsum")!)
                }.font(.system(size: 10)).foregroundStyle(palette.sub).padding(.top, 8)
            }.font(.system(size: 10)).foregroundStyle(palette.sub)
        }.padding(14).background(palette.bg, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func flag(_ label: String, value: Bool?) -> some View {
        if value != nil {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(palette.sub)
            Spacer()
            Label(value.map { $0 ? "已标记" : "来源未标记" } ?? "未知", systemImage: value == true ? "exclamationmark.triangle.fill" : (value == false ? "minus.circle" : "questionmark.circle"))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(value == true ? palette.up : palette.sub)
        }
        }
    }

    private func dns(_ result: IPAssessmentResult) -> some View {
        card {
            Label("DNS 出口", systemImage: "server.rack").font(.system(size: 14, weight: .semibold))
            Text(result.dnsMessage).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            if let primary = result.dns.first(where: { $0.country?.uppercased() == "CN" && result.claudeCountry?.uppercased() != "CN" }) ?? result.dns.first {
                line("解析器出口", value: address(primary.ip))
                line("归属", value: [primary.geo?.country, primary.geo?.isp ?? primary.name].compactMap { $0 }.joined(separator: " · "))
            }
            DisclosureGroup("全部解析器（\(result.dns.count)）") {
            ForEach(result.dns) { exit in
                VStack(alignment: .leading, spacing: 5) {
                    line(exit.country.map(countryLabel) ?? "地区未知", value: address(exit.ip))
                    Text(exit.error ?? [exit.geo?.region, exit.geo?.city, exit.geo?.isp ?? exit.name].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(palette.sub)
                }
            }
            }
            Link("DNS 安全详细查询", destination: URL(string: "https://ip.net.coffee/dns/")!).font(.system(size: 11))
            Text("通过随机子域名与 Net.Coffee 权威 DNS 结果接口现场探测。观测对象是解析器出口，不能单凭地理位置判断 DNS 泄露。")
                .font(.system(size: 10)).foregroundStyle(palette.sub)
        }
    }

    private func udp(_ result: IPAssessmentResult) -> some View {
        card {
            Label("WebRTC UDP 出口", systemImage: "point.3.connected.trianglepath.dotted").font(.system(size: 14, weight: .semibold))
            Text(result.udpMessage).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            ForEach(result.udp, id: \.self) { ip in
                VStack(alignment: .leading, spacing: 5) {
                    Text(address(ip)).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    if let exit = result.udpExits?.first(where: { $0.ip == ip }) {
                        Text([exit.geo?.country, exit.geo?.region, exit.geo?.city, exit.geo?.isp].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(palette.sub)
                    }
                }
            }
            Link("WebRTC 深度查询", destination: URL(string: "https://ip.net.coffee/webrtc/")!).font(.system(size: 11))
            Text("使用 Cloudflare 与 Google STUN 采集 WebKit 的反射候选地址。")
                .font(.system(size: 10)).foregroundStyle(palette.sub)
        }
    }

    private func device(_ result: IPAssessmentResult) -> some View {
        card {
            Label("设备与 WebKit 环境", systemImage: "desktopcomputer").font(.system(size: 14, weight: .semibold))
            line("时区对照", value: result.timezoneComparison)
            line("语言对照", value: result.languageComparison)
            if let rules = result.rules {
                Text("地区与语言规则 · Net.Coffee \(rules.version) · 获取于 \(rules.fetchedAt.formatted())")
                    .font(.system(size: 10)).foregroundStyle(palette.sub)
            }
            line("系统／浏览器", value: result.device["操作系统 / 浏览器"])
            line("WebGL 渲染器", value: result.device["WebGL 渲染器"])
            DisclosureGroup("设备信息与指纹") {
                VStack(spacing: 12) {
                    ForEach(result.device.keys.sorted(), id: \.self) { key in line(key, value: result.device[key]) }
                }.padding(.top, 12)
            }.font(.system(size: 11))
            Text("时区与语言差异属于环境对照，不等于风险或 Claude 封禁依据。")
                .font(.system(size: 10)).foregroundStyle(palette.sub)
            Text("Canvas 与 WebGL 哈希使用 NetGlass 的固定采集方式，仅存储在本机。")
                .font(.system(size: 10)).foregroundStyle(palette.sub)
        }
    }

    private func countryLabel(_ code: String) -> String {
        guard code.count == 2 else { return code }
        let normalized = code.uppercased()
        let flag = String(String.UnicodeScalarView(normalized.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
        return flag + " " + (Locale(identifier: "zh_CN").localizedString(forRegionCode: normalized) ?? normalized)
    }

    private func extraSignals(_ result: IPAssessmentResult) -> [(String, Bool)] {
        let labels = ["is_satellite": "卫星网络", "is_public_proxy": "公共代理", "is_residential_proxy": "住宅代理", "is_anonymous": "匿名网络", "is_spam": "垃圾信息记录", "is_attacker": "攻击记录"]
        return labels.keys.sorted().compactMap { key in
            guard let value = result.risk?.signals?[key] else { return nil }
            return (labels[key]!, value)
        }
    }

    private func statusLabel(_ value: String) -> String {
        let labels = ["operational": "正常运行", "degraded_performance": "性能下降", "partial_outage": "部分故障", "major_outage": "严重故障", "under_maintenance": "维护中", "none": "全部服务正常", "minor": "轻微故障", "major": "重大故障", "critical": "严重故障", "maintenance": "维护中"]
        return labels[value] ?? value
    }

    private func connectivity(_ result: IPAssessmentResult) -> some View {
        card {
            HStack {
                Label("Claude 连通性与服务状态", systemImage: "waveform.path.ecg").font(.system(size: 14, weight: .semibold))
                Spacer()
                if model.connectivityRunning { ProgressView().controlSize(.small) }
                Button("刷新连通性") { model.refreshConnectivity() }.controlSize(.small).disabled(model.running || model.connectivityRunning)
            }
            ForEach((result.connectivity ?? result.exits.filter { $0.name == "Claude" || $0.name == "Anthropic" }).filter { $0.milliseconds != nil }) { exit in
                line(exit.name == "Claude" ? "claude.ai" : "anthropic.com", value: exit.milliseconds.map { time in
                    (time < 250 ? "正常" : (time < 500 ? "良好" : "较慢")) + String(format: " · %.0f ms", time)
                } ?? "探测失败 · " + (exit.error ?? "未知原因"), color: exit.milliseconds == nil ? palette.up : palette.accent)
            }
            if let date = result.connectivityDate { Text("HTTP 探测于 \(date.formatted())").font(.system(size: 10)).foregroundStyle(palette.sub) }
            Text("HTTP 响应反映端点连通性，地区限制与业务登录另行核对。").font(.system(size: 10)).foregroundStyle(palette.sub)
            Divider()
            if let service = result.serviceDetails {
                line("服务整体状态", value: service.status.indicator.map(statusLabel) ?? service.status.description)
                DisclosureGroup("服务组件（\(service.components?.count ?? 0)）") {
                    VStack(spacing: 12) {
                        ForEach(service.components ?? []) { component in line(component.name, value: statusLabel(component.status)) }
                    }.padding(.top, 12)
                }.font(.system(size: 11))
                ForEach(service.incidents ?? []) { incident in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(incident.name).font(.system(size: 12, weight: .medium))
                        Text(incident.status).font(.system(size: 10)).foregroundStyle(palette.up)
                        if let value = incident.shortlink, let url = URL(string: value), url.scheme == "https" {
                            Link("查看事件", destination: url).font(.system(size: 11))
                        }
                    }
                }
            }
            Link("Anthropic 实时服务状态", destination: URL(string: "https://status.claude.com/")!).font(.system(size: 11))
        }
    }

    private var exitHistory: some View {
        card {
            HStack {
                Label("Claude 出口 IP 历史", systemImage: "arrow.triangle.swap").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("同一 IP 在 24 小时内合并 · 最近 6 条").font(.system(size: 10)).foregroundStyle(palette.sub)
            }
            if model.exitHistory.isEmpty { Text("尚无出口记录").font(.system(size: 11)).foregroundStyle(palette.sub) }
            ForEach(model.exitHistory) { item in
                HStack {
                    Text(item.date.formatted(date: .abbreviated, time: .standard)).font(.system(size: 11)).foregroundStyle(palette.sub)
                    if item.id == model.exitHistory.first?.id { Text("最新").font(.system(size: 10)).foregroundStyle(palette.accent) }
                    Spacer()
                    Text(countryLabel(item.claudeCountry ?? "" )).font(.system(size: 11)).foregroundStyle(palette.sub)
                    Text(address(item.exits.first(where: { $0.name == "Claude" })?.ip)).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Text(item.risk?.city ?? "").font(.system(size: 11)).foregroundStyle(palette.sub)
                }
            }
        }
    }

    private var history: some View {
        card {
            HStack {
                Label("本地评估历史", systemImage: "clock.arrow.circlepath").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("最近 30 次").font(.system(size: 10)).foregroundStyle(palette.sub)
                Button("清空", role: .destructive) { confirmClear = true }.controlSize(.small).disabled(model.history.isEmpty || model.running)
            }
            if model.history.isEmpty { Text("评估完成后在本机保存记录").font(.system(size: 11)).foregroundStyle(palette.sub) }
            DisclosureGroup("展开完整评估记录（\(model.history.count)）") {
            ForEach(model.history) { item in
                HStack {
                    Text(item.date.formatted(date: .abbreviated, time: .standard)).font(.system(size: 11)).foregroundStyle(palette.sub)
                    Spacer()
                    Text(address(item.exits.first(where: { $0.name == "Claude" })?.ip)).font(.system(size: 11, design: .monospaced))
                    Button("查看") { model.result = item }.controlSize(.small).disabled(model.running || model.connectivityRunning)
                }
            }
            }.font(.system(size: 11))
        }
    }
}

struct ClaudeRiskPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            IPAssessmentPage(model: state.ipAssessment)
                .frame(maxWidth: 1180).frame(maxWidth: .infinity).padding(24)
        }.background(Palette.for(scheme).bg)
    }
}
