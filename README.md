[中文说明](README.zh-CN.md) | English

# NetGlass — a GlassWire-style network monitor for macOS

A native macOS app inspired by [GlassWire](https://www.glasswire.com), recreating its core features and look: real-time traffic graphs, per-app traffic attribution, LAN device discovery, an app firewall, security alerts, and usage statistics.

![macOS](https://img.shields.io/badge/macOS-15.0+-blueviolet) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## Features

| Page | What it does |
|------|--------------|
| **Graph** | Live download/upload chart (5 min / 3 h / 24 h / 7 days / 30 days). Left-hand app list with per-app live rates and window totals. Tap an app row to expand its detail panel: 30-minute sparkline, per-host traffic totals, live `ip:port` connections, and a flame block button. Alerts appear as colored pennants on the chart (hover for details). Draggable two-handle timeline navigator, hover tooltips, active app/host indicator strip. |
| **Usage** | Daily / weekly / monthly stats, ranked tables per app and per host (down/up/share), CSV export. |
| **Things** | LAN device discovery with gateway badge, new-device badge, first/last-seen times. |
| **Firewall** | Integrates the macOS built-in application firewall. GlassWire-style **flame toggles**: light the flame to block an app, tap again to allow (admin password required). Shows per-app live connection counts and rates; expand to inspect remote hosts. |
| **Alerts** | New app online, app reaching a new host, new device on the LAN, traffic spikes (mean + N·σ detection), DNS server changes, ARP spoofing, firewall changes. System notifications plus in-app filtering. |
| **Menu bar** | Live ⇩/⇧ rates in the menu bar, pause monitoring, quick access. |
| **Settings** | Sampling interval, history retention, dark/light theme, launch at login, per-alert toggles, spike σ threshold, data reset. |

## Build & run

```bash
cd NetGlass
./build.sh           # produces build/NetGlass.app
./build.sh run       # build and launch
./build.sh install   # build, install to /Applications, relaunch
```

- Requires full Xcode (the CLT `swiftc` cannot load the SwiftUI macro plugins used by `@State` etc.).
- No Xcode project, no developer account needed; ad-hoc signed.
- Data lives in `~/Library/Application Support/NetGlass/` (settings, daily usage rollups, devices, alerts).
- Dock icon: `Resources/AppIcon.icns`, drawn by `Scripts/make_icon.swift` with CoreGraphics to match the in-app logo (dark rounded tile + four-color radial pinwheel + white highlight arc). After changing the logo, re-run the script and `iconutil -c icns`.

## Where the data comes from (no special permissions needed)

- **Per-process traffic**: polls `nettop -P -L 1 -J bytes_in,bytes_out` (cumulative counters, differenced per tick). Processes are merged into apps via `NSRunningApplication` and prefix-matching against `/Applications` (covering helpers like Chrome Helper).
- **Remote-host attribution**: `lsof -nP -i -F pcn` yields each process's remote endpoints; an app's byte delta is spread evenly across its live remote hosts. Hostnames resolved asynchronously via the system resolver, with caching.
- **History strategy**: raw samples in RAM for 6 h → minute buckets for 24 h → daily rollups on disk (retention configurable).

## macOS 26+ local-network gating (important)

Recent macOS releases silently restrict GUI apps **without local-network permission** (verified on macOS 27.0.1 — and System Settings exposes **no** toggle for it, nor does a prompt ever appear):

- `arp -a` returns nothing and `netstat -rn` hides all host routes (the MAC neighbor table is unreadable)
- Every UDP `sendto` fails with `EPERM` (regardless of destination), and the `ping` subprocess fails silently
- **TCP connects are unaffected** (live hosts answer with an immediate refusal)

How NetGlass copes:

1. Device discovery prefers host routes from `netstat -rn` (they carry MACs when readable, enabling vendor lookup and ARP-spoof detection);
2. When gated, it automatically falls back to a **TCP connect sweep** (own /24 on ports 80/445/62078 — live hosts answer instantly with RST). MAC addresses are unavailable in this mode, so devices are identified by IP + reverse DNS and the vendor shows as "unidentified (system restriction)";
3. The gateway is always listed explicitly.

If local-network access is ever granted (or on older macOS without the gating), MAC/vendor lookups and ARP-spoof detection resume automatically.

## Firewall note

Backed by `/usr/libexec/ApplicationFirewall/socketfilterfw` (the macOS built-in application firewall), which manages **inbound** per-app allow/block; changes prompt for an admin password via osascript. Strict per-app **outbound** blocking would require a Network Extension system extension (paid developer account + signed distribution), which this version does not include.

## Project layout

```
NetGlass/
├── build.sh              # one-shot build script (Xcode toolchain swiftc)
├── Info.plist
├── Scripts/
│   └── make_icon.swift   # CoreGraphics app-icon generator (matches LogoView)
├── Resources/
│   └── AppIcon.icns
└── Sources/
    ├── Utilities.swift        # shell runner, formatting, OUI vendor DB, IP/iface utils, reverse DNS
    ├── Models.swift           # settings / sampling / device / alert / firewall models
    ├── NetTopSampler.swift    # nettop + lsof sampling, app identity & icon resolution
    ├── TrafficStore.swift     # traffic history (raw/minute/day tiers) and window queries
    ├── DeviceScanner.swift    # neighbor-table + TCP-sweep discovery, ARP-spoof detection
    ├── LANNudge.swift         # in-process UDP probe (triggers local-network permission)
    ├── FirewallManager.swift  # socketfilterfw integration
    ├── AlertCenter.swift      # alert store (persisted + system notifications)
    ├── AppState.swift         # central engine (timers, attribution, alert rules, window math)
    ├── Shell.swift            # theme palette, logo, top-bar navigation, flame toggle
    ├── GraphViews.swift       # graph page (chart canvas, timeline navigator, app list, drill-down)
    ├── UsageAlertsPages.swift # usage page, alerts page
    ├── ThingsFirewallPages.swift # things page, firewall page
    ├── SettingsPage.swift     # settings sheet
    └── App.swift              # entry point, menu-bar controller
```
