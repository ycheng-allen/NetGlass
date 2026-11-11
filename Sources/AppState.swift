import AppKit
import Foundation
import ServiceManagement

final class AppState: ObservableObject {
    enum Page: Int, CaseIterable {
        case graph = 0, usage, things, firewall, alerts, diagnosis

        var title: String {
            switch self {
            case .graph: return "图表"
            case .usage: return "用量"
            case .things: return "设备"
            case .firewall: return "防火墙"
            case .alerts: return "警报"
            case .diagnosis: return "诊断"
            }
        }

        var icon: String {
            switch self {
            case .graph: return "chart.xyaxis.line"
            case .usage: return "chart.pie.fill"
            case .things: return "point.3.connected.trianglepath.dotted"
            case .firewall: return "flame.fill"
            case .alerts: return "bell.fill"
            case .diagnosis: return "waveform.path.ecg"
            }
        }
    }

    @Published var page: Page = .graph
    @Published var settings: AppSettings {
        didSet {
            Store.save(settings, "config.json")
            applySettings(old: oldValue)
        }
    }
    @Published var paused = false { didSet { insights.paused = paused } }
    @Published var liveDown: Double = 0
    @Published var liveUp: Double = 0

    let outbound = OutboundFirewall()
    let insights = NetworkInsights()
    private var currentProfile = ""
    let store = TrafficStore()
    let scanner = DeviceScanner()
    let firewall = FirewallManager()
    let alertCenter = AlertCenter()
    let identity = AppIdentity.shared

    // Selection window
    @Published var selection: SelectionWindow
    @Published var followNow = true
    @Published var historyStart = Date().addingTimeInterval(-3600)

    // Computed for UI
    @Published var graphBuckets: [Bucket] = []
    @Published var overview: [Bucket] = []
    @Published var windowTotal = Delta()
    @Published var appRows: [AppRow] = []
    @Published var hostRows: [HostRow] = []
    /// Non-nil when the stacked graph mode is on (top-5 apps + "其他").
    @Published var stackedSeries: StackedSeries?

    // Live details
    @Published var hostNames: [String: String] = [:]
    @Published var activeAppConns: [String: Int] = [:]   // app key -> active remote conn count
    @Published var activeHostsForApp: [String: [String]] = [:]
    @Published var activeSocketsForApp: [String: [String]] = [:]   // app key -> "ip:port"
    /// Per-app per-host byte totals (RAM, session lifetime) for the drill-down view.
    @Published var appHostTotals: [String: [String: Delta]] = [:]

    // Engine
    private var prevCum: [String: (UInt64, UInt64)] = [:]
    private var lastHosts: [String: Set<String>] = [:]
    private var lastRates: [String: (Double, Double)] = [:]
    private var spikeHistory: [[Double]] = [[], []]
    private var budgetNotified = Store.load([String].self, "budget-alerts.json") ?? []
    private var lastSpikeAlert: Date?
    private var lastDNS: [String] = []
    private var knownApps: [String: Date] = [:]
    private var baselineSeeded = false
    /// appKey -> [host: firstSeen], persisted; drives "new host" alerts
    private var knownAppHosts: [String: [String: Date]] = [:]
    private var appHostsSeeded = false
    private var scanCounter = 0
    private var sampleTimer: Timer?
    private var otherTimers: [Timer] = []
    private let samplerQueue = DispatchQueue(label: "netglass.sampler", qos: .utility)

    init() {
        settings = AppSettings.load()
        let now = Date()
        selection = SelectionWindow(start: now.addingTimeInterval(-3 * 3600), end: now)
        store.loadFromDisk(retention: settings.retentionDays)
        knownApps = Store.load([String: Date].self, "apps.json") ?? [:]
        baselineSeeded = Store.load(Bool.self, "apps-baseline.json") ?? false
        knownAppHosts = Store.load([String: [String: Date]].self, "apphosts.json") ?? [:]
        appHostsSeeded = Store.load(Bool.self, "apphosts-baseline.json") ?? false
    }

