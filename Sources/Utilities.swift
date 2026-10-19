import AppKit
import Darwin
import SwiftUI

// MARK: - Shell

enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (out: String, err: String, code: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch { return ("", "\(error)", -1) }
        let d = o.fileHandleForReading.readDataToEndOfFile()
        let de = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: d, encoding: .utf8) ?? "",
                String(data: de, encoding: .utf8) ?? "",
                p.terminationStatus)
    }

    /// Run a command with administrator privileges (pops the system password dialog).
    static func admin(_ cmd: String, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let escaped = cmd
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let script = "do shell script \"\(escaped)\" with administrator privileges"
            let r = Shell.run("/usr/bin/osascript", ["-e", script])
            let ok = r.code == 0
            DispatchQueue.main.async { completion(ok, ok ? r.out : r.err) }
        }
    }
}

// MARK: - Formatting

enum Fmt {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f
    }()

    static func bytes(_ v: Double) -> String {
        if v <= 0 { return "0 B" }
        return byteFormatter.string(fromByteCount: Int64(v))
    }

    static func bytes(_ v: UInt64) -> String { bytes(Double(v)) }

    static func speed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0 else { return "0 B/s" }
        return byteFormatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }

    static func pct(_ v: Double) -> String {
        String(format: "%.1f%%", v * 100)
    }

    private static let timeShortF: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let timeFullF: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    private static let dayLabelF: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()

    static func timeShort(_ d: Date) -> String { timeShortF.string(from: d) }
    static func timeFull(_ d: Date) -> String { timeFullF.string(from: d) }
    static func dayLabel(_ d: Date) -> String { dayLabelF.string(from: d) }

    static func ago(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前" }
        if s < 86400 { return "\(Int(s / 3600)) 小时前" }
        return "\(Int(s / 86400)) 天前"
    }
}

// MARK: - Persistence helpers

enum Store {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NetGlass", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        let url = dir.appendingPathComponent(name)
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        let url = dir.appendingPathComponent(name)
        guard let d = try? JSONEncoder().encode(value) else { return }
        try? d.write(to: url, options: .atomic)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }
}

// MARK: - IP helpers

enum NetUtil {
    static func isPrivate(_ ip: String) -> Bool {
        if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".").compactMap { Int($0) }
            if parts.count >= 2, parts[1] >= 16, parts[1] <= 31 { return true }
        }
        return false
    }

    static func isLoopback(_ ip: String) -> Bool {
        ip.hasPrefix("127.") || ip == "::1"
    }

    static func isMulticast(_ ip: String) -> Bool {
        ip.hasPrefix("224.") || ip.hasPrefix("239.") || ip.hasPrefix("ff") || ip.hasPrefix("255.255.255")
    }

    static func isUsableRemote(_ ip: String) -> Bool {
        guard !ip.isEmpty, ip != "*" else { return false }
        if isLoopback(ip) || isMulticast(ip) { return false }
        if ip.hasPrefix("169.254") || ip.hasPrefix("fe80") || ip.hasPrefix("0.0.0.0") { return false }
        return true
    }

    static func normalizeMAC(_ raw: String) -> String {
        raw.lowercased()
            .split(separator: ":")
            .map { g -> String in
                let v = UInt8(g, radix: 16) ?? 0
                return String(format: "%02x", v)
            }
            .joined(separator: ":")
    }

    static func ouiKey(_ mac: String) -> String {
        let m = normalizeMAC(mac).replacingOccurrences(of: ":", with: "")
        return m.count >= 6 ? String(m.prefix(6)) : m
    }

    /// Primary active IPv4 interface (prefer en0).
    static func primaryInterface() -> (name: String, ip: String, mask: String)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var fallback: (String, String, String)?
        var ptr = ifaddr
        while let p = ptr {
            let addr = p.pointee.ifa_addr
            defer { ptr = p.pointee.ifa_next }
            guard let addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: p.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("utun") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var mask = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard let net = p.pointee.ifa_netmask else { continue }
            let hr = getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let mr = getnameinfo(net, socklen_t(net.pointee.sa_len), &mask, socklen_t(mask.count), nil, 0, NI_NUMERICHOST)
            guard hr == 0, mr == 0 else { continue }
            let ipStr = String(cString: host)
            if isLoopback(ipStr) { continue }
            let tuple = (name, ipStr, String(cString: mask))
            if name == "en0" { return tuple }
            if fallback == nil { fallback = tuple }
        }
        guard let f = fallback else { return nil }
        return (f.0, f.1, f.2)
    }

    static func defaultGateway() -> String? {
        let r = Shell.run("/sbin/route", ["-n", "get", "default"])
        for line in r.out.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "gateway" {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func dnsServers() -> [String] {
        let r = Shell.run("/usr/sbin/scutil", ["--dns"])
        var out: [String] = []
        for line in r.out.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("nameserver[") {
                if let i = s.firstIndex(of: ":") {
                    let v = s[s.index(after: i)...].trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty, !out.contains(v) { out.append(v) }
                }
            }
        }
        return out
    }

    static func allOwnMACs() -> Set<String> {
        var set = Set<String>()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return set }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            guard let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let dl = addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
            guard dl.sdl_alen == 6 else { continue }
            let mac: String = withUnsafeBytes(of: dl) { buf in
                let n = Int(dl.sdl_nlen)
                return (0..<6).map { String(format: "%02x", buf[n + $0]) }.joined(separator: ":")
            }
            set.insert(mac)
        }
        return set
    }
}

