import SwiftUI

// MARK: - Things page (LAN devices)

struct ThingsPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    private var P: Palette { Palette.for(scheme) }

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("局域网设备")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(P.text)
                Text("\(state.scanner.devices.count) 台")
                    .font(.system(size: 12))
                    .foregroundColor(P.sub)
                if state.scanner.scanning {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
                Spacer()
                if let last = state.scanner.lastScan {
                    Text("上次扫描: \(Fmt.ago(last))")
                        .font(.system(size: 11))
                        .foregroundColor(P.sub)
                }
                Button {
                    state.scanner.scan(full: true)
                } label: {
                    Label("扫描网络", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundColor(P.accent)
                }
                .buttonStyle(.plain)
                .disabled(state.scanner.scanning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if state.scanner.devices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 34))
                        .foregroundColor(P.sub.opacity(0.5))
                    Text(state.scanner.scanning ? "正在扫描…" : "尚未发现设备")
                        .font(.system(size: 13))
                        .foregroundColor(P.sub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(state.scanner.devices) { dev in
                            DeviceCard(dev: dev, P: P)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(P.bg)
    }
}

struct DeviceCard: View {
    var dev: Device
    var P: Palette
    @Environment(\.colorScheme) var scheme

    private var isNew: Bool {
        !dev.acknowledged && Date().timeIntervalSince(dev.firstSeen) < 7 * 86400
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: dev.kindIcon)
                    .font(.system(size: 19))
                    .foregroundColor(P.accent)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(P.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(dev.name.isEmpty ? dev.ip : dev.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(P.text)
                            .lineLimit(1)
                        if dev.isGateway {
                            badge("网关", P.accent)
                        }
                        if isNew {
                            badge("新设备", P.danger)
                        }
                    }
                    Text(dev.vendor)
                        .font(.system(size: 10))
                        .foregroundColor(P.sub)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                mono(dev.ip)
                if !dev.mac.isEmpty {
                    mono(dev.mac)
                }
            }
            HStack(spacing: 12) {
                Text("首次发现 \(Fmt.dayLabel(dev.firstSeen))")
                Spacer()
                Text("最近 \(Fmt.ago(dev.lastSeen))")
            }
            .font(.system(size: 9))
            .foregroundColor(P.sub.opacity(0.8))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.border))
    }

    private func mono(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(P.sub)
            .lineLimit(1)
            .textSelection(.enabled)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - Firewall page

struct FirewallPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    @State private var query = ""
    @State private var expanded: String?
    private var P: Palette { Palette.for(scheme) }

    private var rows: [FWAppRow] {
        let active = state.appRows.map { r -> (String, String?, Int, Double, NSImage?) in
            let meta = state.identity.meta(for: r.key)
            let conns = state.activeAppConns[r.key] ?? 0
            return (meta.name, meta.bundlePath, conns, r.rate, meta.icon)
        }
        let all = state.firewall.rows(activeApps: active.map {
            (name: $0.0, path: $0.1, conns: $0.2, rate: $0.3, icon: $0.4)
        })
        if query.isEmpty { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(P.sub)
                TextField("搜索应用…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(P.text)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 7).fill(P.card))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(P.border))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if let err = state.firewall.lastError, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(P.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                    if rows.isEmpty {
                        Text("暂无联网应用")
                            .font(.system(size: 12))
                            .foregroundColor(P.sub)
                            .padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
        }
        .background(P.bg)
        .onAppear { state.firewall.refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("应用防火墙")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(P.text)
            HStack(spacing: 6) {
                Circle()
                    .fill(state.firewall.globalOn ? P.down : P.danger)
                    .frame(width: 7, height: 7)
                Text(state.firewall.globalOn ? "已启用" : "未启用")
                    .font(.system(size: 11))
                    .foregroundColor(P.sub)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(P.card))
            .overlay(Capsule().strokeBorder(P.border))

            Button {
                state.firewall.setGlobal(!state.firewall.globalOn)
            } label: {
                Text(state.firewall.globalOn ? "关闭防火墙" : "启用防火墙")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(P.accent)
            }
            .buttonStyle(.plain)
            .disabled(state.firewall.busy)

            Text("点击火焰阻止 / 放行应用联网 · 基于 macOS 内置应用防火墙（需管理员密码）")
                .font(.system(size: 10))
                .foregroundColor(P.sub.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func rowView(_ row: FWAppRow) -> some View {
        let isExpanded = expanded == row.id
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Group {
                    if let img = row.icon { Image(nsImage: img).resizable() }
                    else { Image(systemName: "app.fill").resizable() }
                }
                .frame(width: 24, height: 24)
                .cornerRadius(5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(P.text)
                        .lineLimit(1)
                    if row.path.hasPrefix("/") {
                        Text(row.path)
                            .font(.system(size: 9))
                            .foregroundColor(P.sub.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()

                if row.activeConnections > 0 {
                    Text("\(row.activeConnections) 个连接")
                        .font(.system(size: 10))
                        .foregroundColor(P.sub)
                }
                if row.rate > 1 {
                    Text(Fmt.speed(row.rate))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(P.down)
                }

                stateBadge(row.state)

                flameButton(row)

                Button {
                    expanded = isExpanded ? nil : row.id
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(P.sub)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .buttonStyle(.plain)
                .disabled((state.activeHostsForApp.first { state.identity.meta(for: $0.key).name == row.name }?.value.isEmpty ?? true)
                          && row.activeConnections == 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                let hosts = hostsFor(row)
                if !hosts.isEmpty { expanded = isExpanded ? nil : row.id }
            }

            if isExpanded {
                let hosts = hostsFor(row)
                if !hosts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(hosts, id: \.self) { h in
                            Text("· \(h)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(P.sub)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 46)
                    .padding(.bottom, 10)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.border))
    }

    private func hostsFor(_ row: FWAppRow) -> [String] {
        for (key, hosts) in state.activeHostsForApp {
            if state.identity.meta(for: key).name == row.name {
                return hosts.map { state.hostNames[$0] ?? $0 }
            }
        }
        return []
    }

    // MARK: GlassWire-style flame toggle

    private func flameButton(_ row: FWAppRow) -> some View {
        let managed = row.path.hasPrefix("/")
        let blocked = row.state == .block
        return FlameToggle(palette: P, blocked: blocked, managed: managed,
                           busy: state.firewall.busy,
                           action: { state.firewall.setApp(path: row.path, to: blocked ? .allow : .block) })
            .help(flameHelp(row))
            .contextMenu {
                if managed {
                    Button("从防火墙移除") { state.firewall.setApp(path: row.path, to: nil) }
                }
            }
    }

    private func flameHelp(_ row: FWAppRow) -> String {
        guard row.path.hasPrefix("/") else { return "系统进程：无法通过应用防火墙管理" }
        switch row.state {
        case .block: return "已阻止联网 — 点击放行（需管理员密码）"
        case .allow: return "已放行 — 点击阻止联网（需管理员密码）"
        case .unknown: return "点击加入防火墙并阻止联网（需管理员密码）"
        }
    }

    private func stateBadge(_ s: FWBlockState) -> some View {
        let color: Color = s == .block ? P.danger : (s == .allow ? P.down : P.sub)
        return Text(s.rawValue)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