    func start() {
        insights.onNetworkChange = { [weak self] key, description in self?.switchNetwork(key, description: description) }
        insights.onHealthChange = { [weak self] diagnosis in
            guard let self, self.settings.alertSpike else { return }
            self.alertCenter.add(.spike, title: "网络健康变化", detail: diagnosis)
        }
        insights.start()
        alertCenter.requestAuth()
        alertCenter.onOpen = { [weak self] in self?.replay($0) }

        scanner.onNewDevice = { [weak self] dev in
            guard let self, self.settings.alertNewDevice else { return }
            self.alertCenter.add(.newDevice, title: "发现新设备",
                                 detail: "\(dev.ip)（\(dev.vendor)）加入局域网 · MAC \(dev.mac)")
        }
        scanner.onARPAlert = { [weak self] msg in
            guard let self, self.settings.alertARPSpoof else { return }
            self.alertCenter.add(.arp, title: "ARP 异常", detail: msg)
        }

        firewall.refresh()
        scanner.scan(full: false)
        lastDNS = NetUtil.dnsServers()
        historyStart = store.firstSampleDate() ?? Date().addingTimeInterval(-3600)

        recomputeWindow()
        scheduleTimers()
        sampleTick()
    }

    func saveNetworkProfile() {
        guard !currentProfile.isEmpty else { return }
        var profile = insights.profiles[currentProfile] ?? NetworkProfile()
        profile.budgetGB = settings.budgetGB
        profile.billingDay = settings.billingDay
        profile.alertNewHost = settings.alertNewHost
        profile.alertSpike = settings.alertSpike
        profile.alertOptions = ["newApp": settings.alertNewApp, "newDevice": settings.alertNewDevice, "dns": settings.alertDNSChange, "arp": settings.alertARPSpoof, "firewall": settings.alertFirewallChange, "behavior": settings.alertBehavior]
        profile.devices = scanner.devices
        insights.profiles[currentProfile] = profile
    }

    func selectNetworkProfile(_ key: String) {
        guard key != currentProfile else { return }
        insights.assignments[insights.detectedNetwork] = key
        insights.network = key
        insights.changes.append(NetworkChange(date: Date(), signature: key, description: "手动选择网络配置"))
        switchNetwork(key, description: insights.networkDescription)
    }

    private func switchNetwork(_ key: String, description: String) {
        saveNetworkProfile()
        currentProfile = key
        let profile = insights.profiles[key] ?? NetworkProfile(name: description, budgetGB: settings.budgetGB, billingDay: settings.billingDay, alertNewHost: settings.alertNewHost, alertSpike: settings.alertSpike)
        insights.profiles[key] = profile
        var config = settings
        config.budgetGB = profile.budgetGB
        config.billingDay = profile.billingDay
        config.alertNewHost = profile.alertNewHost
        config.alertSpike = profile.alertSpike
        config.alertNewApp = profile.alertOptions?["newApp"] ?? config.alertNewApp
        config.alertNewDevice = profile.alertOptions?["newDevice"] ?? config.alertNewDevice
        config.alertDNSChange = profile.alertOptions?["dns"] ?? config.alertDNSChange
        config.alertARPSpoof = profile.alertOptions?["arp"] ?? config.alertARPSpoof
        config.alertFirewallChange = profile.alertOptions?["firewall"] ?? config.alertFirewallChange
        config.alertBehavior = profile.alertOptions?["behavior"] ?? config.alertBehavior
        settings = config
        scanner.activateNetwork(key, devices: profile.devices)
        scanner.scan(full: true)
        insights.save()
    }

    // MARK: Timers

