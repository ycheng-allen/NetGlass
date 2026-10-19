import SwiftUI
import AppKit

// MARK: - Usage page

final class UsageModel: ObservableObject {
    enum Scope: String, CaseIterable {
        case day = "日", week = "周", month = "月"
    }
    @Published var scope: Scope = .day
    @Published var offset = 0   // 0 = current period, -1 = previous...

    var periodStart: Date {
        let cal = Calendar.current
        let now = cal.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        switch scope {
        case .day:
            return cal.startOfDay(for: now)
        case .week:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            return cal.date(from: comps) ?? cal.startOfDay(for: now)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: now)
            return cal.date(from: comps) ?? cal.startOfDay(for: now)
        }
    }

    var periodEnd: Date {
        let cal = Calendar.current
        switch scope {
        case .day:
            return periodStart.addingTimeInterval(86400)
        case .week:
            return periodStart.addingTimeInterval(7 * 86400)
        case .month:
            return cal.date(byAdding: .month, value: 1, to: periodStart) ?? periodStart.addingTimeInterval(30 * 86400)
        }
    }

    var label: String {
        let f: DateFormatter
        switch scope {
        case .day:
            f = DateFormatter(); f.dateFormat = "yyyy-MM-dd EEEE"; f.locale = Locale(identifier: "zh_CN")
            return f.string(from: periodStart)
        case .week:
            f = DateFormatter(); f.dateFormat = "MM-dd"; f.locale = Locale(identifier: "zh_CN")
            return "\(f.string(from: periodStart)) ~ \(f.string(from: periodEnd.addingTimeInterval(-86400)))"
        case .month:
            f = DateFormatter(); f.dateFormat = "yyyy年M月"; f.locale = Locale(identifier: "zh_CN")
            return f.string(from: periodStart)
        }
    }

    func totals(state: AppState) -> (apps: [String: Delta], hosts: [String: Delta]) {
        let win = SelectionWindow(start: periodStart, end: min(periodEnd, Date()))
        let r = (state.store.appTotals(window: win), state.store.hostTotals(window: win))
        if ProcessInfo.processInfo.environment["NETGLASS_DEBUG"] != nil {
            print("[usage] win=\(win.start)→\(win.end) span=\(win.span) apps=\(r.0.count) hosts=\(r.1.count) rawCount=\(state.appRows.count)")
            fflush(stdout)
        }
        return r
    }
}

