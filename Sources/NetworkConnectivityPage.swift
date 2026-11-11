import SwiftUI

struct NetworkConnectivityPage: View {
    @ObservedObject var model: NetworkConnectivity
    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette.for(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("测试当前网络到各站点的 HTTP 响应耗时").font(.system(size: 13, weight: .medium))
                    Text("每站预热后测量 8 轮，显示成功请求的中位数 · 最多 9 站并发")
                        .font(.system(size: 11)).foregroundStyle(palette.sub)
                }
                Spacer()
                if model.running {
                    ProgressView().controlSize(.small)
                    Button("停止") { model.stop() }
                }
                Button(model.samples.isEmpty ? "开始测试" : "重新测试") { model.start() }
                    .buttonStyle(.borderedProminent).disabled(model.running)
            }
            HStack(spacing: 16) {
                legend("优 <100 ms", palette.down)
                legend("良 <400 ms", palette.accent)
                legend("慢 ≥400 ms", palette.up)
                legend("超时／失败", palette.danger)
                Spacer()
                let completed = model.samples.values.filter { $0.count == NetworkConnectivity.rounds }.count
                Text("\(completed) / \(model.targets.count) 站完成").font(.system(size: 10)).foregroundStyle(palette.sub)
            }
            if model.running {
                let total = (model.activeGroup.map { group in model.targets.filter { $0.group == group }.count } ?? model.targets.count) * NetworkConnectivity.rounds
                let done = model.targets.filter { model.activeGroup == nil || $0.group == model.activeGroup }.reduce(0) { $0 + (model.samples[$1.id]?.count ?? 0) }
                ProgressView(value: Double(done), total: Double(max(1, total))).tint(palette.accent)
            }
            ForEach(ConnectivityCatalog.groups, id: \.0) { group in groupSection(group.0, title: group.1) }
            VStack(alignment: .leading, spacing: 8) {
                Text(model.catalogMessage).font(.system(size: 10)).foregroundStyle(palette.sub)
                if let date = model.checkedAt { Text("最近测试开始于 " + date.formatted()).font(.system(size: 10)).foregroundStyle(palette.sub) }
                DisclosureGroup("测试方式与结果含义") {
                    Text("由 NetGlass 直接请求各站的轻量端点或 CDN 图标，单次约 2.5 秒超时。取得 HTTP 响应即计入可达，403、404 等状态可在圆点提示中查看，不能据此确认业务可用。结果包含 DNS、TLS、连接及响应传输耗时。其他浏览器可能使用不同代理；超时也可能是探测受限。每次全部测试重新检查参考站列表，失败时保留当前列表。")
                        .font(.system(size: 11)).foregroundStyle(palette.sub).padding(.top, 8)
                }.font(.system(size: 11))
                Link("站点列表参考 Net.Coffee", destination: URL(string: "https://ip.net.coffee/link/")!).font(.system(size: 10))
            }
        }.tint(palette.accent)
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 6, height: 6); Text(title).font(.system(size: 10)).foregroundStyle(palette.sub) }
    }

    private func groupSection(_ group: String, title: String) -> some View {
        let targets = model.targets.filter { $0.group == group }
        let values = targets.compactMap { NetworkConnectivity.median(model.samples[$0.id] ?? []) }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(group == "gl" ? "🌐" : (group == "cn" ? "🇨🇳" : (group == "jp" ? "🇯🇵" : "🇺🇸")))
                Text(title).font(.system(size: 15, weight: .semibold))
                Text("响应 \(values.count) / \(targets.count)").font(.system(size: 11)).foregroundStyle(palette.sub)
                if !values.isEmpty { Text(String(format: "平均 %.0f ms", values.reduce(0, +) / Double(values.count))).font(.system(size: 11)).foregroundStyle(palette.sub) }
                Spacer()
                Button { model.start(group: group) } label: { Label("重测此组", systemImage: "arrow.clockwise") }
                    .controlSize(.small).disabled(model.running || targets.isEmpty)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 12)], spacing: 12) {
                ForEach(targets) { target in targetTile(target) }
            }
        }.padding(20).background(palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border))
    }

    private func color(_ sample: ConnectivitySample) -> Color {
        guard let time = sample.milliseconds else { return palette.danger }
        return time < 100 ? palette.down : (time < 400 ? palette.accent : palette.up)
    }

    private func targetTile(_ target: ConnectivityTarget) -> some View {
        let samples = model.samples[target.id] ?? []
        let median = NetworkConnectivity.median(samples)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(target.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(median.map { String(format: "%.0f ms", $0) } ?? (samples.isEmpty ? "待测" : "失败"))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(median.map { $0 < 100 ? palette.down : ($0 < 400 ? palette.accent : palette.up) } ?? (samples.isEmpty ? palette.sub : palette.danger))
            }
            Text(target.host).font(.system(size: 9)).foregroundStyle(palette.sub).lineLimit(1).help(target.endpoint)
            HStack(spacing: 5) {
                ForEach(0..<NetworkConnectivity.rounds, id: \.self) { index in
                    Circle().fill(index < samples.count ? color(samples[index]) : palette.border)
                        .frame(width: 7, height: 7)
                        .help(index < samples.count ? sampleDescription(samples[index], index: index) : "第 \(index + 1) 轮待测")
                }
                Spacer()
                Text("\(samples.filter { $0.milliseconds != nil }.count)/\(NetworkConnectivity.rounds) 响应")
                    .font(.system(size: 9)).foregroundStyle(palette.sub)
            }
        }.padding(14).background(palette.bg, in: RoundedRectangle(cornerRadius: 8))
    }

    private func sampleDescription(_ sample: ConnectivitySample, index: Int) -> String {
        if let time = sample.milliseconds { return String(format: "第 %d 轮 · %.0f ms · HTTP %d", index + 1, time, sample.statusCode ?? 0) }
        return "第 \(index + 1) 轮 · " + (sample.error ?? "失败")
    }
}
