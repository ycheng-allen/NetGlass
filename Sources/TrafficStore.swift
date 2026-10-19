import Foundation

/// Daily per-app / per-host rollups (persisted).
struct DayUsage: Codable {
    var apps: [String: Delta] = [:]
    var hosts: [String: Delta] = [:]
}

/// Central traffic history: raw samples (RAM, 6h), minute buckets (RAM, 24h),
/// day rollups (persisted, retention days).
final class TrafficStore {
    private(set) var raw: [RawSample] = []
    private(set) var minutes: [Int: [String: Delta]] = [:]   // minEpoch -> app deltas
    private(set) var minuteHosts: [Int: [String: Delta]] = [:] // minEpoch -> host deltas
    private(set) var days: [Int: DayUsage] = [:]              // dayEpoch -> rollup
    private let lock = NSLock()

    var rawWindow: TimeInterval { 6 * 3600 }
    var minuteWindow: TimeInterval { 24 * 3600 }

    // MARK: Recording

    func record(t: Date, apps: [String: Delta], hosts: [String: Delta]) {
        lock.lock()
        defer { lock.unlock() }
        raw.append(RawSample(t: t, apps: apps))
        let m = Int(t.timeIntervalSince1970) / 60 * 60
        var md = minutes[m] ?? [:]
        for (k, v) in apps { md[k, default: Delta()].add(v) }
        minutes[m] = md
        var hd = minuteHosts[m] ?? [:]
        for (k, v) in hosts { hd[k, default: Delta()].add(v) }
        minuteHosts[m] = hd
        let d = Int(t.timeIntervalSince1970) / 86400 * 86400
        var day = days[d] ?? DayUsage()
        for (k, v) in apps { day.apps[k, default: Delta()].add(v) }
        for (k, v) in hosts { day.hosts[k, default: Delta()].add(v) }
        days[d] = day
        prune()
    }

    private func prune() {
        let now = Date().timeIntervalSince1970
        let rawCut = now - rawWindow
        raw.removeAll { $0.t.timeIntervalSince1970 < rawCut }
        let minCut = (Int(now - minuteWindow) / 60) * 60
        minutes = minutes.filter { $0.key >= minCut }
        minuteHosts = minuteHosts.filter { $0.key >= minCut }
    }

    func pruneDays(retention: Int) {
        lock.lock()
        defer { lock.unlock() }
        pruneDaysLocked(retention: retention)
    }

    private func pruneDaysLocked(retention: Int) {
        let cut = (Int(Date().timeIntervalSince1970 - Double(retention) * 86400) / 86400) * 86400
        days = days.filter { $0.key >= cut }
    }

    // MARK: Queries

    private enum Source {
        case raw, minute, day
    }

    private func source(for span: TimeInterval) -> Source {
        if span <= rawWindow + 60 { return .raw }
        if span <= minuteWindow + 60 { return .minute }
        return .day
    }

    /// Iterate (t, key, delta) points inside window.
    private func forEachPoint(window: SelectionWindow, keyFilter: ((String) -> Bool)? = nil, _ body: (Date, String, Delta) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        switch source(for: window.span) {
        case .raw:
            for s in raw where s.t >= window.start && s.t <= window.end {
                for (k, d) in s.apps where keyFilter?(k) ?? true { body(s.t, k, d) }
            }
        case .minute:
            let from = Int(window.start.timeIntervalSince1970) / 60 * 60
            let to = Int(window.end.timeIntervalSince1970) / 60 * 60 + 60
            for (m, dict) in minutes where m >= from && m <= to {
                let t = Date(timeIntervalSince1970: Double(m))
                for (k, d) in dict where keyFilter?(k) ?? true { body(t, k, d) }
            }
        case .day:
            let from = Int(window.start.timeIntervalSince1970) / 86400 * 86400
            let to = Int(window.end.timeIntervalSince1970) / 86400 * 86400 + 86400
            for (d, usage) in days where d >= from && d <= to {
                let t = Date(timeIntervalSince1970: Double(d))
                for (k, v) in usage.apps where keyFilter?(k) ?? true { body(t, k, v) }
                for (k, v) in usage.hosts { body(t, "host:" + k, v) }
            }
        }
    }