struct UsagePage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    @StateObject private var model = UsageModel()
    @State private var segment = 0   // 0 apps, 1 hosts
    private var P: Palette { Palette.for(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                VStack(spacing: 14) {
                    summaryCards
                    tableCard
                }
                .padding(16)
            }
        }
        .background(P.bg)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $model.scope) {
                ForEach(UsageModel.Scope.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .onChange(of: model.scope) { _ in model.offset = 0 }

            HStack(spacing: 4) {
                Button { model.offset -= 1 } label: { Image(systemName: "chevron.left") }
                Button { model.offset = min(model.offset + 1, 0) } label: { Image(systemName: "chevron.right") }
                    .disabled(model.offset >= 0)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(P.sub)

            Text(model.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(P.text)

            Spacer()

            Button {
                exportCSV()
            } label: {
                Label("导出 CSV", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(P.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var totals: (apps: [String: Delta], hosts: [String: Delta]) {
        model.totals(state: state)
    }

    private var summaryCards: some View {
        let t = totals
        let down = t.apps.values.reduce(UInt64(0)) { $0 + $1.down }
        let up = t.apps.values.reduce(UInt64(0)) { $0 + $1.up }
        return HStack(spacing: 14) {
            summaryCard("下载流量", Fmt.bytes(down), P.down, "arrow.down.circle.fill")
            summaryCard("上传流量", Fmt.bytes(up), P.up, "arrow.up.circle.fill")
            summaryCard("总流量", Fmt.bytes(down &+ up), P.accent, "arrow.left.arrow.right.circle.fill")
        }
    }

    private func summaryCard(_ title: String, _ value: String, _ color: Color, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11)).foregroundColor(P.sub)
                Text(value).font(.system(size: 17, weight: .semibold, design: .monospaced)).foregroundColor(P.text)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.border))
    }

    private var tableCard: some View {
        let t = totals
        let grand = max(t.apps.values.reduce(UInt64(0)) { $0 + $1.total }, 1)
        return VStack(spacing: 0) {
            Picker("", selection: $segment) {
                Text("按应用").tag(0)
                Text("按主机").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .padding(10)

            if segment == 0 {
                headerRow(left: "应用", extra: nil)
                let rows = t.apps.sorted { $0.value.total > $1.value.total }
                if rows.isEmpty { emptyHint } else {
                    ForEach(Array(rows.prefix(50).enumerated()), id: \.1.key) { _, item in
                        usageRow(title: state.identity.meta(for: item.key).name,
                                 icon: state.identity.meta(for: item.key).icon,
                                 d: item.value, grand: Double(grand))
                    }
                }
            } else {
                headerRow(left: "主机", extra: nil)
                let rows = t.hosts.sorted { $0.value.total > $1.value.total }
                if rows.isEmpty { emptyHint } else {
                    ForEach(Array(rows.prefix(50).enumerated()), id: \.1.key) { _, item in
                        let name = state.hostNames[item.key] ?? item.key
                        usageRow(title: name, icon: nil, d: item.value, grand: Double(grand))
                    }
                }
            }
            Spacer(minLength: 6)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.border))
    }

    private var emptyHint: some View {
        Text("该时段暂无流量记录")
            .font(.system(size: 12))
            .foregroundColor(P.sub)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
    }

    private func headerRow(left: String, extra: String?) -> some View {
        HStack(spacing: 10) {
            Text(left).frame(maxWidth: .infinity, alignment: .leading)
            Text("下载").frame(width: 90, alignment: .trailing)
            Text("上传").frame(width: 90, alignment: .trailing)
            Text("占比").frame(width: 130, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(P.sub)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(P.bg.opacity(0.6))
    }

    private func usageRow(title: String, icon: NSImage?, d: Delta, grand: Double) -> some View {
        let share = Double(d.total) / max(grand, 1)
        return HStack(spacing: 10) {
            Group {
                if let img = icon { Image(nsImage: img).resizable() }
                else {
                    Circle().fill(P.accent.opacity(0.2))
                        .overlay(Text(String(title.prefix(1)).uppercased())
                            .font(.system(size: 9, weight: .semibold)).foregroundColor(P.accent))
                }
            }
            .frame(width: 20, height: 20)
            .cornerRadius(4)
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(P.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.bytes(d.down))
                .font(.system(size: 11, design: .monospaced)).foregroundColor(P.sub)
                .frame(width: 90, alignment: .trailing)
            Text(Fmt.bytes(d.up))
                .font(.system(size: 11, design: .monospaced)).foregroundColor(P.sub)
                .frame(width: 90, alignment: .trailing)
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(P.border.opacity(0.5))
                        Capsule().fill(P.accent).frame(width: max(2, geo.size.width * share))
                    }
                }
                .frame(width: 70, height: 5)
                Text(Fmt.pct(share))
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(P.sub)
                    .frame(width: 42, alignment: .leading)
            }
            .frame(width: 130, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "NetGlass-用量-\(model.label).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let t = totals
        var lines = ["类型,名称,下载,上传,总计"]
        for (key, d) in t.apps.sorted(by: { $0.value.total > $1.value.total }) {
            lines.append("应用,\(csvEscape(state.identity.meta(for: key).name)),\(d.down),\(d.up),\(d.total)")
        }
        for (ip, d) in t.hosts.sorted(by: { $0.value.total > $1.value.total }) {
            lines.append("主机,\(csvEscape(state.hostNames[ip] ?? ip)),\(d.down),\(d.up),\(d.total)")
        }
        try? lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
    }

    private func csvEscape(_ s: String) -> String {
        s.contains(",") ? "\"\(s)\"" : s
    }
}

// MARK: - Alerts page

struct AlertsPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    @State private var filter: AlertType?
    private var P: Palette { Palette.for(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                filterChip(nil, label: "全部")
                ForEach(AlertType.allCases, id: \.self) { t in
                    filterChip(t, label: t.rawValue)
                }
                Spacer()
                Button {
                    state.alertCenter.clear()
                } label: {
                    Label("清空", systemImage: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(P.sub)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if state.alertCenter.alerts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 34))
                        .foregroundColor(P.sub.opacity(0.5))
                    Text("暂无警报")
                        .font(.system(size: 13))
                        .foregroundColor(P.sub)
                    Text("新设备接入、应用首次联网、流量异常等事件会出现在这里")
                        .font(.system(size: 11))
                        .foregroundColor(P.sub.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(alerts) { alert in
                            row(alert)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(P.bg)
        .onAppear { state.alertCenter.markAllRead() }
    }

    private var alerts: [AppAlert] {
        guard let f = filter else { return state.alertCenter.alerts }
        return state.alertCenter.alerts.filter { $0.type == f }
    }

    private func filterChip(_ type: AlertType?, label: String) -> some View {
        let selected = filter == type
        return Button {
            filter = type
        } label: {
            Text(label)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? P.accent : P.sub)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? P.accent.opacity(0.14) : P.card))
                .overlay(Capsule().strokeBorder(P.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func row(_ alert: AppAlert) -> some View {
        HStack(spacing: 12) {
            Image(systemName: alert.type.icon)
                .font(.system(size: 16))
                .foregroundColor(color(for: alert.type))
                .frame(width: 34, height: 34)
                .background(Circle().fill(color(for: alert.type).opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(alert.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(P.text)
                    Text(alert.type.rawValue)
                        .font(.system(size: 9))
                        .foregroundColor(P.sub)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(P.border.opacity(0.5)))
                }
                Text(alert.detail)
                    .font(.system(size: 11))
                    .foregroundColor(P.sub)
                    .lineLimit(2)
            }
            Spacer()
            Text(Fmt.ago(alert.date))
                .font(.system(size: 10))
                .foregroundColor(P.sub)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.border))
    }

    private func color(for type: AlertType) -> Color {
        type.tint
    }
}