// MARK: - Hostname resolver (async, cached)

final class HostResolver {
    static let shared = HostResolver()
    private var cache: [String: String] = [:]
    private let queue = DispatchQueue(label: "netglass.resolver", qos: .utility)

    func cached(_ ip: String) -> String? { cache[ip] }

    func resolve(_ ip: String, completion: @escaping (String) -> Void) {
        queue.async {
            if let hit = self.cache[ip] {
                DispatchQueue.main.async { completion(hit) }
                return
            }
            let name = Self.lookup(ip)
            self.cache[ip] = name
            DispatchQueue.main.async { completion(name) }
        }
    }

    static func lookup(_ ip: String) -> String {
        var sa = sockaddr_in()
        sa.sin_family = sa_family_t(AF_INET)
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        var addr = in_addr()
        guard inet_pton(AF_INET, ip, &addr) == 1 else { return ip }
        sa.sin_addr = addr
        var host = [CChar](repeating: 0, count: 256)
        let result = withUnsafePointer(to: &sa) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                getnameinfo(saPtr, socklen_t(MemoryLayout<sockaddr_in>.size),
                            &host, socklen_t(host.count), nil, 0, 0)
            }
        }
        guard result == 0 else { return ip }
        let name = String(cString: host).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return name.isEmpty || name == ip ? ip : name
    }
}

// MARK: - OUI vendor database (common prefixes)

