import SwiftUI

/// Compact panel shown when clicking the menu-bar status item.
struct MenuBarPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    private var P: Palette { Palette.for(scheme) }

    private var series: [Bucket] {
        let end = Date()
        return state.store.buckets(
            window: SelectionWindow(start: end.addingTimeInterval(-1800), end: end),
            slots: 48)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                LogoView(size: 16)
                Text("NetGlass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(P.text)
                Spacer()
                HStack(spacing: 8) {
                    Label(Fmt.speed(state.liveDown), systemImage: "arrow.down")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(P.down)
                    Label(Fmt.speed(state.liveUp), systemImage: "arrow.up")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(P.up)
                }
            }

            MiniSparkline(buckets: series, palette: P)
                .frame(height: 52)

            Text("Top 应用")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(P.accent)

            if state.appRows.isEmpty {
                Text(state.paused ? "监控已暂停" : "正在采样…")
                    .font(.system(size: 11))
                    .foregroundColor(P.sub)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                ForEach(state.appRows.prefix(3)) { row in
                    HStack(spacing: 8) {
                        Group {
                            if let img = row.icon { Image(nsImage: img).resizable() }
                            else { Image(systemName: "app.fill").resizable() }
                        }
                        .frame(width: 18, height: 18)
                        .cornerRadius(4)
                        Text(row.name)
                            .font(.system(size: 11))
                            .foregroundColor(P.text)
                            .lineLimit(1)
                        Spacer()
                        Text(row.rate > 0.5 ? Fmt.speed(row.rate) : "—")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(row.rate > 0.5 ? P.down : P.sub.opacity(0.5))
                    }
                }
            }

            Divider().opacity(0.4)

            HStack(spacing: 8) {
                Button {
                    state.togglePause()
                } label: {
                    Label(state.paused ? "继续" : "暂停",
                          systemImage: state.paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(P.card))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.border))
                }
                .buttonStyle(.plain)

                Button {
                    closePopover()
                    openMainWindow()
                } label: {
                    Label("打开主窗口", systemImage: "macwindow.on.rectangle")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(P.accent.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.accent.opacity(0.4)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(P.panel)
    }

    private func closePopover() {
        NSApp.keyWindow?.performClose(nil)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.canBecomeMain }) {
            win.makeKeyAndOrderFront(nil)
        }
    }
}
