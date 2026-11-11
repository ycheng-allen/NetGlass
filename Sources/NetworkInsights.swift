import AppKit
import Foundation
import Network
import SystemConfiguration

struct HealthSample: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var network: String
    var gatewayMS: Double?
    var internetMS: Double?
    var dnsMS: Double?
    var diagnosis: String
}

struct ConnectionEvent: Codable, Identifiable {
    var id = UUID()
    var app: String
    var name: String
    var endpoint: String
    var transport: String
    var started: Date
    var ended: Date?
    var interrupted: Bool = false
}

struct NetworkChange: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var signature: String
    var description: String
}

struct NetworkProfile: Codable {
    var name = "新网络"
    var budgetGB: Double = 0
    var billingDay = 1
    var alertNewHost = true
    var alertSpike = true
    var trustedDevices: [String] = []
    var devices: [Device] = []
    var alertOptions: [String: Bool]?
}

final class NetworkInsights: ObservableObject {
    @Published var health = Store.load([HealthSample].self, "health.json") ?? []
    @Published var connections = Store.load([ConnectionEvent].self, "connections.json") ?? []
    @Published var changes = Store.load([NetworkChange].self, "networks.json") ?? []
    @Published var profiles = Store.load([String: NetworkProfile].self, "profiles.json") ?? [:]
    var usage = Store.load([String: [Int: Delta]].self, "network-usage.json") ?? [:]
    @Published var detectedNetwork = ""
    var assignments = Store.load([String: String].self, "network-profile-map.json") ?? [:]
    @Published var network = ""
    @Published var networkDescription = "正在识别网络"
    @Published var probing = false
    @Published var exportError: String?
    var paused = false
    var onHealthChange: ((String) -> Void)?
    var onNetworkChange: ((String, String) -> Void)?
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "netglass.health")
    private var timer: Timer?
    private var active: [String: UUID] = [:]
    private var connectionCounts = Store.load([String: [Int]].self, "connection-baselines.json") ?? [:]
    private var appVersions = Store.load([String: String].self, "app-versions.json") ?? [:]
    private var uploadHistory = Store.load([String: [Double]].self, "upload-baselines.json") ?? [:]
    private var cooldown: [String: Date] = [:]

    init() {
        // A process restart leaves the exact closing time unobserved.
        for index in connections.indices where connections[index].ended == nil {
            connections[index].ended = Store.load(Date.self, "connections-last-seen.json") ?? connections[index].started
            connections[index].interrupted = true
        }
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let interfaces = path.availableInterfaces.filter { path.usesInterfaceType($0.type) }
            let label = Array(Set(interfaces.map { "\($0.type) \($0.name)" })).sorted().joined(separator: ", ")
            let wifi = SCDynamicStoreCopyValue(nil, "State:/Network/Interface/en0/AirPort" as CFString) as? [String: Any]
            let ssid = wifi?["SSID_STR"] as? String ?? ""
            let gateway = NetUtil.defaultGateway() ?? "无网关"
            let ip = NetUtil.primaryInterface()?.ip ?? "无地址"
            let signature = "\(label)|\(ssid)|\(gateway)|\(ip.split(separator: ".").dropLast().joined(separator: "."))"
            DispatchQueue.main.async {
                guard let self, signature != self.detectedNetwork else { return }
                self.detectedNetwork = signature
                self.network = self.assignments[signature] ?? signature
                self.networkDescription = "\(label) \(ssid) · \(gateway)"
                self.changes.append(NetworkChange(date: Date(), signature: self.network, description: self.networkDescription))
                self.changes = Array(self.changes.suffix(1000))
                self.onNetworkChange?(self.network, self.networkDescription)
                self.save()
                self.probe()
            }
        }
        monitor.start(queue: queue)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.probe() }
    }

    static func ping(_ host: String) -> Double? {
        let result = Shell.run("/sbin/ping", ["-n", "-c", "1", "-W", "1500", host])
        guard result.code == 0, let range = result.out.range(of: #"time[=<]([0-9.]+)"#, options: .regularExpression) else { return nil }
        return Double(result.out[range].dropFirst(5))
    }

    func probe() {
        guard !probing, !paused else { return }
        probing = true
        let signature = network
        queue.async {
            let gateway = NetUtil.defaultGateway().flatMap(Self.ping)
            let external = Self.ping("1.1.1.1")
            let dns = Shell.run("/usr/bin/dig", ["+tries=1", "+time=2", "+stats", "example.com"])
            let dnsMS: Double?
            if dns.code == 0, dns.out.contains("status: NOERROR"), let range = dns.out.range(of: #"Query time: [0-9]+"#, options: .regularExpression) {
                dnsMS = Double(dns.out[range].dropFirst(12))
            } else { dnsMS = nil }
            let diagnosis: String
            if NetUtil.primaryInterface() == nil { diagnosis = "本地链路未连接，检查 Wi-Fi 或网线" }
            else if external != nil && dnsMS == nil { diagnosis = "外网探测可达，DNS 解析可能异常" }
            else if external == nil && gateway != nil { diagnosis = "网关可达，外网或 ICMP 探测可能受限" }
            else if external == nil { diagnosis = "网关和外网探测均无响应，检查本地链路、路由器或探测限制" }
            else if let gateway, gateway > 100 { diagnosis = "网关延迟偏高，可能存在 Wi-Fi 干扰或路由器拥塞" }
            else { diagnosis = "探测正常" }
            DispatchQueue.main.async {
                self.probing = false
                guard signature == self.network else { return }
                let previous = self.health.last
                if diagnosis != "探测正常", previous?.diagnosis != diagnosis {
                    self.onHealthChange?(diagnosis)
                }
                self.health.append(HealthSample(date: Date(), network: signature, gatewayMS: gateway, internetMS: external, dnsMS: dnsMS, diagnosis: diagnosis))
                self.health = self.health.filter { $0.date > Date().addingTimeInterval(-7 * 86400) }
                self.save()
            }
        }
    }

    func recordConnections(_ observed: [(String, String, String, String)], alert: AlertCenter, enabled: Bool) {
        let now = Date()
        var seen = Set<String>()
        var counts: [String: Int] = [:]
        for (app, name, endpoint, transport) in observed {
            let key = "\(app)|\(transport)|\(endpoint)"
            guard seen.insert(key).inserted else { continue }
            counts[app, default: 0] += 1
            if active[key] == nil {
                let event = ConnectionEvent(app: app, name: name, endpoint: endpoint, transport: transport, started: now)
                active[key] = event.id
                connections.append(event)
            }
        }
        for (key, id) in active where !seen.contains(key) {
            if let index = connections.firstIndex(where: { $0.id == id }) { connections[index].ended = now }
            active.removeValue(forKey: key)
        }
        for app in Set(counts.keys).union(connectionCounts.keys) {
            let count = counts[app] ?? 0
            let meta = AppIdentity.shared.meta(for: app)
            let version = meta.bundlePath.flatMap { Bundle(path: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
            let updated = version != nil && appVersions[app] != nil && appVersions[app] != version
            let history = connectionCounts[app] ?? []
            if enabled, history.count >= 12 {
                let mean = Double(history.reduce(0, +)) / Double(history.count)
                if Double(count) > max(10, mean * 3) {
                    notify(app + "connections", title: "应用连接数明显增加", detail: "\(meta.name)\(updated ? " 更新至 " + (version ?? "") + " 后" : "") 当前 \(count) 个连接，近期均值 \(Int(mean))", center: alert)
                }
            }
            if let version { appVersions[app] = version }
            connectionCounts[app] = Array((history + [count]).suffix(120))
        }
        connections = connections.filter { $0.ended == nil || $0.started > now.addingTimeInterval(-7 * 86400) }
        if connections.count > 20000 {
            let closed = connections.filter { $0.ended != nil }.suffix(max(0, 20000 - active.count))
            connections = Array(closed) + connections.filter { $0.ended == nil }
        }
        save()
    }

    func recordTraffic(_ apps: [String: Delta], date: Date) {
        guard !network.isEmpty else { return }
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        for delta in apps.values { usage[network, default: [:]][day, default: Delta()].add(delta) }
        let cutoff = Int(date.addingTimeInterval(-90 * 86400).timeIntervalSince1970)
        for key in usage.keys { usage[key] = usage[key]?.filter { $0.key >= cutoff } }
    }

    func recordUploads(_ rates: [String: (Double, Double)], alert: AlertCenter, enabled: Bool) {
        for app in Set(rates.keys).union(uploadHistory.keys) {
            let rate = rates[app] ?? (0, 0)
            let history = uploadHistory[app] ?? []
            if enabled, history.count >= 30 {
                let mean = history.reduce(0, +) / Double(history.count)
                if rate.1 > max(262144, mean * 5) {
                    notify(app + "upload", title: "应用上传行为变化", detail: "\(AppIdentity.shared.meta(for: app).name) 上传 \(Fmt.speed(rate.1))，近期均值 \(Fmt.speed(mean))", center: alert)
                }
            }
            uploadHistory[app] = Array((history + [rate.1]).suffix(120))
        }
    }

    private func notify(_ key: String, title: String, detail: String, center: AlertCenter) {
        guard cooldown[key].map({ Date().timeIntervalSince($0) > 600 }) ?? true else { return }
        cooldown[key] = Date()
        center.add(.spike, title: title, detail: detail)
    }

    func resetHistory() {
        health.removeAll()
        connections.removeAll()
        changes.removeAll()
        usage.removeAll()
        active.removeAll()
        connectionCounts.removeAll()
        uploadHistory.removeAll()
        appVersions.removeAll()
        cooldown.removeAll()
        for key in profiles.keys { profiles[key]?.devices = [] }
        save()
    }

    func save() {
        Store.save(assignments, "network-profile-map.json")
        Store.save(connectionCounts, "connection-baselines.json")
        Store.save(uploadHistory, "upload-baselines.json")
        Store.save(appVersions, "app-versions.json")
        Store.save(Date(), "connections-last-seen.json")
        Store.save(usage, "network-usage.json")
        Store.save(health, "health.json")
        Store.save(connections, "connections.json")
        Store.save(changes, "networks.json")
        Store.save(profiles, "profiles.json")
    }

    func export(state: AppState, start: Date, end: Date) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NetGlass-诊断报告.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        struct Report: Encodable {
            var start: Date
            var end: Date
            var notes: String
            var health: [HealthSample]
            var connections: [ConnectionEvent]
            var networks: [NetworkChange]
            var traffic: [String: Delta]
            var alerts: [AppAlert]
        }
        let report = Report(start: start, end: end,
            notes: "包含应用名、远端地址和网络标识，分享前请检查。连接时间为约10秒轮询观察时间，可能漏掉短连接。ICMP无响应不能单独证明断网。DNS为默认解析服务器的查询耗时。流量仅包含监控期间数据，较长时段使用日汇总。",
            health: health.filter { $0.date >= start && $0.date <= end },
            connections: connections.filter { $0.started <= end && ($0.ended ?? Date()) >= start },
            networks: changes.filter { $0.date >= start && $0.date <= end },
            traffic: state.store.appTotals(window: SelectionWindow(start: start, end: end)),
            alerts: state.alertCenter.alerts.filter { $0.date >= start && $0.date <= end })
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: url, options: .atomic)
            exportError = nil
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { exportError = error.localizedDescription }
    }
}