enum OUI {
    static let table: [String: String] = [
        "f0:18:98": "Apple", "ac:de:48": "Apple", "00:03:93": "Apple", "00:05:02": "Apple",
        "00:0a:27": "Apple", "00:0d:93": "Apple", "00:10:fa": "Apple", "00:14:51": "Apple",
        "00:16:cb": "Apple", "00:17:f2": "Apple", "00:19:e3": "Apple", "00:1b:63": "Apple",
        "00:1e:52": "Apple", "00:1f:5b": "Apple", "00:1f:f3": "Apple", "00:21:e9": "Apple",
        "00:22:41": "Apple", "00:23:12": "Apple", "00:23:32": "Apple", "00:23:6c": "Apple",
        "00:23:df": "Apple", "00:24:36": "Apple", "00:25:00": "Apple", "00:25:4b": "Apple",
        "00:25:bc": "Apple", "00:26:08": "Apple", "00:26:4a": "Apple", "00:26:b0": "Apple",
        "00:26:bb": "Apple", "00:35:f9": "Apple", "00:50:e4": "Apple", "04:0c:ce": "Apple",
        "10:dd:b1": "Apple", "18:af:61": "Apple", "20:c9:d0": "Apple", "24:a0:74": "Apple",
        "28:6a:ba": "Apple", "2c:be:08": "Apple", "30:b4:9e": "Apple", "34:c0:59": "Apple",
        "38:c9:86": "Apple", "3c:07:54": "Apple", "40:33:1a": "Apple", "44:fb:42": "Apple",
        "48:74:6e": "Apple", "4c:8b:ef": "Apple", "50:32:37": "Apple", "54:26:96": "Apple",
        "58:55:ca": "Apple", "5c:ad:cf": "Apple", "60:03:08": "Apple", "60:d9:c7": "Apple",
        "64:a3:cb": "Apple", "68:a8:6d": "Apple", "6c:19:8f": "Apple", "70:de:e2": "Apple",
        "74:1f:6a": "Apple", "78:31:c1": "Apple", "7c:6d:62": "Apple", "80:e6:50": "Apple",
        "84:38:35": "Apple", "88:53:d4": "Apple", "8c:29:37": "Apple", "90:27:e4": "Apple",
        "98:01:a7": "Apple", "9c:20:7b": "Apple", "a0:99:9b": "Apple", "a4:b8:05": "Apple",
        "a4:d1:8c": "Apple", "a8:88:08": "Apple", "ac:bc:32": "Apple", "b0:34:95": "Apple",
        "b4:18:c1": "Apple", "b8:27:eb": "Raspberry Pi", "bc:52:b7": "Apple", "c0:63:94": "Apple",
        "c4:2c:03": "Apple", "c8:69:cd": "Apple", "cc:08:e0": "Apple", "d0:03:4b": "Apple",
        "d4:90:9c": "Apple", "d8:00:4d": "Apple", "dc:2b:61": "Apple", "dc:9b:9c": "Apple",
        "e0:f8:47": "Apple", "e4:8b:7f": "Apple", "e8:80:2e": "Apple", "ec:35:86": "Apple",
        "f0:18:98": "Apple", "f0:b4:79": "Apple", "f4:1b:a1": "Apple", "f4:f9:51": "Apple",
        "f8:1e:df": "Apple", "f8:ff:c2": "Apple", "fc:25:3f": "Apple",
        "c8:7f:54": "TP-Link", "50:c7:bf": "TP-Link", "14:cc:20": "TP-Link", "a4:2b:8c": "TP-Link",
        "54:c8:0f": "TP-Link", "98:da:c4": "TP-Link", "b0:4e:26": "TP-Link", "c0:25:e9": "TP-Link",
        "14:9d:09": "Huawei", "18:c5:8a": "Huawei", "28:6e:d4": "Huawei", "34:6b:d3": "Huawei",
        "38:f8:89": "Huawei", "40:4e:36": "Huawei", "48:46:fb": "Huawei", "50:01:bb": "Huawei",
        "54:a5:1b": "Huawei", "58:7f:66": "Huawei", "5c:c3:07": "Huawei", "64:16:f0": "Huawei",
        "70:72:3c": "Huawei", "74:a0:63": "Huawei", "78:1d:ba": "Huawei", "80:fb:06": "Huawei",
        "88:40:b3": "Huawei", "8c:be:be": "Huawei", "94:04:9c": "Huawei", "98:e7:f5": "Huawei",
        "ac:61:5a": "Huawei", "b4:30:52": "Huawei", "c8:0c:c8": "Huawei", "d4:40:f0": "Huawei",
        "e0:36:76": "Huawei", "e8:cd:2d": "Huawei", "f4:63:1f": "Huawei", "f8:01:13": "Huawei",
        "fc:48:e6": "Huawei",
        "00:9e:c8": "Xiaomi", "04:cf:8c": "Xiaomi", "0c:1d:af": "Xiaomi", "10:2a:b3": "Xiaomi",
        "14:f6:5a": "Xiaomi", "18:59:36": "Xiaomi", "20:82:c0": "Xiaomi", "28:6c:07": "Xiaomi",
        "30:74:96": "Xiaomi", "34:80:b3": "Xiaomi", "38:a4:ed": "Xiaomi", "3c:bd:d8": "Xiaomi",
        "40:31:3c": "Xiaomi", "44:23:7c": "Xiaomi", "4c:49:e3": "Xiaomi", "50:64:2b": "Xiaomi",
        "54:64:d9": "Xiaomi", "58:44:98": "Xiaomi", "5c:b7:8e": "Xiaomi", "64:09:80": "Xiaomi",
        "64:cc:2e": "Xiaomi", "6c:29:95": "Xiaomi", "70:18:8b": "Xiaomi", "74:23:44": "Xiaomi",
        "78:02:f8": "Xiaomi", "7c:1d:d9": "Xiaomi", "80:ad:16": "Xiaomi", "84:f3:eb": "Xiaomi",
        "88:c3:97": "Xiaomi", "8c:be:be": "Huawei", "94:65:9c": "Xiaomi", "98:fa:e3": "Xiaomi",
        "9c:b6:d0": "Xiaomi", "a4:77:33": "Xiaomi", "ac:c1:ee": "Xiaomi", "b0:e2:35": "Xiaomi",
        "c4:0b:cb": "Xiaomi", "d4:97:0b": "Xiaomi", "e4:46:da": "Xiaomi", "f0:b4:29": "Xiaomi",
        "f4:f5:d8": "Xiaomi", "f8:a4:5f": "Xiaomi", "fc:64:ba": "Xiaomi",
        "00:16:32": "Synology", "00:11:32": "Synology", "90:09:d0": "Synology",
        "00:1b:44": "SanDisk", "00:1d:7e": "Cisco", "00:1e:14": "Cisco", "00:1e:f7": "Cisco",
        "00:25:45": "Cisco", "0c:85:25": "Cisco", "58:97:1e": "Cisco", "68:ef:bd": "Cisco",
        "3c:ce:73": "Cisco", "00:24:6c": "Brother", "00:80:77": "Brother", "30:05:5c": "Brother",
        "00:00:48": "Seiko Epson", "00:1b:a9": "Brother", "00:26:ab": "Epson",
        "00:00:0c": "Cisco", "00:04:5a": "D-Link", "00:05:5d": "D-Link", "00:0d:88": "D-Link",
        "00:13:46": "D-Link", "00:17:9a": "D-Link", "00:1b:11": "D-Link", "00:1f:33": "D-Link",
        "00:22:b0": "D-Link", "00:24:01": "D-Link", "00:26:5a": "D-Link", "14:d6:4d": "D-Link",
        "1c:7e:e5": "D-Link", "34:08:04": "D-Link", "c8:d3:a3": "D-Link",
        "00:0c:29": "VMware", "00:05:69": "VMware", "00:1c:14": "VMware", "00:50:56": "VMware",
        "08:00:27": "Oracle VirtualBox", "0a:00:27": "Oracle VirtualBox",
        "00:1a:11": "Google", "00:1e:59": "Google", "3c:5a:b4": "Google", "54:60:09": "Google",
        "6c:ad:f8": "Google", "f4:f5:e8": "Google", "fc:a1:3e": "Google",
        "00:24:d7": "NETGEAR", "00:26:f2": "NETGEAR", "20:4e:7f": "NETGEAR", "9c:3d:cf": "NETGEAR",
        "a0:40:a0": "NETGEAR", "b0:b9:8a": "NETGEAR", "c4:04:15": "NETGEAR",
        "00:e0:4c": "Realtek", "0c:9d:21": "Realtek", "24:69:68": "Realtek", "52:54:00": "QEMU/KVM",
        "00:1c:42": "Parallels", "00:1f:16": "QNAP", "24:5e:be": "QNAP",
        "18:d6:c7": "Intel", "00:1b:21": "Intel", "00:1d:e0": "Intel", "00:1e:64": "Intel",
        "00:1f:3b": "Intel", "00:22:fa": "Intel", "00:23:14": "Intel", "00:24:d6": "Intel",
        "00:27:10": "Intel", "24:0a:64": "Intel", "24:77:03": "Intel", "3c:97:0e": "Intel",
        "48:51:b7": "Intel", "4c:cc:6a": "Intel", "58:6d:8f": "Intel", "5c:e0:c5": "Intel",
        "60:67:20": "Intel", "74:e6:e2": "Intel", "78:92:9c": "Intel", "7c:5c:f8": "Intel",
        "80:19:34": "Intel", "84:a6:c8": "Intel", "8c:16:45": "Intel", "9c:4e:36": "Intel",
        "a0:36:9f": "Intel", "a4:34:d9": "Intel", "a8:a1:59": "Intel", "ac:7b:a1": "Intel",
        "b4:6b:fc": "Intel", "b8:08:29": "Intel", "c8:f7:50": "Intel", "d0:7e:35": "Intel",
        "d4:3d:7e": "Intel", "d8:fc:f5": "Intel", "dc:53:60": "Intel", "e8:6a:64": "Intel",
        "f0:9f:c2": "Intel", "f4:06:69": "Intel", "f8:16:54": "Intel", "fc:f8:ae": "Intel",
        "00:26:37": "Realtek", "00:e0:b6": "Realtek", "08:10:7a": "Realtek", "0c:84:dc": "Realtek",
        "10:68:3f": "Realtek", "14:da:e9": "Realtek", "18:5e:0f": "Realtek", "20:89:86": "Realtek",
        "28:80:23": "Realtek", "30:cd:a7": "Realtek", "3c:46:d8": "Realtek", "44:8a:5b": "Realtek",
        "4c:cc:34": "Realtek", "54:a5:1b": "Huawei", "60:32:b1": "Realtek", "68:05:ca": "Realtek",
        "6c:fd:b9": "Realtek", "74:a7:8e": "Realtek", "80:3f:5d": "Realtek", "90:e6:ba": "Realtek",
        "b0:6e:bf": "Realtek", "bc:32:59": "Realtek", "c4:6e:1f": "Realtek", "d8:5d:84": "Realtek",
        "e0:3f:49": "Realtek", "f4:2a:7d": "Realtek", "fc:45:96": "Realtek",
        "64:bc:0c": "Espressif", "24:0a:c4": "Espressif", "5c:cf:7f": "Espressif",
        "84:0d:8e": "Espressif", "a4:cf:12": "Espressif", "b4:e6:2d": "Espressif",
        "bc:dd:c2": "Espressif", "ec:fa:bc": "Espressif",
        "00:04:4b": "NVIDIA", "00:16:41": "SHARP", "00:17:c4": "Mitac",
        "00:50:f2": "Microsoft", "7c:ed:8d": "Microsoft", "9c:eb:e8": "Microsoft",
        "28:18:78": "Microsoft", "44:1e:a1": "Microsoft", "50:1f:c6": "Microsoft",
        "00:1d:ba": "Samsung", "00:21:19": "Samsung", "00:23:39": "Samsung", "00:23:99": "Samsung",
        "00:24:54": "Samsung", "00:25:66": "Samsung", "00:26:37": "Realtek", "04:46:65": "Samsung",
        "08:21:ef": "Samsung", "0c:b3:19": "Samsung", "10:68:3f": "Realtek", "14:49:e0": "Samsung",
        "18:22:9e": "Samsung", "1c:62:0c": "Samsung", "20:64:32": "Samsung", "24:db:ed": "Samsung",
        "28:98:13": "Samsung", "2c:ae:2b": "Samsung", "30:96:fb": "Samsung", "34:23:ba": "Samsung",
        "38:01:67": "Samsung", "3c:5a:b4": "Google", "40:0e:85": "Samsung", "44:6d:6c": "Samsung",
        "48:44:f7": "Samsung", "4c:bc:a5": "Samsung", "50:cc:f8": "Samsung", "54:92:be": "Samsung",
        "58:8f:5c": "Samsung", "5c:3c:27": "Samsung", "60:af:6d": "Samsung", "64:b3:10": "Samsung",
        "68:27:37": "Samsung", "6c:2f:2c": "Samsung", "70:f9:27": "Samsung", "74:2f:68": "Samsung",
        "78:25:ad": "Samsung", "7c:0b:c6": "Samsung", "80:18:a7": "Samsung", "84:25:db": "Samsung",
        "88:32:9b": "Samsung", "8c:77:12": "Samsung", "90:18:7c": "Samsung", "94:35:0a": "Samsung",
        "98:0c:82": "Samsung", "9c:02:98": "Samsung", "a0:07:98": "Samsung", "a4:07:b6": "Samsung",
        "a8:06:00": "Samsung", "ac:36:13": "Samsung", "b0:72:bf": "Samsung", "b4:3a:28": "Samsung",
        "b8:5a:73": "Samsung", "bc:72:b1": "Samsung", "c0:bd:d1": "Samsung", "c4:57:6e": "Samsung",
        "c8:ba:94": "Samsung", "cc:07:ab": "Samsung", "d0:22:be": "Samsung", "d4:88:90": "Samsung",
        "d8:90:e8": "Samsung", "dc:71:44": "Samsung", "e0:99:71": "Samsung", "e4:58:b8": "Samsung",
        "e8:50:8b": "Samsung", "ec:1f:72": "Samsung", "f0:25:b7": "Samsung", "f4:7b:5e": "Samsung",
        "f8:04:2e": "Samsung", "fc:f1:36": "Samsung",
        "00:0c:e7": "Motorola", "00:1a:73": "Motorola", "00:23:a2": "Motorola",
        "00:24:37": "Motorola", "34:bb:1c": "Motorola", "44:78:3e": "Motorola",
        "4c:60:de": "Motorola", "54:1f:8a": "Motorola", "5c:da:d5": "Motorola",
        "6c:88:14": "Motorola", "84:3a:4b": "Motorola", "8c:83:d3": "Motorola",
        "a0:57:e7": "Motorola", "b0:86:1e": "Motorola", "bc:8c:cd": "Motorola",
        "c8:64:c2": "Motorola", "d8:5d:4c": "Motorola", "e0:05:c5": "Motorola",
        "f0:ef:86": "Motorola", "fc:75:16": "Motorola",
        "00:23:31": "OnePlus", "04:4b:ed": "OnePlus", "0c:1a:0b": "OnePlus", "10:68:3f": "Realtek",
        "18:b4:30": "OnePlus", "2c:10:c1": "OnePlus", "38:2d:c7": "OnePlus", "3c:2a:f4": "OnePlus",
        "44:23:7c": "Xiaomi", "48:74:6e": "Apple", "4c:66:41": "OnePlus", "58:1f:28": "OnePlus",
        "64:a2:f9": "OnePlus", "6c:b7:49": "OnePlus", "78:f5:fd": "OnePlus", "88:29:fc": "OnePlus",
        "8c:1f:64": "OnePlus", "9c:5a:81": "OnePlus", "a0:1c:6b": "OnePlus", "a4:be:2b": "OnePlus",
        "b2:3c:9e": "OnePlus", "c0:11:73": "OnePlus", "c8:5c:37": "OnePlus", "d4:61:2e": "OnePlus",
        "e4:5f:01": "OnePlus", "f0:a4:55": "OnePlus", "fc:36:2b": "OnePlus",
        "24:db:ac": "ASUS", "00:0c:6e": "ASUS", "00:0e:a6": "ASUS", "00:1a:92": "ASUS",
        "00:1b:fc": "ASUS", "00:1d:60": "ASUS", "00:1e:8c": "ASUS", "00:1f:c6": "ASUS",
        "00:22:15": "ASUS", "00:23:54": "ASUS", "00:24:8c": "ASUS", "00:25:22": "ASUS",
        "00:26:18": "ASUS", "04:d9:f5": "ASUS", "08:60:6e": "ASUS", "0c:5b:8f": "ASUS",
        "10:bf:48": "ASUS", "14:da:e9": "Realtek", "1c:87:2c": "ASUS", "20:cf:30": "ASUS",
        "24:4b:fe": "ASUS", "2c:4d:54": "ASUS", "30:5a:3a": "ASUS", "33:33:33": "IPv6 mcast",
        "38:2c:4a": "ASUS", "40:b0:fa": "ASUS", "48:5b:39": "ASUS", "50:46:5d": "ASUS",
        "54:04:a6": "ASUS", "58:7e:61": "ASUS", "6c:b0:ce": "ASUS", "74:d0:2b": "ASUS",
        "88:d7:f6": "ASUS", "90:e6:ba": "Realtek", "94:e9:79": "ASUS", "a0:f3:c1": "ASUS",
        "ac:22:0b": "ASUS", "b0:6e:bf": "Realtek", "bc:ae:c5": "ASUS", "c8:60:00": "ASUS",
        "d0:17:c2": "ASUS", "d4:5d:64": "ASUS", "d8:50:e6": "ASUS", "e0:3f:49": "Realtek",
        "f0:79:59": "ASUS", "f4:6d:04": "ASUS", "f8:32:e4": "ASUS", "fc:ec:da": "ASUS",
        "00:18:e7": "ZTE", "00:1f:e2": "ZTE", "00:25:93": "ZTE", "00:26:ed": "ZTE",
        "04:02:1f": "ZTE", "08:57:00": "ZTE", "0c:37:dc": "ZTE", "10:c6:1f": "ZTE",
        "18:64:72": "ZTE", "1c:26:0d": "ZTE", "34:4b:50": "ZTE", "38:a5:43": "ZTE",
        "40:cb:a8": "ZTE", "4c:09:b4": "ZTE", "50:01:0a": "ZTE", "54:22:f8": "ZTE",
        "5c:30:d8": "ZTE", "64:16:f0": "Huawei", "6c:e0:c1": "ZTE", "78:11:dc": "ZTE",
        "7c:0b:c6": "Samsung", "84:5b:12": "ZTE", "8c:e8:e9": "ZTE", "94:db:c9": "ZTE",
        "9c:c1:72": "ZTE", "a4:e9:75": "ZTE", "ac:22:0b": "ASUS", "b0:41:83": "ZTE",
        "c0:3d:d9": "ZTE", "cc:e1:d5": "ZTE", "d0:22:be": "Samsung", "dc:56:e7": "ZTE",
        "e4:68:e3": "ZTE", "f4:6a:92": "ZTE", "fc:a8:21": "ZTE",
    ]

    static func vendor(for mac: String) -> String {
        table[NetUtil.ouiKey(mac)] ?? "未知厂商"
    }
}

// MARK: - Misc

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
    min(max(v, lo), hi)
}

extension NSImage {
    func resized(_ size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        draw(in: NSRect(origin: .zero, size: size))
        img.unlockFocus()
        return img
    }
}
