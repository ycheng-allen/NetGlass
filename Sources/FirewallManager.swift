import AppKit
import Foundation

final class FirewallManager: ObservableObject {
    @Published var globalOn: Bool = false
    @Published var firewallApps: [String: FWBlockState] = [:]  // app path -> state
    @Published var busy = false
    @Published var lastError: String?

    private let bin = "/usr/libexec/ApplicationFirewall/socketfilterfw"

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let st = Shell.run(self.bin, ["--getglobalstate"])
            let on = st.out.contains("State = 1") || st.out.contains("State = 2")
            var apps: [String: FWBlockState] = [:]
            let list = Shell.run(self.bin, ["--listapps"])
            // Lines like:  1    Allow   /Applications/Safari.app/Contents/MacOS/Safari (Safari)
            for line in list.out.split(separator: "\n") {
                let s = line.trimmingCharacters(in: .whitespaces)
                guard let m = s.range(of: #"^(\d+)\s+(Allow|Block)\s+(.+?)\s+\((.*)\)$"#,
                                      options: .regularExpression) else { continue }
                let full = String(s[m])
                guard let stateRange = full.range(of: "Allow|Block", options: .regularExpression),
                      let pathMatch = full.range(of: #"/.*\("#, options: .regularExpression)
                else { continue }
                let state = full[stateRange].lowercased() == "block" ? FWBlockState.block : .allow
                var path = String(full[pathMatch])
                path = String(path.dropLast()) // trailing "("
                apps[path] = state
            }
            DispatchQueue.main.async {
                self.globalOn = on
                self.firewallApps = apps
                self.lastError = (st.code != 0 && st.err.contains("not authorized")) ? "需要管理员权限" : nil
            }
        }
    }

    func setGlobal(_ on: Bool) {
        busy = true
        Shell.admin("\(bin) --setglobalstate \(on ? "on" : "off")") { [weak self] ok, msg in
            self?.busy = false
            self?.lastError = ok ? nil : msg
            self?.refresh()
        }
    }

    /// state: nil = remove from firewall list.
    func setApp(path: String, to state: FWBlockState?) {
        busy = true
        var cmd: String
        switch state {
        case .block: cmd = "\(bin) --blockapp \"\(path)\""
        case .allow: cmd = "\(bin) --unblockapp \"\(path)\""
        case .unknown, nil: cmd = "\(bin) --removeapp \"\(path)\""
        }
        Shell.admin(cmd) { [weak self] ok, msg in
            self?.busy = false
            self?.lastError = ok ? nil : msg
            self?.refresh()
        }
    }

    /// Ensure an app is present in the firewall list (added as allowed).
    func ensureApp(path: String) {
        guard firewallApps[path] == nil else { return }
        Shell.admin("\(bin) --addapp \"\(path)\"") { [weak self] _, _ in
            self?.refresh()
        }
    }

    /// Merge live per-app connection activity into display rows.
    func rows(activeApps: [(name: String, path: String?, conns: Int, rate: Double, icon: NSImage?)]) -> [FWAppRow] {
        var rows: [FWAppRow] = []
        var seenPaths = Set<String>()
        for a in activeApps {
            let state: FWBlockState
            if let p = a.path, let s = firewallApps[p] {
                state = s
            } else {
                state = .unknown
            }
            rows.append(FWAppRow(path: a.path ?? "proc:" + a.name, name: a.name,
                                 state: state, activeConnections: a.conns,
                                 rate: a.rate, icon: a.icon))
            if let p = a.path { seenPaths.insert(p) }
        }
        // Include firewall-listed apps that aren't currently active
        for (path, state) in firewallApps where !seenPaths.contains(path) {
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            rows.append(FWAppRow(path: path, name: name, state: state,
                                 activeConnections: 0, rate: 0,
                                 icon: NSWorkspace.shared.icon(forFile: path)))
        }
        return rows.sorted { $0.rate > $1.rate }
    }
}