    private func scheduleTimers() {
        sampleTimer?.invalidate()
        otherTimers.forEach { $0.invalidate() }
        otherTimers.removeAll()

        let s = Timer(timeInterval: settings.sampleInterval, repeats: true) { [weak self] _ in
            self?.sampleTick()
        }
        RunLoop.main.add(s, forMode: .common)
        sampleTimer = s

        let make: (TimeInterval, @escaping () -> Void) -> Timer = { interval, block in
            let t = Timer(timeInterval: interval, repeats: true) { _ in block() }
            RunLoop.main.add(t, forMode: .common)
            return t
        }
        otherTimers.append(make(10) { [weak self] in self?.lsofTick() })
        otherTimers.append(make(120) { [weak self] in self?.scanTick() })
        otherTimers.append(make(60) { [weak self] in self?.persistTick() })
        otherTimers.append(make(300) { [weak self] in self?.dnsTick() })
    }

    private func applySettings(old: AppSettings) {
        if old.sampleInterval != settings.sampleInterval {
            scheduleTimers()
        }
        if old.retentionDays != settings.retentionDays {
            store.pruneDays(retention: settings.retentionDays)
        }
        switch settings.appearance {
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .system: NSApp.appearance = nil
        }
        applyLaunchAtLogin()
        recomputeWindow()
    }

    private func applyLaunchAtLogin() {
        do {
            if settings.launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Not fatal (unsigned builds may be denied); keep UI value as-is.
        }
    }

    // MARK: Sampling

    func sampleTick() {
        guard !paused else { return }
        samplerQueue.async { [weak self] in
            guard let self else { return }
            let t = Date()
            let procs = NetTopSampler.sample()
            guard !procs.isEmpty else { return }

            // Resolve to stable app keys (serial queue => pid cache is safe)
            var byKey: [String: (UInt64, UInt64)] = [:]
            var pidKey: [pid_t: String] = [:]
            for p in procs {
                let key = self.identity.key(forPid: p.pid, procName: p.procName)
                pidKey[p.pid] = key
                var cur = byKey[key] ?? (0, 0)
                cur.0 &+= p.cumIn
                cur.1 &+= p.cumOut
                byKey[key] = cur
            }

            var appDeltas: [String: Delta] = [:]
            var hostDeltas: [String: Delta] = [:]
            var appHostDeltas: [String: [String: Delta]] = [:]
            var rates: [String: (Double, Double)] = [:]
            let dt = self.settings.sampleInterval

            for (key, cum) in byKey {
                var dIn: UInt64 = 0, dOut: UInt64 = 0
                if let prev = self.prevCum[key], cum.0 >= prev.0, cum.1 >= prev.1 {
                    dIn = cum.0 - prev.0
                    dOut = cum.1 - prev.1
                }
                self.prevCum[key] = cum
                guard dIn > 0 || dOut > 0 else { continue }
                let d = Delta(down: dIn, up: dOut)
                appDeltas[key] = d
                rates[key] = (Double(dIn) / dt, Double(dOut) / dt)

                // Distribute across this app's known remote hosts
                let hosts = self.lastHosts[key] ?? []
                if !hosts.isEmpty {
                    let shareIn = dIn / UInt64(hosts.count)
                    let shareOut = dOut / UInt64(hosts.count)
                    for h in hosts {
                        let share = Delta(down: shareIn, up: shareOut)
                        hostDeltas[h, default: Delta()].add(share)
                        appHostDeltas[key, default: [:]][h, default: Delta()].add(share)
                    }
                }
            }

            DispatchQueue.main.async {
                self.applySample(t: t, appDeltas: appDeltas, hostDeltas: hostDeltas,
                                 appHostDeltas: appHostDeltas, rates: rates)
            }
        }
    }