    func buckets(window: SelectionWindow, slots: Int = 260, keyFilter: ((String) -> Bool)? = nil) -> [Bucket] {
        let span = max(window.span, 1)
        let slotSpan = span / Double(slots)
        var sums = [Double](repeating: 0, count: slots)
        var sumsUp = [Double](repeating: 0, count: slots)
        let base = window.start.timeIntervalSince1970
        forEachPoint(window: window, keyFilter: keyFilter) { t, key, d in
            guard !key.hasPrefix("host:") else { return }
            let idx = Int((t.timeIntervalSince1970 - base) / slotSpan)
            guard idx >= 0, idx < slots else { return }
            sums[idx] += Double(d.down)
            sumsUp[idx] += Double(d.up)
        }
        var out: [Bucket] = []
        out.reserveCapacity(slots)
        for i in 0..<slots {
            let t0 = base + Double(i) * slotSpan
            // For day-level data place the day's average across its slot window.
            let isDay = source(for: window.span) == .day
            let norm = isDay ? max(slotSpan, 86400.0) : slotSpan
            out.append(Bucket(t: Date(timeIntervalSince1970: t0 + slotSpan / 2),
                              down: sums[i] / norm,
                              up: sumsUp[i] / norm))
        }
        return out
    }

    /// Per-key total (down+up) bytes/s per slot for the stacked chart.
    /// Returns arrays aligned with `keys`.
    func stackedTotals(window: SelectionWindow, keys: [String], slots: Int = 260) -> [[Double]] {
        let span = max(window.span, 1)
        let slotSpan = span / Double(slots)
        var sums = [[Double]](repeating: [Double](repeating: 0, count: slots), count: keys.count)
        let idxOf = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
        let base = window.start.timeIntervalSince1970
        forEachPoint(window: window) { t, k, d in
            guard let ki = idxOf[k] else { return }
            let idx = Int((t.timeIntervalSince1970 - base) / slotSpan)
            guard idx >= 0, idx < slots else { return }
            sums[ki][idx] += Double(d.down + d.up)
        }
        return sums.map { $0.map { $0 / slotSpan } }
    }

    /// Miniature overview across the whole retained history.
    func overviewBuckets(retentionDays: Int, slots: Int = 120) -> [Bucket] {
        let end = Date()
        let start = end.addingTimeInterval(-Double(retentionDays) * 86400)
        return buckets(window: SelectionWindow(start: start, end: end), slots: slots)
    }

    func appTotals(window: SelectionWindow) -> [String: Delta] {
        var out: [String: Delta] = [:]
        forEachPoint(window: window) { _, k, d in
            guard !k.hasPrefix("host:") else { return }
            out[k, default: Delta()].add(d)
        }
        return out
    }

    func hostTotals(window: SelectionWindow) -> [String: Delta] {
        var out: [String: Delta] = [:]
        if source(for: window.span) == .day {
            forEachPoint(window: window) { _, k, d in
                if k.hasPrefix("host:") { out[String(k.dropFirst(5)), default: Delta()].add(d) }
            }
        } else {
            lock.lock()
            defer { lock.unlock() }
            let from = Int(window.start.timeIntervalSince1970) / 60 * 60
            let to = Int(window.end.timeIntervalSince1970) / 60 * 60 + 60
            for (m, dict) in minuteHosts where m >= from && m <= to {
                for (ip, d) in dict { out[ip, default: Delta()].add(d) }
            }
        }
        return out
    }

    func total(window: SelectionWindow) -> Delta {
        var out = Delta()
        forEachPoint(window: window) { _, k, d in
            guard !k.hasPrefix("host:") else { return }
            out.add(d)
        }
        return out
    }

    func firstSampleDate() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return raw.first?.t
    }

    // MARK: Persistence

    func loadFromDisk(retention: Int) {
        lock.lock()
        defer { lock.unlock() }
        if let loaded = Store.load([Int: DayUsage].self, "daily.json") {
            days = loaded
        }
        pruneDaysLocked(retention: retention)
    }

    func saveToDisk() {
        lock.lock()
        let snapshot = days
        lock.unlock()
        Store.save(snapshot, "daily.json")
    }

    func reset() {
        lock.lock()
        raw.removeAll()
        minutes.removeAll()
        minuteHosts.removeAll()
        days.removeAll()
        lock.unlock()
        Store.remove("daily.json")
    }
}
