import SwiftUI

// MARK: - Graph page (the GlassWire signature screen)

struct GraphPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    private var P: Palette { Palette.for(scheme) }

    /// Alerts inside the selected window, shown as pennants on the chart.
    private var graphMarkers: [GraphMarker] {
        let win = state.selection
        return state.alertCenter.alerts
            .filter { $0.date >= win.start && $0.date <= win.end }
            .prefix(40)
            .map { GraphMarker(t: $0.date, type: $0.type, title: $0.title, detail: $0.detail) }
            .reversed()
    }
    var body: some View {
        HStack(spacing: 0) {
            AppListPanel()
                .frame(width: 316)
            Divider().opacity(0.4)
            VStack(spacing: 0) {
                RangeBar()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                GraphView(buckets: state.graphBuckets, palette: P,
                          window: state.selection, markers: graphMarkers)
                InfoStrip()
                TimelineNavigator()
            }
        }
    }
}

// MARK: - Left app list

struct AppListPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    @State private var expandedApp: String?
    private var P: Palette { Palette.for(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("应用")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(P.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("↓")
                    .frame(width: 78, alignment: .trailing)
                Text("↑")
                    .frame(width: 78, alignment: .trailing)
            }
            .font(.system(size: 11))
            .foregroundColor(P.sub)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 1) {
                    allAppsRow
                    ForEach(state.appRows.prefix(60)) { row in
                        VStack(spacing: 0) {
                            appRow(row)
                                .background(expandedApp == row.key ? P.accent.opacity(0.10) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    expandedApp = expandedApp == row.key ? nil : row.key
                                }
                            if expandedApp == row.key {
                                AppDetailPanel(key: row.key)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                    if !state.hostRows.isEmpty {
                        HStack {
                            Text("活跃主机")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(P.sub)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                        ForEach(state.hostRows.prefix(10)) { h in
                            hostRow(h)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(P.panel)
    }

    private var allAppsRow: some View {
        let liveRate = state.liveDown + state.liveUp
        return HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 13))
                .foregroundColor(P.down)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("全部应用")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(P.text)
                Text(liveRate > 0.5 ? Fmt.speed(liveRate) : "空闲")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(liveRate > 0.5 ? P.down : P.sub.opacity(0.45))
            }
            Spacer()
            numberColumn(Fmt.bytes(state.windowTotal.down))
            numberColumn(Fmt.bytes(state.windowTotal.up))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(P.rowHighlight)
    }

    private func appRow(_ row: AppRow) -> some View {
        let active = row.rate > 0.5
        return HStack(spacing: 8) {
            Group {
                if let img = row.icon {
                    Image(nsImage: img).resizable()
                } else {
                    Image(systemName: "app.fill").resizable()
                }
            }
            .frame(width: 20, height: 20)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: 12))
                    .foregroundColor(row.isSystem ? P.sub.opacity(0.7) : P.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 3) {
                    if active {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(P.down)
                    }
                    Text(active ? Fmt.speed(row.rate) : "空闲")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(active ? P.down : P.sub.opacity(0.45))
                }
            }
            Spacer()
            numberColumn(Fmt.bytes(row.down))
            numberColumn(Fmt.bytes(row.up))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func hostRow(_ h: HostRow) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(P.accent.opacity(0.18))
                .frame(width: 20, height: 20)
                .overlay(
                    Text(String(h.name.prefix(1)).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(P.accent)
                )
            Text(h.name)
                .font(.system(size: 12))
                .foregroundColor(P.text)
                .lineLimit(1)
            Spacer()
            numberColumn(Fmt.bytes(h.down))
            numberColumn(Fmt.bytes(h.up))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func numberColumn(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(P.sub)
            .frame(width: 78, alignment: .trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Range chips

struct RangeBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    private var P: Palette { Palette.for(scheme) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SelectionWindow.presets, id: \.0) { preset in
                let selected = abs(state.selection.span - preset.1) < preset.1 * 0.08 && state.followNow
                Button {
                    state.setPreset(preset.1)
                } label: {
                    Text(preset.0)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundColor(selected ? P.accent : P.sub)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(selected ? P.accent.opacity(0.14) : P.card)
                        )
                        .overlay(Capsule().strokeBorder(P.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                state.paused.toggle()
            } label: {
                Image(systemName: state.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11))
                    .foregroundColor(P.sub)
                    .frame(width: 26, height: 22)
                    .background(Capsule().fill(P.card))
                    .overlay(Capsule().strokeBorder(P.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(state.paused ? "继续监控" : "暂停监控")
        }
    }
}

// MARK: - Main chart

struct GraphView: View {
    var buckets: [Bucket]
    var palette: Palette
    var window: SelectionWindow
    var markers: [GraphMarker] = []
    @EnvironmentObject var state: AppState
    @State private var hoverX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    Self.draw(ctx: ctx, size: size, buckets: buckets, P: palette,
                              hoverX: hoverX.map { $0 / max(size.width, 1) },
                              window: window, markers: markers)
                }
                if let fx = hoverX {
                    let fraction = fx / max(size.width, 1)
                    if let m = nearestMarker(fraction: fraction, width: size.width) {
                        markerTooltip(m, width: size.width)
                    } else {
                        trafficTooltip(fraction: fraction)
                            .offset(x: min(max(fx - 70, 6), max(size.width - 176, 6)), y: 10)
                            .allowsHitTesting(false)
                    }
                }
            }
            .background(palette.chartBg)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hoverX = p.x
                case .ended: hoverX = nil
                @unknown default: break
                }
            }
        }
    }

    // MARK: markers

    private func markerFraction(_ m: GraphMarker) -> CGFloat {
        let span = max(window.span, 1)
        return CGFloat(clamp(m.t.timeIntervalSince(window.start) / span, 0, 1))
    }

    private func nearestMarker(fraction: CGFloat, width: CGFloat) -> GraphMarker? {
        guard !markers.isEmpty else { return nil }
        let threshold = 10.0 / max(width, 1)
        var best: GraphMarker?
        var bestDist = threshold
        for m in markers {
            let d = abs(markerFraction(m) - fraction)
            if d < bestDist { bestDist = d; best = m }
        }
        return best
    }

    private func markerTooltip(_ m: GraphMarker, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(m.type.tint).frame(width: 6, height: 6)
                Text(m.type.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(m.type.tint)
                Text(Fmt.timeFull(m.t))
                    .font(.system(size: 9))
                    .foregroundColor(palette.sub)
            }
            Text(m.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.text)
            Text(m.detail)
                .font(.system(size: 10))
                .foregroundColor(palette.sub)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border))
        .shadow(radius: 4)
        .offset(x: min(max(markerFraction(m) * width - 80, 6), max(width - 250, 6)), y: 10)
        .allowsHitTesting(false)
    }

    private func trafficTooltip(fraction: CGFloat) -> some View {
        Group {
            if let b = bucketAt(fraction) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Fmt.timeFull(b.t))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(palette.sub)
                    HStack(spacing: 5) {
                        Circle().fill(palette.down).frame(width: 6, height: 6)
                        Text("↓ \(Fmt.speed(b.down))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(palette.text)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(palette.up).frame(width: 6, height: 6)
                        Text("↑ \(Fmt.speed(b.up))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(palette.text)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.card))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border))
                .shadow(radius: 4)
            }
        }
    }

    private func bucketAt(_ fraction: CGFloat) -> Bucket? {
        guard !buckets.isEmpty else { return nil }
        let idx = Int(CGFloat(buckets.count - 1) * fraction)
        return buckets[clamp(idx, 0, buckets.count - 1)]
    }

    static func niceCeil(_ v: Double) -> Double {
        guard v > 0, v.isFinite else { return 10240 }
        let exp = floor(log10(v))
        let base = pow(10, exp)
        let frac = v / base
        let nice: Double
        if frac <= 1 { nice = 1 } else if frac <= 2 { nice = 2 }
        else if frac <= 5 { nice = 5 } else { nice = 10 }
        return nice * base
    }

    static func draw(ctx: GraphicsContext, size: CGSize, buckets: [Bucket], P: Palette,
                     hoverX: CGFloat?, window: SelectionWindow, markers: [GraphMarker]) {
        let w = size.width, h = size.height
        guard w > 10, h > 10 else { return }

        guard !buckets.isEmpty else {
            let text = Text("正在采样…").font(.system(size: 12)).foregroundColor(P.sub)
            ctx.draw(text, at: CGPoint(x: w / 2, y: h / 2))
            return
        }

        var maxV = 0.0
        for b in buckets {
            maxV = max(maxV, b.down, b.up)
        }
        let niceMax = niceCeil(maxV * 1.15)

        // grid
        for i in 1...3 {
            let y = h * CGFloat(i) / 4.0
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: w, y: y))
            ctx.stroke(line, with: .color(P.border.opacity(0.5)), lineWidth: 1)
            let label = Text(Fmt.speed(niceMax * Double(4 - i) / 4.0))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(P.sub.opacity(0.9))
            ctx.draw(label, at: CGPoint(x: w - 42, y: y - 6), anchor: .leading)
        }

        let n = buckets.count

        func seriesPath(_ values: [Double]) -> (area: Path, line: Path) {
            var area = Path()
            var line = Path()
            guard n > 1 else { return (area, line) }
            for (i, v) in values.enumerated() {
                let x = w * CGFloat(i) / CGFloat(n - 1)
                let y = h - CGFloat(min(v / niceMax, 1)) * h
                let pt = CGPoint(x: x, y: y)
                if i == 0 {
                    line.move(to: pt)
                    area.move(to: CGPoint(x: x, y: h))
                    area.addLine(to: pt)
                } else {
                    line.addLine(to: pt)
                    area.addLine(to: pt)
                }
            }
            area.addLine(to: CGPoint(x: w, y: h))
            area.closeSubpath()
            return (area, line)
        }

        // upload (behind)
        let up = seriesPath(buckets.map { $0.up })
        ctx.fill(up.area, with: .linearGradient(
            Gradient(colors: [P.up.opacity(0.30), P.up.opacity(0.03)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
        ctx.stroke(up.line, with: .color(P.up.opacity(0.9)), lineWidth: 1.2)

        // download (front)
        let down = seriesPath(buckets.map { $0.down })
        ctx.fill(down.area, with: .linearGradient(
            Gradient(colors: [P.down.opacity(0.38), P.down.opacity(0.04)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
        ctx.stroke(down.line, with: .color(P.down), lineWidth: 1.6)

        // alert markers (pennants along the top edge)
        let span = max(window.span, 1)
        for m in markers {
            let f = clamp(m.t.timeIntervalSince(window.start) / span, 0, 1)
            let x = w * CGFloat(f)
            var pennant = Path()
            pennant.move(to: CGPoint(x: x - 4.5, y: 3))
            pennant.addLine(to: CGPoint(x: x + 4.5, y: 3))
            pennant.addLine(to: CGPoint(x: x, y: 12))
            pennant.closeSubpath()
            ctx.fill(pennant, with: .color(m.type.tint))
            var stem = Path()
            stem.move(to: CGPoint(x: x, y: 3))
            stem.addLine(to: CGPoint(x: x, y: h))
            ctx.stroke(stem, with: .color(m.type.tint.opacity(0.18)), lineWidth: 1)
        }

        // hover crosshair
        if let fx = hoverX {
            let x = w * CGFloat(fx)
            if x >= 0, x <= w {
                var v = Path()
                v.move(to: CGPoint(x: x, y: 0))
                v.addLine(to: CGPoint(x: x, y: h))
                ctx.stroke(v, with: .color(P.text.opacity(0.25)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                let idx = clamp(Int(CGFloat(n - 1) * CGFloat(fx)), 0, n - 1)
                for (val, color) in [(buckets[idx].down, P.down), (buckets[idx].up, P.up)] {
                    let y = h - CGFloat(min(val / niceMax, 1)) * h
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7)),
                             with: .color(color))
                }
            }
        }
    }
}

// MARK: - Info strip (bottom of chart, like GlassWire's active app/host row)

struct InfoStrip: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    private var P: Palette { Palette.for(scheme) }

    var body: some View {
        HStack(spacing: 16) {
            if let top = state.appRows.first {
                HStack(spacing: 6) {
                    Group {
                        if let img = top.icon { Image(nsImage: img).resizable() }
                        else { Image(systemName: "app.fill").resizable() }
                    }
                    .frame(width: 15, height: 15)
                    Text(top.name)
                        .font(.system(size: 11))
                        .foregroundColor(P.text)
                        .lineLimit(1)
                    Text(Fmt.speed(top.rate))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(P.down)
                }
            }
            if let host = state.hostRows.first {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                        .foregroundColor(P.accent)
                    Text(host.name)
                        .font(.system(size: 11))
                        .foregroundColor(P.text)
                        .lineLimit(1)
                    Text(Fmt.bytes(host.down + host.up))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(P.sub)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                Label(Fmt.speed(state.liveDown), systemImage: "arrow.down")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(P.down)
                Label(Fmt.speed(state.liveUp), systemImage: "arrow.up")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(P.up)
                Text("至 \(Fmt.timeFull(state.selection.end))")
                    .font(.system(size: 11))
                    .foregroundColor(P.sub)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(P.chartBg)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Timeline navigator (draggable selection over full history)

struct TimelineNavigator: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    private var P: Palette { Palette.for(scheme) }

    private enum DragMode { case left, right, move }
    @State private var dragMode: DragMode?
    @State private var moveAnchor: Date = Date()
    @State private var moveSel: SelectionWindow?

    private var rangeStart: Date { state.historyStart }
    private var rangeEnd: Date { max(Date(), state.selection.end) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    draw(ctx: ctx, w: w, h: h)
                }
                selectionLayer(w: w, h: h)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in handleDrag(x: v.location.x, w: w) }
                    .onEnded { _ in dragMode = nil; moveSel = nil }
            )
        }
        .frame(height: 84)
        .background(P.panel)
    }

    private func frac(_ d: Date) -> Double {
        let total = rangeEnd.timeIntervalSince(rangeStart)
        guard total > 1 else { return 0 }
        return clamp(d.timeIntervalSince(rangeStart) / total, 0, 1)
    }

    private func date(atFrac f: Double) -> Date {
        rangeStart.addingTimeInterval(f * rangeEnd.timeIntervalSince(rangeStart))
    }

    private func selectionLayer(w: CGFloat, h: CGFloat) -> some View {
        let x0 = CGFloat(frac(state.selection.start)) * w
        let x1 = CGFloat(frac(state.selection.end)) * w
        let rectH = h - 22
        return ZStack {
            Path { p in
                p.addRect(CGRect(x: x0, y: 5, width: max(x1 - x0, 2), height: rectH))
            }
            .fill(P.accent.opacity(0.13))
            Path { p in
                p.addRect(CGRect(x: x0, y: 5, width: max(x1 - x0, 2), height: rectH))
            }
            .stroke(P.accent.opacity(0.55), lineWidth: 1)
            ForEach([x0, x1], id: \.self) { x in
                Circle()
                    .fill(P.accent)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().fill(P.panel).frame(width: 5, height: 5))
                    .position(x: x, y: 5 + rectH / 2)
            }
        }
        .allowsHitTesting(false)
    }

    private func handleDrag(x: CGFloat, w: CGFloat) {
        guard w > 20 else { return }
        let total = rangeEnd.timeIntervalSince(rangeStart)
        guard total > 60 else { return }
        let d = date(atFrac: Double(clamp(x / w, 0, 1)))

        if dragMode == nil {
            let fs = CGFloat(frac(state.selection.start)) * w
            let fe = CGFloat(frac(state.selection.end)) * w
            if abs(x - fs) < 14 { dragMode = .left }
            else if abs(x - fe) < 14 { dragMode = .right }
            else {
                dragMode = .move
                moveAnchor = d
                moveSel = state.selection
            }
        }

        let minSpan: TimeInterval = 30
        switch dragMode {
        case .left:
            let s = min(d, state.selection.end.addingTimeInterval(-minSpan))
            state.setSelection(start: s, end: state.selection.end)
        case .right:
            let e = max(d, state.selection.start.addingTimeInterval(minSpan))
            state.setSelection(start: state.selection.start, end: e)
        case .move:
            guard let sel = moveSel else { return }
            let shift = d.timeIntervalSince(moveAnchor)
            var s = sel.start.addingTimeInterval(shift)
            var e = sel.end.addingTimeInterval(shift)
            if e > rangeEnd { e = rangeEnd; s = e.addingTimeInterval(-sel.span) }
            if s < rangeStart { s = rangeStart; e = s.addingTimeInterval(sel.span) }
            state.setSelection(start: s, end: e)
        case nil:
            break
        }
    }

    private func draw(ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        let buckets = state.overview
        let drawH = h - 24
        guard w > 10, drawH > 10 else { return }
        guard !buckets.isEmpty else {
            let text = Text("暂无历史数据").font(.system(size: 10)).foregroundColor(P.sub)
            ctx.draw(text, at: CGPoint(x: w / 2, y: drawH / 2 + 5))
            return
        }
        var maxV = 0.0
        for b in buckets { maxV = max(maxV, b.down, b.up) }
        let niceMax = GraphView.niceCeil(maxV * 1.1)

        func area(_ key: KeyPath<Bucket, Double>, color: Color, opacity: Double) {
            var p = Path()
            let n = buckets.count
            for (i, b) in buckets.enumerated() {
                let x = w * CGFloat(i) / CGFloat(max(n - 1, 1))
                let y = drawH - CGFloat(min(b[keyPath: key] / niceMax, 1)) * drawH + 5
                if i == 0 {
                    p.move(to: CGPoint(x: x, y: drawH + 5))
                    p.addLine(to: CGPoint(x: x, y: y))
                } else {
                    p.addLine(to: CGPoint(x: x, y: y))
                }
            }
            p.addLine(to: CGPoint(x: w, y: drawH + 5))
            p.closeSubpath()
            ctx.fill(p, with: .color(color.opacity(opacity)))
        }

        area(\.up, color: P.up, opacity: 0.35)
        area(\.down, color: P.down, opacity: 0.45)

        // time labels — switch to clock time when the range is within a day
        let intraday = rangeEnd.timeIntervalSince(rangeStart) < 86400
        func lbl(_ f: Double) -> String {
            let d = date(atFrac: f)
            if f >= 1.0 { return Fmt.timeFull(rangeEnd) }
            return intraday ? Fmt.timeShort(d) : Fmt.dayLabel(d)
        }
        let fmt: [(Double, String)] = [
            (0.0, lbl(0.0)), (0.33, lbl(0.33)), (0.66, lbl(0.66)), (1.0, lbl(1.0)),
        ]
        for (f, label) in fmt {
            let text = Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(P.sub)
            ctx.draw(text, at: CGPoint(x: CGFloat(f) * max(w - 60, 0) + 2, y: h - 8), anchor: .leading)
        }
    }
}

// MARK: - Per-app drill-down detail (shown under the tapped app row)

struct AppDetailPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    let key: String
    private var P: Palette { Palette.for(scheme) }
    private var meta: AppMeta { state.identity.meta(for: key) }

    private var liveRate: Double {
        state.appRows.first { $0.key == key }?.rate ?? 0
    }

    private var hostTotals: [(ip: String, name: String, delta: Delta)] {
        let totals = state.appHostTotals[key] ?? [:]
        return totals
            .map { (ip: $0.key, name: state.hostNames[$0.key] ?? $0.key, delta: $0.value) }
            .sorted { $0.delta.total > $1.delta.total }
    }

    private var series: [Bucket] {
        let end = Date()
        return state.store.buckets(
            window: SelectionWindow(start: end.addingTimeInterval(-1800), end: end),
            slots: 60,
            keyFilter: { $0 == key })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(liveRate > 0.5 ? P.down : P.sub.opacity(0.4))
                Text(liveRate > 0.5 ? Fmt.speed(liveRate) : "空闲")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(liveRate > 0.5 ? P.down : P.sub.opacity(0.5))
                Spacer()
                if let path = meta.bundlePath {
                    FlameToggle(palette: P,
                                blocked: state.firewall.firewallApps[path] == .block,
                                managed: true,
                                busy: state.firewall.busy,
                                action: {
                                    let blocked = state.firewall.firewallApps[path] == .block
                                    state.firewall.setApp(path: path, to: blocked ? .allow : .block)
                                })
                        .help(state.firewall.firewallApps[path] == .block
                              ? "已阻止 — 点击放行"
                              : "点击阻止该应用联网（需管理员密码）")
                }
            }

            MiniSparkline(buckets: series, palette: P)
                .frame(height: 30)

            let hosts = hostTotals
            if !hosts.isEmpty {
                detailLabel("主机（本次运行累计）")
                ForEach(hosts.prefix(6), id: \.ip) { h in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(NetUtil.isPrivate(h.ip) ? P.accent : P.up)
                            .frame(width: 5, height: 5)
                        Text(h.name)
                            .font(.system(size: 10))
                            .foregroundColor(P.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(Fmt.bytes(h.delta.total))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(P.sub)
                    }
                }
            }

            let sockets = state.activeSocketsForApp[key] ?? []
            if !sockets.isEmpty {
                detailLabel("当前连接")
                ForEach(sockets.prefix(6), id: \.self) { s in
                    Text("· \(s)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(P.sub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.border))
    }

    private func detailLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(P.sub)
    }
}

struct MiniSparkline: View {
    var buckets: [Bucket]
    var palette: Palette

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var maxV = 0.0
            for b in buckets { maxV = max(maxV, b.down, b.up) }
            guard maxV > 0 else {
                let text = Text("近 30 分钟无流量").font(.system(size: 8)).foregroundColor(palette.sub.opacity(0.6))
                ctx.draw(text, at: CGPoint(x: w / 2, y: h / 2))
                return
            }
            func line(_ kp: KeyPath<Bucket, Double>) -> Path {
                var p = Path()
                let n = buckets.count
                for (i, b) in buckets.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(max(n - 1, 1))
                    let y = h - 1 - CGFloat(min(b[keyPath: kp] / maxV, 1)) * (h - 2)
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                return p
            }
            ctx.stroke(line(\.up), with: .color(palette.up.opacity(0.7)), lineWidth: 1)
            ctx.stroke(line(\.down), with: .color(palette.down), lineWidth: 1.2)
        }
    }
}
