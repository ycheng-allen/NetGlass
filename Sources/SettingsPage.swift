import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    @Environment(\.dismiss) private var dismiss
    private var P: Palette { Palette.for(scheme) }
    @State private var confirmReset = false

    private var settings: Binding<AppSettings> {
        Binding(get: { state.settings }, set: { state.settings = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(P.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(P.sub)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("通用") {
                        row("外观") {
                            Picker("", selection: settings.appearance) {
                                ForEach(AppearanceMode.allCases, id: \.self) { m in
                                    Text(m.rawValue).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                        row("开机自启") {
                            Toggle("", isOn: settings.launchAtLogin).labelsHidden()
                        }
                        row("菜单栏图标") {
                            Toggle("", isOn: settings.showMenuBarIcon).labelsHidden()
                        }
                        row("采样间隔") {
                            Picker("", selection: settings.sampleInterval) {
                                Text("1 秒").tag(1.0)
                                Text("2 秒").tag(2.0)
                                Text("5 秒").tag(5.0)
                                Text("10 秒").tag(10.0)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                        row("历史保留") {
                            Picker("", selection: settings.retentionDays) {
                                Text("7 天").tag(7)
                                Text("30 天").tag(30)
                                Text("90 天").tag(90)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                    }

                    section("警报") {
                        row("新应用开始联网") {
                            Toggle("", isOn: settings.alertNewApp).labelsHidden()
                        }
                        row("应用访问新主机") {
                            Toggle("", isOn: settings.alertNewHost).labelsHidden()
                        }
                        row("自动将新应用加入防火墙") {
                            Toggle("", isOn: settings.autoBlockNewApp).labelsHidden()
                        }
                        row("发现新设备") {
                            Toggle("", isOn: settings.alertNewDevice).labelsHidden()
                        }
                        row("流量异常升高") {
                            Toggle("", isOn: settings.alertSpike).labelsHidden()
                        }
                        row("异常判定阈值") {
                            HStack(spacing: 8) {
                                Slider(value: settings.spikeSigma, in: 2...6, step: 0.5)
                                    .frame(width: 140)
                                Text("\(state.settings.spikeSigma, specifier: "%.1f")σ")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(P.sub)
                            }
                        }
                        row("DNS 服务器变更") {
                            Toggle("", isOn: settings.alertDNSChange).labelsHidden()
                        }
                        row("ARP 欺骗检测") {
                            Toggle("", isOn: settings.alertARPSpoof).labelsHidden()
                        }
                    }

                    section("数据") {
                        row("清空全部历史") {
                            Button {
                                confirmReset = true
                            } label: {
                                Text("重置数据")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(P.danger)
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog("确定清空所有流量历史、设备记录与警报吗？",
                                                isPresented: $confirmReset, titleVisibility: .visible) {
                                Button("清空", role: .destructive) { state.resetAllData() }
                            }
                        }
                    }

                    section("关于") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                LogoView(size: 22)
                                Text("NetGlass v1.0")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(P.text)
                            }
                            Text("受 GlassWire 启发的 macOS 网络监控器。\n· 流量归因通过 nettop（每进程字节统计）+ lsof（连接归属）实现，无需额外权限。\n· 防火墙功能调用 macOS 内置应用防火墙，修改时需要管理员密码。\n· 严格的应用级出入站拦截需要 Network Extension 系统扩展（需开发者账号签名），本版本暂未包含。")
                                .font(.system(size: 10))
                                .foregroundColor(P.sub)
                                .lineSpacing(3)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 560, height: 620)
        .background(P.bg)
    }

    private func section<S: View>(_ title: String, @ViewBuilder content: () -> S) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(P.accent)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(P.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.border))
        }
    }

    @ViewBuilder
    private func row<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(P.text)
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
