import SwiftUI

// MARK: - Palette

struct Palette {
    let bg: Color
    let panel: Color
    let card: Color
    let border: Color
    let text: Color
    let sub: Color
    let accent: Color
    let down: Color
    let up: Color
    let chartBg: Color
    let rowHighlight: Color
    let danger: Color

    static func `for`(_ scheme: ColorScheme) -> Palette {
        if scheme == .light {
            return Palette(
                bg: Color(hex: 0xF2F5F7), panel: Color(hex: 0xFFFFFF), card: Color(hex: 0xFFFFFF),
                border: Color(hex: 0xDCE3EA), text: Color(hex: 0x1C2A36), sub: Color(hex: 0x6B7E90),
                accent: Color(hex: 0x0AA6A0), down: Color(hex: 0x14A88C), up: Color(hex: 0xF08C2E),
                chartBg: Color(hex: 0xEAF6FB), rowHighlight: Color(hex: 0xE4F5EA), danger: Color(hex: 0xD64545))
        }
        return Palette(
            bg: Color(hex: 0x0D1218), panel: Color(hex: 0x131A22), card: Color(hex: 0x18212C),
            border: Color(hex: 0x22303F), text: Color(hex: 0xDCE6F0), sub: Color(hex: 0x7E93A8),
            accent: Color(hex: 0x2BD9C8), down: Color(hex: 0x23C3A5), up: Color(hex: 0xFF9E4A),
            chartBg: Color(hex: 0x10161D), rowHighlight: Color(hex: 0x18291E), danger: Color(hex: 0xE05A5A))
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

extension AlertType {
    /// Shared tint for alert chips, list rows and graph markers.
    var tint: Color {
        switch self {
        case .newApp: return Color(hex: 0x2BD9C8)
        case .newHost: return Color(hex: 0x6FA8FF)
        case .newDevice: return .blue
        case .spike: return .orange
        case .dns: return .purple
        case .arp: return .red
        case .firewall: return .yellow
        }
    }
}

// MARK: - Logo (GlassWire-style pinwheel)

struct LogoView: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [Color(hex: 0x35E0CF), Color(hex: 0x18A8D8),
                                            Color(hex: 0xF26FA0), Color(hex: 0xF5C542)],
                                   center: .init(x: 0.3, y: 0.25), startRadius: 0, endRadius: size)
                )
            Circle()
                .stroke(Color(hex: 0x5A6B7D), lineWidth: size * 0.07)
            Circle()
                .trim(from: 0.0, to: 0.28)
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-70))
                .padding(size * 0.18)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Top bar (GlassWire-style centered nav)

struct TopBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    private var P: Palette { Palette.for(scheme) }
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                LogoView(size: 24)
                Text("NetGlass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(P.text)
                Text("网络监控")
                    .font(.system(size: 11))
                    .foregroundColor(P.sub)
            }
            .padding(.leading, 16)

            Spacer()

            HStack(spacing: 4) {
                ForEach(Array(AppState.Page.allCases.enumerated()), id: \.1) { _, page in
                    navButton(page)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                if state.paused {
                    Text("已暂停")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(P.danger)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(P.danger.opacity(0.15)))
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15))
                        .foregroundColor(P.sub)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showSettings) { SettingsPage() }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 62)
        .background(P.panel)
    }

    private func navButton(_ page: AppState.Page) -> some View {
        let selected = state.page == page
        return Button {
            state.page = page
            if page == .alerts { state.alertCenter.markAllRead() }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: page.icon)
                        .font(.system(size: 17, weight: .medium))
                    if page == .alerts && state.alertCenter.unread > 0 {
                        Circle()
                            .fill(P.danger)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -2)
                    }
                }
                Text(page.title)
                    .font(.system(size: 11))
            }
            .foregroundColor(selected ? P.accent : P.sub)
            .frame(width: 78, height: 54)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? P.accent.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GlassWire-style flame toggle (shared: firewall page + app drill-down)

struct FlameToggle: View {
    var palette: Palette
    var blocked: Bool
    var managed: Bool
    var busy: Bool
    var action: () -> Void

    private var flame: Color { Color(hex: 0xFF9E4A) }

    private var tint: Color {
        blocked ? flame : (managed ? palette.down.opacity(0.85) : palette.sub.opacity(0.35))
    }

    public var body: some View {
        Button {
            guard managed, !busy else { return }
            action()
        } label: {
            Image(systemName: blocked ? "flame.fill" : "flame")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .shadow(color: blocked ? flame.opacity(0.9) : .clear, radius: blocked ? 5 : 0)
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(blocked ? flame.opacity(0.14) : palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(blocked ? flame.opacity(0.55) : palette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!managed || busy)
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider().opacity(0.4)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.for(scheme).bg)
        .preferredColorScheme(preferred)
        .onAppear { state.start() }
    }

    private var preferred: ColorScheme? {
        switch state.settings.appearance {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.page {
        case .graph: GraphPage()
        case .usage: UsagePage()
        case .things: ThingsPage()
        case .firewall: FirewallPage()
        case .alerts: AlertsPage()
        }
    }
}