    private func applySample(t: Date, appDeltas: [String: Delta], hostDeltas: [String: Delta],
                             appHostDeltas: [String: [String: Delta]], rates: [String: (Double, Double)]) {
        store.record(t: t, apps: appDeltas, hosts: hostDeltas)
        insights.recordTraffic(appDeltas, date: t)
        insights.recordUploads(rates, alert: alertCenter, enabled: settings.alertBehavior)
        lastRates = rates
        for (key, hosts) in appHostDeltas {
            var bucket = appHostTotals[key] ?? [:]
            for (ip, d) in hosts { bucket[ip, default: Delta()].add(d) }
            appHostTotals[key] = bucket
        }

        let down = appDeltas.values.reduce(0.0) { $0 + Double($1.down) } / max(settings.sampleInterval, 0.5)
        let up = appDeltas.values.reduce(0.0) { $0 + Double($1.up) } / max(settings.sampleInterval, 0.5)
        liveDown = liveDown == 0 ? down : liveDown * 0.6 + down * 0.4
        liveUp = liveUp == 0 ? up : liveUp * 0.6 + up * 0.4

        checkSpike(down: down, up: up, rates: rates)
        checkBudget()
        checkNewApps(appDeltas: appDeltas)

        // Resolve hostnames lazily
        for ip in hostDeltas.keys where hostNames[ip] == nil {
            hostNames[ip] = ip
            HostResolver.shared.resolve(ip) { [weak self] name in
                self?.hostNames[ip] = name
            }
        }

        if followNow {
            let span = selection.span
            selection = SelectionWindow(start: t.addingTimeInterval(-span), end: t)
        }
        if t.timeIntervalSince1970 - historyStart.timeIntervalSince1970 > 60 {
            historyStart = store.firstSampleDate() ?? t.addingTimeInterval(-3600)
        }
        recomputeWindow()
    }

    private func checkSpike(down: Double, up: Double, rates: [String: (Double, Double)]) {
        guard settings.alertSpike else { return }
        for (index, value) in [down, up].enumerated() {
            let history = spikeHistory[index]
            spikeHistory[index].append(value)
            if spikeHistory[index].count > 120 { spikeHistory[index].removeFirst() }
            guard history.count >= 20 else { continue }
            let mean = history.reduce(0, +) / Double(history.count)
            let sigma = (history.reduce(0) { $0 + pow($1 - mean, 2) } / Double(history.count)).squareRoot()
            guard value > mean + settings.spikeSigma * sigma, value > settings.spikeFloorBytes else { continue }
            guard lastSpikeAlert.map({ Date().timeIntervalSince($0) >= 600 }) ?? true else { continue }
            lastSpikeAlert = Date()
            let top = rates.sorted { (index == 0 ? $0.value.0 : $0.value.1) > (index == 0 ? $1.value.0 : $1.value.1) }.prefix(3).map {
                SpikeApp(name: identity.meta(for: $0.key).name, down: $0.value.0, up: $0.value.1)
            }
            alertCenter.add(.spike, title: index == 0 ? "下载流量异常" : "上传流量异常",
                detail: "当前 \(Fmt.speed(value))，近期均值 \(Fmt.speed(mean))", snapshot: top)
        }
    }

    var budgetStart: Date {
        let cal = Calendar.current
        let now = Date()
        let month = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let start = cal.date(byAdding: .day, value: min(max(settings.billingDay, 1), 28) - 1, to: month)!
        return start <= now ? start : cal.date(byAdding: .month, value: -1, to: start)!
    }

    var budgetUsed: UInt64 {
        (insights.usage[insights.network] ?? [:]).filter { Double($0.key) >= budgetStart.timeIntervalSince1970 }.values.reduce(UInt64(0)) { $0 + $1.total }
    }

    var budgetText: String {
        guard settings.budgetGB > 0 else { return "未设置流量预算" }
        let limit = settings.budgetGB * 1_000_000_000
        return "本期已用 \(Fmt.bytes(budgetUsed)) · 剩余 \(Fmt.bytes(UInt64(max(0, limit - Double(budgetUsed)))))"
    }

    private func checkBudget() {
        guard settings.budgetGB > 0 else { return }
        for threshold in [80, 100] {
            let key = "\(insights.network)-\(Int(budgetStart.timeIntervalSince1970))-\(settings.budgetGB)-\(threshold)"
            if Double(budgetUsed) >= settings.budgetGB * 1_000_000_000 * Double(threshold) / 100, !budgetNotified.contains(key) {
                budgetNotified.append(key)
                Store.save(budgetNotified, "budget-alerts.json")
                alertCenter.add(.spike, title: "流量预算已用 \(threshold)%", detail: budgetText)
            }
        }
    }

