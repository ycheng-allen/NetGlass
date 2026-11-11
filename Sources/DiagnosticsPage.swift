import SwiftUI
import Charts

struct DiagnosticsPage: View {
    @EnvironmentObject var state: AppState
    var body: some View { DiagnosticsContent(state: state, insights: state.insights, outbound: state.outbound) }
}

private struct DiagnosticsContent: View {
    @ObservedObject var state: AppState
    @ObservedObject var insights: NetworkInsights
    @ObservedObject var outbound: OutboundFirewall
    @Environment(\.colorScheme) private var colorScheme
    @State private var tab = 0
    @State private var liveTimeline = true
    @State private var appFilter = ""
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var end = Date()
    @State private var appID = ""
    @State private var target = "*"
    @State private var action: OutboundRule.Action = .block
    @State private var profileName = ""

    private var palette: Palette { Palette.for(colorScheme) }
    private let tabs = ["网络健康", "连接时间线", "网络配置", "出站规则", "诊断报告", "网络连通性测试"]
    private let tabIcons = ["waveform.path.ecg", "point.3.connected.trianglepath.dotted", "network", "shield.lefthalf.filled", "square.and.arrow.up", "network"]
    private var currentHealth: [HealthSample] { insights.health.filter { $0.network == insights.network } }
    private var validRange: Bool { start < end }
    private var validProfileName: Bool { !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tabs[tab]).font(.system(size: 22, weight: .semibold))
                    Label(insights.networkDescription, systemImage: "network")
                        .font(.system(size: 11)).foregroundStyle(palette.sub)
                        .lineLimit(1).textSelection(.enabled)
                }
                Spacer()
                if state.paused {
                    Label("监控已暂停", systemImage: "pause.circle").foregroundStyle(palette.sub)
                } else if tab == 0 {
                    Button { insights.probe() } label: {
                        Label(insights.probing ? "探测中…" : "立即探测", systemImage: "arrow.clockwise")
                    }.disabled(insights.probing).controlSize(.large)
                }
            }.padding(.horizontal, 24).padding(.vertical, 20)
            HStack(spacing: 6) {
                ForEach(tabs.indices, id: \.self) { index in
                    Button { tab = index } label: {
                        Label(tabs[index], systemImage: tabIcons[index])
                            .font(.system(size: 12, weight: tab == index ? .semibold : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .foregroundStyle(tab == index ? palette.accent : palette.sub)
                            .background(tab == index ? palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(.horizontal, 24).padding(.bottom, 14)
            Rectangle().fill(palette.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch tab {
                    case 0: healthPanel
                    case 1: timelinePanel
                    case 2: profilesPanel
                    case 3: outboundPanel
                    case 4: reportPanel
                    default: NetworkConnectivityPage(model: state.networkConnectivity)
                    }
                }.frame(maxWidth: 1180).frame(maxWidth: .infinity).padding(24)
            }
        }.foregroundStyle(palette.text).background(palette.bg)
            .tint(palette.accent)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border))
    }

    private func emptyState(_ title: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(palette.sub)
            Text(title).font(.system(size: 12)).foregroundStyle(palette.sub)
        }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }

    private func latency(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }

    private func metric(_ title: String, icon: String, keyPath: KeyPath<HealthSample, Double?>, color: Color) -> some View {
        let samples = Array(currentHealth.suffix(20))
        let last = samples.last?[keyPath: keyPath]
        let failures = samples.filter { $0[keyPath: keyPath] == nil }.count
        return card {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.sub)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(latency(last)).font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
                Text(last == nil ? "无响应" : "ms").font(.system(size: 12)).foregroundStyle(palette.sub)
                Spacer()
                if !samples.isEmpty {
                    Text("无响应 \(failures * 100 / samples.count)%").font(.system(size: 10)).foregroundStyle(failures > 0 ? palette.up : palette.sub)
                }
            }
            Chart(samples) { sample in
                if let value = sample[keyPath: keyPath] {
                    LineMark(x: .value("时间", sample.date), y: .value("毫秒", value))
                        .foregroundStyle(color).interpolationMethod(.linear)
                    PointMark(x: .value("时间", sample.date), y: .value("毫秒", value)).symbolSize(10).foregroundStyle(color)
                }
            }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 56)
            Text(samples.isEmpty ? "等待首次探测" : "最近 \(samples.count) 次探测")
                .font(.system(size: 10)).foregroundStyle(palette.sub)
        }
    }

    private var healthPanel: some View {
        let latest = currentHealth.last
        let healthy = latest?.diagnosis == "探测正常"
        return VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: latest == nil ? "clock" : (healthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill"))
                    .font(.system(size: 22)).foregroundStyle(healthy ? palette.down : palette.up)
                VStack(alignment: .leading, spacing: 5) {
                    Text(latest?.diagnosis ?? "正在等待网络探测").font(.system(size: 13, weight: .semibold))
                    Text("每 30 秒探测一次 · ICMP 无响应可能由网络限制引起")
                        .font(.system(size: 11)).foregroundStyle(palette.sub)
                }
                Spacer()
                if let latest { Text(latest.date, style: .time).font(.system(size: 11)).foregroundStyle(palette.sub) }
            }.padding(16).background((healthy ? palette.down : palette.up).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 16) {
                metric("网关延迟", icon: "wifi.router", keyPath: \.gatewayMS, color: palette.down)
                metric("外网延迟", icon: "globe", keyPath: \.internetMS, color: palette.accent)
                metric("DNS 查询", icon: "server.rack", keyPath: \.dnsMS, color: palette.up)
            }
            card {
                HStack { Text("探测历史").font(.system(size: 14, weight: .semibold)); Spacer(); Text("当前网络 · 最近 100 条").font(.caption).foregroundStyle(palette.sub) }
                HStack {
                    Text("时间").frame(maxWidth: .infinity, alignment: .leading)
                    Text("网关 / ms").frame(width: 130, alignment: .trailing)
                    Text("外网 / ms").frame(width: 130, alignment: .trailing)
                    Text("DNS / ms").frame(width: 130, alignment: .trailing)
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(palette.sub)
                if currentHealth.isEmpty { emptyState("尚无探测记录", icon: "waveform.path.ecg") }
                LazyVStack(spacing: 0) {
                    ForEach(currentHealth.suffix(100).reversed()) { sample in
                        HStack {
                            Text(sample.date.formatted(date: .abbreviated, time: .standard)).frame(maxWidth: .infinity, alignment: .leading)
                            Text(latency(sample.gatewayMS)).frame(width: 130, alignment: .trailing)
                            Text(latency(sample.internetMS)).frame(width: 130, alignment: .trailing)
                            Text(latency(sample.dnsMS)).frame(width: 130, alignment: .trailing)
                        }.font(.system(size: 11, design: .monospaced)).padding(.vertical, 11)
                        Rectangle().fill(palette.border.opacity(0.6)).frame(height: 1)
                    }
                }
                Text("外网目标 1.1.1.1 · DNS 查询 example.com · 默认 DNS 服务器")
                    .font(.system(size: 10)).foregroundStyle(palette.sub)
            }
        }
    }

    private var rangeControls: some View {
        HStack(spacing: 18) {
            DatePicker("开始", selection: $start).datePickerStyle(.field)
            DatePicker("结束", selection: $end).datePickerStyle(.field).disabled(tab == 1 && liveTimeline)
            Spacer(minLength: 0)
            if tab == 1 { Toggle("实时", isOn: $liveTimeline).toggleStyle(.switch).controlSize(.small) }
            Menu {
                Button("最近一小时") { setRange(hours: 1) }
                Button("最近 24 小时") { setRange(hours: 24) }
                Button("最近七天") { setRange(hours: 168) }
            } label: { Label("快捷时段", systemImage: "clock") }.fixedSize()
        }.font(.system(size: 11)).controlSize(.small)
    }

    private func setRange(hours: Double) {
        end = Date()
        start = end.addingTimeInterval(-hours * 3600)
    }

    private var timelinePanel: some View {
        let timelineEnd = liveTimeline ? Date() : end
        let records = insights.connections.filter { event in
            event.started <= timelineEnd && (event.ended ?? Date()) >= start && (appFilter.isEmpty || event.name.localizedCaseInsensitiveContains(appFilter) || event.app.localizedCaseInsensitiveContains(appFilter))
        }
        let keys = Set(records.map { $0.app })
        let keyFilter: ((String) -> Bool)? = appFilter.isEmpty ? nil : { keys.contains($0) }
        let entries = timelineEntries(records, end: timelineEnd)
        return VStack(spacing: 20) {
            card {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.sub)
                    TextField("搜索应用名称或标识", text: $appFilter).textFieldStyle(.plain)
                    if !appFilter.isEmpty { Button { appFilter = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(palette.sub) }
                }.padding(10).background(palette.bg, in: RoundedRectangle(cornerRadius: 6))
                rangeControls
                if start >= timelineEnd { Text("开始时间应早于结束时间").font(.caption).foregroundStyle(palette.up) }
                MiniSparkline(buckets: state.store.buckets(window: SelectionWindow(start: start, end: max(start.addingTimeInterval(1), timelineEnd)), slots: 100, keyFilter: keyFilter), palette: palette, emptyMessage: "所选时段无流量")
                    .frame(height: 90)
                HStack { Text(start, style: .time); Spacer(); Label("下载", systemImage: "arrow.down").foregroundStyle(palette.down); Label("上传", systemImage: "arrow.up").foregroundStyle(palette.up); Spacer(); Text(timelineEnd, style: .time) }.font(.system(size: 10)).foregroundStyle(palette.sub)
            }
            card {
                HStack {
                    Text("连接与告警").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(entries.count) 条事件").font(.caption).foregroundStyle(palette.sub)
                }
                if entries.isEmpty { emptyState("所选时段暂无匹配事件", icon: "point.3.connected.trianglepath.dotted") }
                LazyVStack(spacing: 0) {
                    ForEach(entries.suffix(500).reversed()) { entry in timelineRow(entry) }
                }
                Text("约 10 秒轮询，可能遗漏短连接。观察中断表示无法确定连接的实际结束时间。")
                    .font(.system(size: 10)).foregroundStyle(palette.sub)
            }
        }
    }

    private func timelineRow(_ entry: TimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.date, format: .dateTime.hour().minute().second()).monospacedDigit()
                Text(entry.date, format: .dateTime.month().day()).font(.system(size: 9))
            }.font(.system(size: 11)).foregroundStyle(palette.sub).frame(width: 72, alignment: .trailing)
            Image(systemName: entry.alert == nil ? "circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: entry.alert == nil ? 7 : 15)).foregroundStyle(entry.alert == nil ? palette.accent : palette.up)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(entry.alert == nil ? palette.sub : palette.up)
                Text(entry.detail).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let alert = entry.alert {
                Button { state.replay(alert) } label: { Label("回放", systemImage: "play.circle") }.controlSize(.small)
            }
        }.padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border.opacity(0.6)).frame(height: 1) }
    }

    private struct TimelineEntry: Identifiable {
        var id: String
        var date: Date
        var title: String
        var detail: String
        var alert: AppAlert?
    }

    private func timelineEntries(_ records: [ConnectionEvent], end: Date) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        for event in records {
            let detail = "\(event.name) · \(event.transport) · \(event.endpoint)"
            if event.started >= start {
                entries.append(TimelineEntry(id: event.id.uuidString + "start", date: event.started, title: "观察到连接", detail: detail))
            }
            if let closed = event.ended, closed >= start, closed <= end {
                entries.append(TimelineEntry(id: event.id.uuidString + "end", date: closed, title: event.interrupted ? "观察中断" : "连接结束", detail: detail))
            }
            if event.started < start && (event.ended ?? Date()) >= start {
                entries.append(TimelineEntry(id: event.id.uuidString + "active", date: start, title: "时段开始时已连接", detail: detail))
            }
        }
        for alert in state.alertCenter.alerts where alert.date >= start && alert.date <= end {
            let matches = appFilter.isEmpty || alert.detail.localizedCaseInsensitiveContains(appFilter) || (alert.snapshot?.contains { $0.name.localizedCaseInsensitiveContains(appFilter) } ?? false)
            if matches { entries.append(TimelineEntry(id: alert.id.uuidString, date: alert.date, title: alert.title, detail: alert.detail, alert: alert)) }
        }
        return entries.sorted { $0.date < $1.date }
    }

    private var profilesPanel: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                card {
                    Label("当前配置", systemImage: "network").font(.system(size: 14, weight: .semibold))
                    Picker("使用配置", selection: Binding(get: { insights.network }, set: { state.selectNetworkProfile($0) })) {
                        ForEach(insights.profiles.keys.sorted(), id: \.self) { key in Text(insights.profiles[key]?.name ?? key).tag(key) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                    Text(state.budgetText).font(.system(size: 12)).foregroundStyle(palette.sub)
                    HStack {
                        Label("\(state.scanner.devices.filter { $0.acknowledged }.count) 台可信设备", systemImage: "checkmark.shield")
                        Spacer()
                        Button("管理设备") { state.page = .things }.controlSize(.small)
                    }.font(.system(size: 11))
                    Text("预算和告警可在设置中修改，设备名称与信任可在设备页修改。")
                        .font(.system(size: 11)).foregroundStyle(palette.sub)
                }
                card {
                    Text("配置名称").font(.system(size: 14, weight: .semibold))
                    TextField("例如，家庭、公司、手机热点", text: $profileName).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("重命名当前配置") {
                            state.saveNetworkProfile()
                            insights.profiles[insights.network]?.name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
                            insights.save()
                        }.disabled(!validProfileName)
                        Spacer()
                        Button("新建并使用") {
                            let key = "manual-" + UUID().uuidString
                            insights.profiles[key] = NetworkProfile(name: profileName.trimmingCharacters(in: .whitespacesAndNewlines))
                            state.selectNetworkProfile(key)
                        }.buttonStyle(.borderedProminent).disabled(!validProfileName)
                    }.controlSize(.small)
                    Text("无法自动区分网络时，可手动选择独立配置。")
                        .font(.system(size: 11)).foregroundStyle(palette.sub)
                }
            }.frame(maxWidth: .infinity)
            card {
                Label("切换记录", systemImage: "arrow.triangle.swap").font(.system(size: 14, weight: .semibold))
                if insights.changes.isEmpty { emptyState("尚无网络切换记录", icon: "network") }
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(insights.changes.suffix(100).reversed()) { change in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(insights.profiles[change.signature]?.name ?? change.description).font(.system(size: 12)).lineLimit(2)
                            Text(change.date.formatted(date: .abbreviated, time: .standard)).font(.system(size: 10)).foregroundStyle(palette.sub)
                        }
                        Rectangle().fill(palette.border).frame(height: 1)
                    }
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private var outboundPanel: some View {
        VStack(spacing: 20) {
            card {
                HStack(spacing: 12) {
                    Image(systemName: outbound.enabled ? "checkmark.shield.fill" : "shield.lefthalf.filled").font(.system(size: 26)).foregroundStyle(outbound.enabled ? palette.down : palette.up)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(outbound.status).font(.system(size: 13, weight: .semibold))
                        Text(outbound.bundled ? "规则作用于新建出站连接" : "当前构建需要已签名的系统扩展才能启用拦截")
                            .font(.system(size: 11)).foregroundStyle(palette.sub)
                    }
                    Spacer()
                    if outbound.enabled { Button("关闭过滤") { outbound.disable() } }
                    else { Button("启用出站过滤") { outbound.activate() }.disabled(!outbound.bundled) }
                }
                DisclosureGroup("规则如何生效") {
                    Text("默认放行未匹配的目标，较新的规则优先。单次允许耗尽或十分钟到期后，规则会阻止后续新连接。既有连接可能继续传输。域名匹配依赖系统提供的主机名，部分连接需要 IP 规则。启用扩展需要 Network Extension 授权和开发者签名。")
                        .font(.system(size: 11)).foregroundStyle(palette.sub).padding(.top, 8)
                }.font(.system(size: 11))
            }
            HStack(alignment: .top, spacing: 20) {
                card {
                    Text("添加规则").font(.system(size: 14, weight: .semibold))
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("应用签名标识").font(.system(size: 11)).foregroundStyle(palette.sub)
                            Spacer()
                            Menu("选择活跃应用") {
                                ForEach(state.appRows) { app in Button(app.name) { appID = app.key } }
                            }.controlSize(.mini)
                        }
                        TextField("com.apple.Safari", text: $appID).textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("目标地址").font(.system(size: 11)).foregroundStyle(palette.sub)
                        TextField("IP、域名、*.example.com 或 *", text: $target).textFieldStyle(.roundedBorder)
                    }
                    Picker("操作", selection: $action) {
                        ForEach(OutboundRule.Action.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Button {
                        outbound.rules.append(OutboundRule(app: appID.trimmingCharacters(in: .whitespacesAndNewlines), target: target.trimmingCharacters(in: .whitespacesAndNewlines), action: action))
                        outbound.save()
                    } label: { Label("保存规则", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).disabled(appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.frame(width: 330)
                card {
                    HStack { Text("已保存规则").font(.system(size: 14, weight: .semibold)); Spacer(); Text("\(outbound.rules.count) 条").font(.caption).foregroundStyle(palette.sub) }
                    if outbound.rules.isEmpty { emptyState("添加应用和目标，创建第一条规则", icon: "shield") }
                    LazyVStack(spacing: 0) {
                        ForEach(outbound.rules.reversed()) { rule in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: rule.action == .block ? "hand.raised.fill" : "clock").foregroundStyle(rule.action == .block ? palette.danger : palette.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(rule.app).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                                    Text(rule.target == "*" ? "所有目标" : rule.target).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.sub).textSelection(.enabled)
                                    Text(rule.action.rawValue).font(.system(size: 10)).foregroundStyle(rule.action == .block ? palette.danger : palette.accent)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Button(role: .destructive) { outbound.rules.removeAll { $0.id == rule.id }; outbound.save() } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("删除规则")
                            }.padding(.vertical, 14)
                            Rectangle().fill(palette.border).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var reportPanel: some View {
        HStack(alignment: .top, spacing: 20) {
            card {
                Label("导出时段", systemImage: "calendar").font(.system(size: 14, weight: .semibold))
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("开始", selection: $start).datePickerStyle(.field)
                    DatePicker("结束", selection: $end).datePickerStyle(.field)
                    HStack {
                        Button("最近一小时") { setRange(hours: 1) }
                        Button("最近 24 小时") { setRange(hours: 24) }
                        Button("七天") { setRange(hours: 168) }
                    }.controlSize(.small)
                }
                if !validRange { Text("开始时间应早于结束时间").font(.caption).foregroundStyle(palette.up) }
                Divider()
                Text("文件包含应用名称、目标 IP 和网络标识，分享前请检查。")
                    .font(.system(size: 11)).foregroundStyle(palette.sub)
                Button { insights.export(state: state, start: start, end: end) } label: {
                    Label("导出 JSON 报告", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!validRange)
                if let error = insights.exportError { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(palette.danger) }
            }.frame(width: 390)
            card {
                Text("报告内容").font(.system(size: 14, weight: .semibold))
                reportItem("网络质量", detail: "延迟、探测无响应与 DNS 查询耗时", icon: "waveform.path.ecg")
                reportItem("应用与连接", detail: "活跃应用流量、连接地址与观察时间", icon: "point.3.connected.trianglepath.dotted")
                reportItem("网络切换", detail: "所选时段的网络与配置切换记录", icon: "network")
                reportItem("告警事件", detail: "流量异常、新目标及其他网络警报", icon: "bell")
            }
        }
    }

    private func reportItem(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(palette.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(palette.sub)
            }
        }.padding(.vertical, 9)
    }
}
