import Foundation

final class DeviceScanner: ObservableObject {
    @Published var devices: [Device] = []
    @Published var lastScan: Date?
    @Published var scanning = false

    var onNewDevice: ((Device) -> Void)?
    var onARPAlert: ((String) -> Void)?

    private var store: [String: Device] = [:]   // mac (or "ip-x") -> device
    private var ownIPs: Set<String> = []
    private var knownGatewayMAC: String?
    private var nameRequested: Set<String> = []
    /// True when arp is readable; when false we fall back to TCP discovery (no MACs).
    private var arpAvailable = true

    init() {
        if let saved = Store.load([String: Device].self, "devices.json") {
            store = saved
            devices = saved.values.sorted { $0.lastSeen > $1.lastSeen }
        }
        if let iface = NetUtil.primaryInterface() {
            ownIPs.insert(iface.ip)
        }
    }

    private func persist() {
        Store.save(store, "devices.json")
    }

    // MARK: Host table

    /// Reads the kernel's host routes (`netstat -rn`). Lines like
    /// `10.9.0.2  6c:fe:54:39:78:78  UHLWIi  en0` carry the neighbor's MAC —
    /// this is the ARP table equivalent that stays readable for GUI apps on
    /// macOS 26+, where `arp -a` output is gated by local-network permission.
    private func neighborTable() -> [(ip: String, mac: String)] {
        let r = Shell.run("/usr/sbin/netstat", ["-rn", "-f", "inet"])
        var out: [(String, String)] = []
        for line in r.out.split(separator: "\n") {
            let parts = line.split(separator: " ").filter { !$0.isEmpty }
            guard parts.count >= 3 else { continue }
            let dest = String(parts[0])
            let gw = String(parts[1])
            let ip = dest.hasSuffix("/32") ? String(dest.dropLast(3)) : dest
            guard ip.split(separator: ".").count == 4 else { continue }
            guard gw.range(of: #"^[0-9a-f]{1,2}(:[0-9a-f]{1,2}){5}$"#,
                            options: [.regularExpression, .caseInsensitive]) != nil else { continue }
            let mac = NetUtil.normalizeMAC(gw)
            guard mac.count >= 14 else { continue }
            out.append((ip, mac))
        }
        return out
    }

    // MARK: TCP sweep — works even when UDP/ARP are gated

    private static let probePorts: [UInt16] = [80, 445, 62078]

