import Foundation
import AppKit

// MARK: - AppSettings

enum AppearanceMode: String, Codable, CaseIterable {
    case system = "跟随系统"
    case dark = "深色"
    case light = "浅色"

    var colorScheme: ColorSchemeSwap? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

// SwiftUI wrapper to avoid importing SwiftUI here — use string, mapped in views.
enum ColorSchemeSwap {
    case dark, light
}

struct AppSettings: Codable {
    var sampleInterval: Double = 2.0          // seconds
    var retentionDays: Int = 30
    var appearance: AppearanceMode = .dark
    var showMenuBarIcon: Bool = true
    var launchAtLogin: Bool = false

    var alertNewApp: Bool = true
    var alertNewHost: Bool = true
    var alertNewDevice: Bool = true
    var alertSpike: Bool = true
    var alertDNSChange: Bool = true
    var alertARPSpoof: Bool = true
    var alertFirewallChange: Bool = true

    var spikeSigma: Double = 3.0
    var spikeFloorBytes: Double = 262_144     // 256 KB/s

    var autoBlockNewApp: Bool = false
    var graphStacked: Bool = false            // main chart: per-app stacked mode

    // Tolerant decode: older config.json files lack newer keys.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sampleInterval = try c.decodeIfPresent(Double.self, forKey: .sampleInterval) ?? 2.0
        retentionDays = try c.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 30
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .dark
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        alertNewApp = try c.decodeIfPresent(Bool.self, forKey: .alertNewApp) ?? true
        alertNewHost = try c.decodeIfPresent(Bool.self, forKey: .alertNewHost) ?? true
        alertNewDevice = try c.decodeIfPresent(Bool.self, forKey: .alertNewDevice) ?? true
        alertSpike = try c.decodeIfPresent(Bool.self, forKey: .alertSpike) ?? true
        alertDNSChange = try c.decodeIfPresent(Bool.self, forKey: .alertDNSChange) ?? true
        alertARPSpoof = try c.decodeIfPresent(Bool.self, forKey: .alertARPSpoof) ?? true
        alertFirewallChange = try c.decodeIfPresent(Bool.self, forKey: .alertFirewallChange) ?? true
        spikeSigma = try c.decodeIfPresent(Double.self, forKey: .spikeSigma) ?? 3.0
        spikeFloorBytes = try c.decodeIfPresent(Double.self, forKey: .spikeFloorBytes) ?? 262_144
        autoBlockNewApp = try c.decodeIfPresent(Bool.self, forKey: .autoBlockNewApp) ?? false
        graphStacked = try c.decodeIfPresent(Bool.self, forKey: .graphStacked) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case sampleInterval, retentionDays, appearance, showMenuBarIcon, launchAtLogin
        case alertNewApp, alertNewHost, alertNewDevice, alertSpike, alertDNSChange, alertARPSpoof, alertFirewallChange
        case spikeSigma, spikeFloorBytes, autoBlockNewApp, graphStacked
    }

    static func load() -> AppSettings {
        Store.load(AppSettings.self, "config.json") ?? AppSettings()
    }
}

// MARK: - Traffic

/// Per-key byte delta over one sampling tick.
struct Delta: Codable {
    var down: UInt64 = 0
    var up: UInt64 = 0
    var total: UInt64 { down + up }
    mutating func add(_ d: Delta) {
        down &+= d.down
        up &+= d.up
    }
}

/// One raw sample: per-app deltas at a timestamp.
struct RawSample {
    var t: Date
    var apps: [String: Delta]
}

struct Bucket: Identifiable {
    var id: Double { t.timeIntervalSince1970 }
    var t: Date
    var down: Double   // bytes/sec
    var up: Double
}

struct AppMeta {
    var key: String
    var name: String
    var icon: NSImage?
    var bundlePath: String?
    var isSystem: Bool
}

struct AppRow: Identifiable {
    var id: String { key }
    var key: String
    var name: String
    var icon: NSImage?
    var down: UInt64     // window total
    var up: UInt64
    var rate: Double     // current bytes/sec
    var share: Double    // 0...1 of window total
    var isSystem: Bool
}

struct HostRow: Identifiable {
    var id: String { ip }
    var ip: String
    var name: String
    var down: UInt64
    var up: UInt64
    var share: Double
}

// MARK: - Devices

struct Device: Codable, Identifiable {
    var id: String { mac.isEmpty ? "ip-" + ip : mac }
    var mac: String
    var ip: String
    var name: String
    var vendor: String
    var firstSeen: Date
    var lastSeen: Date
    var isGateway: Bool = false
    var acknowledged: Bool = false

    var kindIcon: String {
        let v = (vendor + " " + name).lowercased()
        if v.contains("raspberry") { return "cpu.fill" }
        if v.contains("apple") || v.contains("iphone") { return "iphone.gen3" }
        if v.contains("tv") { return "appletv.fill" }
        if isGateway { return "antenna.radiowaves.left.and.right" }
        if v.contains("watch") { return "applewatch" }
        if v.contains("pad") { return "ipad.landscape" }
        return "laptopcomputer"
    }
}

// MARK: - Alerts

enum AlertType: String, Codable, CaseIterable {
    case newApp = "新应用"
    case newHost = "新主机"
    case newDevice = "新设备"
    case spike = "流量异常"
    case dns = "DNS 变更"
    case arp = "ARP 异常"
    case firewall = "防火墙"

    var icon: String {
        switch self {
        case .newApp: return "app.badge.fill"
        case .newHost: return "link.badge.plus"
        case .newDevice: return "laptopcomputer.and.iphone"
        case .spike: return "chart.line.uptrend.xyaxis"
        case .dns: return "globe"
        case .arp: return "exclamationmark.shield.fill"
        case .firewall: return "flame.fill"
        }
    }
}

/// An alert pinned onto the traffic graph timeline.
struct GraphMarker: Identifiable {
    let id = UUID()
    let t: Date
    let type: AlertType
    let title: String
    let detail: String
}

/// Per-app stacked series for the main chart (bytes/s per slot; last layer = "其他").
struct StackedSeries {
    var names: [String]
    var values: [[Double]]
}

struct AppAlert: Codable, Identifiable {
    var id = UUID()
    var type: AlertType
    var title: String
    var detail: String
    var date: Date
}

// MARK: - Firewall

enum FWBlockState: String {
    case allow = "允许"
    case block = "已阻止"
    case unknown = "未监控"
}

struct FWAppRow: Identifiable {
    var id: String { path }
    var path: String
    var name: String
    var state: FWBlockState
    var activeConnections: Int
    var rate: Double
    var icon: NSImage?
}

// MARK: - Selection window

struct SelectionWindow: Equatable {
    var start: Date
    var end: Date

    var span: TimeInterval { end.timeIntervalSince(start) }

    static let presets: [(String, TimeInterval)] = [
        ("5 分钟", 300), ("3 小时", 3 * 3600), ("24 小时", 24 * 3600),
        ("7 天", 7 * 86400), ("30 天", 30 * 86400),
    ]
}