    func replay(_ alert: AppAlert) {
        followNow = false
        selection = SelectionWindow(start: alert.date.addingTimeInterval(-30), end: alert.date.addingTimeInterval(30))
        page = .graph
        recomputeWindow()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    private func checkNewApps(appDeltas: [String: Delta]) {
        var changed = false
        for key in appDeltas.keys where knownApps[key] == nil {
            if baselineSeeded, settings.alertNewApp {
                let meta = identity.meta(for: key)
                alertCenter.add(.newApp, title: "新应用开始联网",
                                detail: "\(meta.name) 首次产生网络流量")
                if settings.autoBlockNewApp, let path = meta.bundlePath {
                    firewall.ensureApp(path: path)
                }
            }
            knownApps[key] = Date()
            changed = true
        }
        if !baselineSeeded && knownApps.count > 0 {
            baselineSeeded = true
            Store.save(baselineSeeded, "apps-baseline.json")
        }
        if changed {
            Store.save(knownApps, "apps.json")
        }
    }

    // MARK: lsof connections

    private func lsofTick() {
        guard !paused else { return }
        samplerQueue.async { [weak self] in
            guard let self else { return }
            let conns = LSOF.connections()
            var observed: [(String, String, String, String)] = []
            var keyConns: [String: Int] = [:]
            var keyHosts: [String: Set<String>] = [:]
            var keySockets: [String: Set<String>] = [:]
            for c in conns {
                let key = self.identity.key(forPid: c.pid, procName: c.cmd)
                for socket in c.sockets {
                    let parts = socket.split(separator: "|", maxSplits: 1).map(String.init)
                    observed.append((key, self.identity.meta(for: key).name, parts.last ?? socket, parts.count > 1 ? parts[0] : "未知"))
                }
                keyConns[key, default: 0] += c.remotes.count
                keyHosts[key, default: []].formUnion(c.remotes)
                keySockets[key, default: []].formUnion(c.sockets)
            }
            DispatchQueue.main.async {
                self.insights.recordConnections(observed, alert: self.alertCenter, enabled: self.settings.alertBehavior)
                self.activeAppConns = keyConns
                self.lastHosts = keyHosts
                self.activeHostsForApp = keyHosts.mapValues { Array($0).sorted() }
                self.activeSocketsForApp = keySockets.mapValues { $0.map { $0.replacingOccurrences(of: "|", with: " ") }.sorted() }
                self.checkNewHosts(keyHosts: keyHosts)
            }
        }
    }

    /// Alert when an app reaches out to a remote host it has never talked to before.
    private func checkNewHosts(keyHosts: [String: Set<String>]) {
        var changed = false
        for (key, hosts) in keyHosts {
            for ip in hosts where knownAppHosts[key]?[ip] == nil {
                if appHostsSeeded, settings.alertNewHost {
                    let meta = identity.meta(for: key)
                    let host = hostNames[ip] ?? ip
                    let where_ = NetUtil.isPrivate(ip) ? "内网" : "公网"
                    alertCenter.add(.newHost, title: "应用访问新主机",
                                    detail: "\(meta.name) 首次连接 \(host)（\(where_)）")
                }
                knownAppHosts[key, default: [:]][ip] = Date()
                changed = true
            }
        }
        if !appHostsSeeded && !knownAppHosts.isEmpty {
            appHostsSeeded = true
            Store.save(appHostsSeeded, "apphosts-baseline.json")
        }
        if changed {
            Store.save(knownAppHosts, "apphosts.json")
        }
    }

    // MARK: Other ticks

    private func scanTick() {
        scanCounter += 1
        scanner.scan(full: scanCounter % 5 == 0)
    }

    private func persistTick() {
        saveNetworkProfile()
        insights.save()
        store.saveToDisk()
        Store.save(knownApps, "apps.json")
    }

    private func dnsTick() {
        let dns = NetUtil.dnsServers()
        if !lastDNS.isEmpty && dns != lastDNS && settings.alertDNSChange {
            alertCenter.add(.dns, title: "DNS 服务器变更",
                            detail: "\(lastDNS.joined(separator: ", ")) → \(dns.joined(separator: ", "))")
        }
        lastDNS = dns
    }

    // MARK: Window computation

    func recomputeWindow() {
        graphBuckets = store.buckets(window: selection)
        overview = store.overviewBuckets(retentionDays: settings.retentionDays)
        windowTotal = store.total(window: selection)

        let totals = store.appTotals(window: selection)
        let grand = max(Double(windowTotal.total), 1)

        // Stacked per-app series (top-5 + 其他) when the mode is on
        if settings.graphStacked {
            let top = totals.sorted { $0.value.total > $1.value.total }.prefix(5)
            let keys = top.map { $0.key }
            let mutKeys = Array(keys)
            let values = store.stackedTotals(window: selection, keys: mutKeys, slots: graphBuckets.count)
            var names = mutKeys.map { identity.meta(for: $0).name }
            var series = values
            if !series.isEmpty {
                // "其他" = total (down+up per slot) minus the top-5 layers
                var other = [Double](repeating: 0, count: graphBuckets.count)
                for (i, b) in graphBuckets.enumerated() {
                    let topSum = series.reduce(0.0) { $0 + ($1.indices.contains(i) ? $1[i] : 0) }
                    other[i] = max(b.down + b.up - topSum, 0)
                }
                names.append("其他")
                series.append(other)
            }
            stackedSeries = StackedSeries(names: names, values: series)
        } else {
            stackedSeries = nil
        }

        var rows: [AppRow] = totals.map { key, d in
            let meta = identity.meta(for: key)
            let r = lastRates[key] ?? (0, 0)
            return AppRow(key: key, name: meta.name, icon: meta.icon,
                          down: d.down, up: d.up,
                          rate: r.0 + r.1,
                          share: Double(d.total) / grand,
                          isSystem: meta.isSystem)
        }
        rows.sort { $0.down + $0.up > $1.down + $1.up }
        appRows = rows

        let hostTotals = store.hostTotals(window: selection)
        var hrows: [HostRow] = hostTotals.map { ip, d in
            HostRow(ip: ip, name: hostNames[ip] ?? ip, down: d.down, up: d.up,
                    share: Double(d.total) / grand)
        }
        hrows.sort { $0.down + $0.up > $1.down + $1.up }
        hostRows = Array(hrows.prefix(24))
    }

    // MARK: Actions

    func setPreset(_ span: TimeInterval) {
        let end = Date()
        selection = SelectionWindow(start: end.addingTimeInterval(-span), end: end)
        followNow = true
        recomputeWindow()
    }

    func setSelection(start: Date, end: Date) {
        selection = SelectionWindow(start: start, end: end)
        followNow = end.timeIntervalSinceNow > -2
        recomputeWindow()
    }

    func togglePause() {
        paused.toggle()
    }

    func resetAllData() {
        insights.resetHistory()
        budgetNotified.removeAll()
        Store.save(budgetNotified, "budget-alerts.json")
        store.reset()
        scanner.reset()
        alertCenter.clear()
        knownApps.removeAll()
        knownAppHosts.removeAll()
        appHostTotals.removeAll()
        baselineSeeded = true
        appHostsSeeded = true
        Store.save(baselineSeeded, "apps-baseline.json")
        Store.save(knownApps, "apps.json")
        Store.save(appHostsSeeded, "apphosts-baseline.json")
        Store.save(knownAppHosts, "apphosts.json")
        recomputeWindow()
    }

    var topAppName: String? {
        appRows.first?.name
    }
}