    /// Non-blocking connect; "refused" or instant host-unreach means the host is alive.
    private func tcpProbe(ip: String, port: UInt16, timeoutMs: Int32) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        var sa = sockaddr_in()
        sa.sin_family = sa_family_t(AF_INET)
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &sa.sin_addr) == 1 else { return false }
        let r = withUnsafePointer(to: &sa) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if r == 0 { return true }
        guard errno == EINPROGRESS else {
            // ECONNREFUSED / EHOSTUNREACH arriving synchronously — host answered or routed instantly
            return errno == ECONNREFUSED
        }
        var pr = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let rc = poll(&pr, 1, timeoutMs)
        guard rc > 0 else { return false }   // timeout => treat as absent
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        // connected, refused, or instant-unreachable all indicate a live host
        return err == 0 || err == ECONNREFUSED || err == EHOSTUNREACH
    }

    private func tcpSweep(baseIP: String) -> Set<String> {
        let parts = baseIP.split(separator: ".")
        guard parts.count == 4 else { return [] }
        let prefix = parts.dropLast().joined(separator: ".")
        let found = DispatchQueue(label: "netglass.sweep").sync { () -> Set<String> in
            var alive = Set<String>()
            let group = DispatchGroup()
            let sem = DispatchSemaphore(value: 64)
            let queue = DispatchQueue.global(qos: .utility)
            let lock = NSLock()
            for i in 1...254 {
                let ip = "\(prefix).\(i)"
                if ownIPs.contains(ip) { continue }
                queue.async {
                    sem.wait()
                    defer { sem.signal() }
                    group.enter()
                    defer { group.leave() }
                    var live = false
                    for port in Self.probePorts {
                        if self.tcpProbe(ip: ip, port: port, timeoutMs: 600) {
                            live = true
                            break
                        }
                    }
                    if live {
                        lock.lock()
                        alive.insert(ip)
                        lock.unlock()
                    }
                }
            }
            group.wait()
            return alive
        }
        return found
    }

    // MARK: Scan

    func scan(full: Bool) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.scanning = true }
            LANNudge.send()

            var discovered = self.neighborTable()
            if discovered.isEmpty {
                self.arpAvailable = false
                if full, let iface = NetUtil.primaryInterface() {
                    for ip in self.tcpSweep(baseIP: iface.ip) {
                        discovered.append((ip, ""))
                    }
                } else {
                    // light scan: refresh devices already known
                    discovered = self.store.values.map { ($0.ip, $0.mac) }
                }
            } else if full, let iface = NetUtil.primaryInterface() {
                // enrich active peers with idle-but-alive hosts on our /24
                for ip in self.tcpSweep(baseIP: iface.ip) where !discovered.contains(where: { $0.ip == ip }) {
                    discovered.append((ip, ""))
                }
            }
            self.arpAvailable = true

            // The gateway usually drops TCP probes — always include it explicitly.
            if let gw = NetUtil.defaultGateway(), !discovered.contains(where: { $0.ip == gw }) {
                discovered.append((gw, ""))
            }

            self.merge(discovered: discovered)
            DispatchQueue.main.async {
                self.scanning = false
                self.lastScan = Date()
            }
        }
    }

    private func merge(discovered: [(ip: String, mac: String)]) {
        let gateway = NetUtil.defaultGateway()
        let now = Date()
        var newDevices: [Device] = []
        var ipOwners: [String: Set<String>] = [:]

        var seen: [String: (ip: String, mac: String)] = [:]
        for entry in discovered {
            let mac = entry.mac
            if !mac.isEmpty {
                let firstOctet = Int(mac.split(separator: ":").first ?? "ff", radix: 16) ?? 255
                if firstOctet & 1 == 1 { continue }               // multicast
                if mac == "ff:ff:ff:ff:ff:ff" { continue }
            }
            if ownIPs.contains(entry.ip) { continue }
            seen[entry.ip] = (entry.ip, mac)
            if !mac.isEmpty {
                ipOwners[entry.ip, default: []].insert(mac)
            }
        }

        for (ip, mac) in seen.values {
            let isGateway = (ip == gateway)
            let key = mac.isEmpty ? "ip-" + ip : mac
            var dev: Device
            if let existing = store[key] {
                dev = existing
                dev.ip = ip
                dev.lastSeen = now
                dev.isGateway = isGateway
            } else {
                dev = Device(mac: mac, ip: ip, name: "", vendor: mac.isEmpty ? "未识别（系统限制）" : OUI.vendor(for: mac),
                             firstSeen: now, lastSeen: now, isGateway: isGateway)
                store[key] = dev
                if isGateway {
                    dev.acknowledged = true // gateways are expected, don't alarm
                } else {
                    newDevices.append(dev)
                }
            }
            store[key] = dev

            if isGateway && !mac.isEmpty {
                if let known = knownGatewayMAC, known != mac {
                    onARPAlert?("网关 \(ip) 的 MAC 地址发生变化: \(known) → \(mac)，疑似 ARP 欺骗")
                }
                knownGatewayMAC = mac
            }
        }

        // Duplicate IP with different MACs => possible ARP spoofing
        for (ip, macs) in ipOwners where macs.count > 1 {
            onARPAlert?("IP \(ip) 同时对应多个 MAC（\(macs.sorted().joined(separator: ", "))），疑似 ARP 欺骗")
        }

        // Resolve names for new / unnamed devices
        for (key, dev) in store where dev.name.isEmpty && !nameRequested.contains(dev.ip) {
            nameRequested.insert(dev.ip)
            let ip = dev.ip
            HostResolver.shared.resolve(ip) { [weak self] name in
                guard let self else { return }
                if name != ip {
                    var d = self.store[key]
                    let short = name.components(separatedBy: ".").first ?? name
                    d?.name = short
                    if let d { self.store[key] = d }
                    DispatchQueue.main.async {
                        self.devices = self.store.values.sorted { $0.lastSeen > $1.lastSeen }
                    }
                }
            }
        }

        DispatchQueue.main.async {
            self.devices = self.store.values.sorted { $0.lastSeen > $1.lastSeen }
        }
        persist()

        for dev in newDevices {
            onNewDevice?(dev)
        }
    }

    func acknowledgeAll() {
        for (k, var d) in store {
            d.acknowledged = true
            store[k] = d
        }
        DispatchQueue.main.async {
            self.devices = self.store.values.sorted { $0.lastSeen > $1.lastSeen }
        }
        persist()
    }

    func reset() {
        store.removeAll()
        devices = []
        knownGatewayMAC = nil
        persist()
    }
}
