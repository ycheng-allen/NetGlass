import AppKit
import Foundation

// MARK: - nettop sampler (cumulative per-process bytes)

struct ProcCum {
    var pid: pid_t
    var procName: String
    var cumIn: UInt64
    var cumOut: UInt64
}

enum NetTopSampler {
    static func sample() -> [ProcCum] {
        let r = Shell.run("/usr/bin/nettop", ["-P", "-L", "1", "-J", "bytes_in,bytes_out"])
        guard r.code == 0, !r.out.isEmpty else { return [] }
        var result: [ProcCum] = []
        var first = true
        for line in r.out.split(separator: "\n") {
            if first { first = false; continue }  // header line ",bytes_in,bytes_out,"
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let procField = String(fields[0])
            guard let dotIdx = procField.lastIndex(of: ".") else { continue }
            let pidStr = procField[procField.index(after: dotIdx)...]
            guard let pid = pid_t(pidStr), pid > 0 else { continue }
            let name = String(procField[..<dotIdx])
            let inV = UInt64(fields[1].trimmingCharacters(in: .whitespaces)) ?? 0
            let outV = UInt64(fields[2].trimmingCharacters(in: .whitespaces)) ?? 0
            result.append(ProcCum(pid: pid, procName: name, cumIn: inV, cumOut: outV))
        }
        return result
    }
}

// MARK: - lsof sampler (pid -> remote hosts)

struct PidConn {
    var pid: pid_t
    var cmd: String
    var remotes: Set<String>       // remote IPs
    var sockets: Set<String>       // "ip:port"
}

enum LSOF {
    static func connections() -> [PidConn] {
        let r = Shell.run("/usr/sbin/lsof", ["-nP", "-i", "-F", "pcn"])
        guard r.code == 0 || r.code == 1 else { return [] }
        var out: [Int: PidConn] = [:]
        var currentPid: Int?
        for line in r.out.split(separator: "\n") {
            guard line.count > 1 else { continue }
            let tag = line.first!
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                currentPid = Int(value)
                if let pid = currentPid, out[pid] == nil {
                    out[pid] = PidConn(pid: pid_t(pid), cmd: "", remotes: [], sockets: [])
                }
            case "c":
                if let pid = currentPid { out[pid]?.cmd = value }
            case "n":
                guard let pid = currentPid else { continue }
                guard let arrow = value.range(of: "->") else { continue }
                let remotePart = String(value[arrow.upperBound...])
                guard let colon = remotePart.lastIndex(of: ":") else { continue }
                var ip = String(remotePart[..<colon])
                if ip.hasPrefix("[") && ip.hasSuffix("]") {
                    ip = String(ip.dropFirst().dropLast())
                }
                let port = remotePart[remotePart.index(after: colon)...]
                guard NetUtil.isUsableRemote(ip) else { continue }
                out[pid]?.remotes.insert(ip)
                if !port.isEmpty {
                    out[pid]?.sockets.insert("\(ip):\(port)")
                }
            default:
                break
            }
        }
        return Array(out.values).filter { !$0.remotes.isEmpty }
    }
}

// MARK: - App identity (pid -> stable key / display name / icon)

final class AppIdentity: ObservableObject {
    static let shared = AppIdentity()

    @Published var metas: [String: AppMeta] = [:]
    private var pidCache: [pid_t: String] = [:]
    private var pendingMeta: Set<String> = []

    /// Called from the sampler serial queue. Reads pid -> bundle info (thread-safe),
    /// resolves icons on the main queue.
    func key(forPid pid: pid_t, procName: String) -> String {
        var key: String
        if let cached = pidCache[pid] {
            key = cached
        } else {
            key = procName
            var name = Self.friendlyName(procName)
            var path: String?
            var isSystem = procName.hasPrefix("com.apple") || Self.systemNames.contains(procName.lowercased())

            if let app = NSRunningApplication(processIdentifier: pid) {
                if let bid = app.bundleIdentifier { key = bid }
                if let url = app.bundleURL {
                    path = url.path
                    if let bid = Bundle(url: url)?.bundleIdentifier { key = bid }
                    name = app.localizedName ?? name
                }
            } else {
                // daemon / helper — attribute to an installed app by name prefix
                if procName.lowercased().contains("webkit") {
                    name = "Safari"
                    path = "/Applications/Safari.app"
                }
                if let match = Self.matchInstalledApp(procName) {
                    name = match.name
                    path = match.path
                }
            }
            pidCache[pid] = key

            if !pendingMeta.contains(key) {
                pendingMeta.insert(key)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    defer { self.pendingMeta.remove(key) }
                    if self.metas[key] != nil { return }
                    var m = AppMeta(key: key, name: name, icon: nil, bundlePath: path, isSystem: isSystem)
                    if let p = path {
                        m.icon = NSWorkspace.shared.icon(forFile: p)
                    } else {
                        m.icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ExecutableBinaryIcon.icns")
                    }
                    self.metas[key] = m
                }
            }
        }
        return key
    }

    func meta(for key: String) -> AppMeta {
        metas[key] ?? AppMeta(key: key, name: Self.friendlyName(key), icon: nil,
                              bundlePath: nil, isSystem: key.hasPrefix("com.apple"))
    }

    static func friendlyName(_ raw: String) -> String {
        var n = raw
        if n.hasPrefix("com.") {
            n = n.split(separator: ".").dropFirst(2).joined(separator: " ")
        }
        n = n.replacingOccurrences(of: "_", with: " ")
        if n.contains("WebKit") { n = "Safari" }
        if n.isEmpty { n = "未知进程" }
        return n
    }

    /// Installed applications, longest name first — for prefix-matching helper
    /// processes (nettop truncates names, e.g. "Google Chrome H").
    static let installedApps: [(prefix: String, name: String, path: String)] = {
        var out: [(String, String, String)] = []
        let fm = FileManager.default
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let appName = (item as NSString).deletingPathExtension
                out.append((appName.lowercased(), appName, dir + "/" + item))
            }
        }
        return out.sorted { $0.0.count > $1.0.count }
    }()

    static func matchInstalledApp(_ procName: String) -> (name: String, path: String)? {
        let lower = procName.lowercased()
        for app in installedApps where lower.hasPrefix(app.prefix) {
            return (app.name, app.path)
        }
        return nil
    }

    private static let systemNames: Set<String> = [
        "kernel", "launchd", "mds", "mds stores", "syslogd", "apsd", "airportd", "symptomsd",
        "mdnsresponder", "configd", "distnoted", "trustd", "secinitd", "nsurlsessiond",
        "nsurlstoraged", "cfprefsd", "diagnosticsd", "hidd", "bluetoothd", "wifiagent",
        "networkd", "networkserviceproxy", "discoveryd", "weatherd", "syncdefaultsd",
        "vpnagentd", "anyconnect", "acwebsecagent", "coreservicesd", "powerd", "cloudd",
        "identityservicesd", "imagent", "bird", "findmydeviced", "remoted", "rapportd",
        "sharingd", "usernoted", "coreautha", "sharing", "dock", "finder", "spotlight",
        "spotlightnethelper", "searchpartyd", "dasd", "universalcontrol", "sidecard",
        "handoff", "coresync", "screensharingd", "appleevents", "mediaremoted",
    ]
}
