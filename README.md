[中文说明](README.zh-CN.md) | English

# NetGlass — a GlassWire-style network monitor for macOS

A native macOS app inspired by [GlassWire](https://www.glasswire.com), recreating its core features and look: real-time traffic graphs, per-app traffic attribution, LAN device discovery, an app firewall, security alerts, usage budgets, and network diagnostics.

![macOS](https://img.shields.io/badge/macOS-15.0+-blueviolet) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## Features

| Page | What it does |
|------|--------------|
| **Graph** | Live download/upload chart (5 min / 3 h / 24 h / 7 days / 30 days) with two display modes: total, or **stacked per-app** (top-5 apps as colored layers, hover for per-app breakdown). Left-hand app list with per-app live rates and window totals. Tap an app row to expand its detail panel: 30-minute sparkline, per-host traffic totals, live `ip:port` connections, and a flame block button. Alerts appear as colored pennants on the chart (hover for details). Draggable two-handle timeline navigator, hover tooltips, active app/host indicator strip. |
| **Usage** | Local-calendar daily / weekly / monthly stats, per-app rankings and estimated per-host totals, CSV export, comparison with the previous day, and a per-network monthly budget with 80% / 100% alerts. |
| **Things** | LAN device discovery with gateway/new-device badges and first/last-seen times; editable device aliases and trust saved with each network profile. |
| **Firewall** | Integrates the macOS built-in application firewall. GlassWire-style **flame toggles**: light the flame to block an app’s **inbound connections**, tap again to allow (admin password required). Shows per-app live connection counts and rates; expand to inspect remote hosts. |
| **Alerts** | New app/host/device, separate download/upload spikes (mean + N·σ), upload/connection-count anomalies, budget thresholds, network health, DNS, ARP and firewall changes. Traffic-spike alerts retain the top-three apps and link to a one-minute graph window. |
| **Diagnostics** | Gateway/public ICMP and DNS measurements, per-app connection timeline, automatic/manual network profiles, optional outbound rules, and time-range JSON report export. |
| **Menu bar** | Live ⇩/⇧ rates in the menu bar. Left click opens a popover panel (30-min mini chart, top-3 apps, pause/open buttons, current budget); right click keeps the classic menu. |
| **Settings** | Sampling interval, history retention, dark/light theme, launch at login, per-alert toggles, spike σ threshold, monthly budget and billing day, data reset. |

## Build & run

```bash
cd NetGlass
./build.sh           # produces build/NetGlass.app
./build.sh run       # build and launch
./build.sh install   # build, install to /Applications, relaunch
```

- Targets Apple Silicon (`arm64`) and macOS 15 or later.
- Requires full Xcode (the CLT `swiftc` cannot load the SwiftUI macro plugins used by `@State` etc.).
- Uses standalone Swift sources and shell scripts; there is no `.xcodeproj` or Swift package. The ordinary build is ad-hoc signed and needs no developer account. Enabling outbound filtering requires the separately signed extension described below.
- Data lives in `~/Library/Application Support/NetGlass/` (settings, minute/day usage, network profiles, connections, health samples and alerts).
- Dock icon: `Resources/AppIcon.icns`, drawn by `Scripts/make_icon.swift` with CoreGraphics to match the in-app logo (dark rounded tile + four-color radial pinwheel + white highlight arc). After changing the logo, re-run the script and `iconutil -c icns`.

## Data sources and history

- **Per-process traffic**: polls `nettop -P -L 1 -J bytes_in,bytes_out` (cumulative counters, differenced per tick). Processes are merged into apps via `NSRunningApplication` and prefix-matching against `/Applications` (covering helpers like Chrome Helper).
- **Remote-host attribution**: `lsof -nP -i -F pcnP` yields each process's remote endpoints; an app's byte delta is spread evenly across its live remote hosts. Hostnames resolved asynchronously via the system resolver, with caching.
- **History strategy**: raw samples in RAM for 6 h; minute app/host buckets persisted for 7 days; local-calendar daily rollups retained for 7 / 30 / 90 days. Minute/day history survives restarts. Legacy UTC daily totals are migrated approximately because their original local-day boundaries cannot be recovered.
- Traffic covers periods when NetGlass is monitoring. Per-host bytes are estimates from app counters and observed endpoints, rather than packet-level measurements. Partial-minute/day queries include available aggregate buckets. Notifications require system permission; inbound firewall changes require administrator authentication.

## Local-network discovery limits

Some GUI environments restrict local-network access: neighbor-table entries can be hidden, and UDP/ICMP probes can fail. Availability depends on the system and its permission state; an empty result does not prove that no devices are present.

1. Discovery first reads MAC-bearing host routes from `netstat -rn`, enabling the bundled vendor lookup and gateway MAC-change alerts when available.
2. If no entries are visible, a full scan falls back to TCP connections in the local IPv4 /24 on ports 80, 445 and 62078. Successful connections or explicit refusals count as responses; silent devices can be missed.
3. The gateway is listed explicitly. Without a readable MAC, devices use IP/reverse DNS and cannot provide reliable vendor or ARP-spoof information. IP changes can also affect device identity.

## Inbound firewall

The Firewall page and flame controls use `/usr/libexec/ApplicationFirewall/socketfilterfw`, which manages macOS **inbound** application rules. Changes request an administrator password through osascript. Outbound rules are managed separately in Diagnostics and require the optional signed system extension.

## Diagnostics and network profiles

- **Network health**: measures the gateway and `1.1.1.1` with ICMP, plus the default DNS server’s query time for `example.com`, every 30 seconds. No-response percentages describe these probes; ICMP restrictions can resemble a connectivity failure.
- **Connection timeline**: polls `lsof` about every ten seconds, recording app, protocol, local/remote endpoints and observed start/end times. Short connections can be missed. Closed records are pruned after seven days, with a 20,000-record target that preserves active connections. Connections left open at a restart are marked interrupted.
- **Network profiles**: save separate budgets, alert options, device aliases and trust. Automatic identity combines interface, available Wi-Fi name, gateway and IPv4 subnet prefix. Networks can share an identity when the OS hides the Wi-Fi name; create or select a manual profile to distinguish them. Per-network daily usage is retained for up to 90 days.
- **Budgets and behavior**: set a monthly allowance in decimal GB (`0` disables it), with a billing day from 1–28. Budget alerts fire at 80% and 100%. Upload/connection-count baselines survive restarts; behavior alerts have a ten-minute cooldown. Connection-count alerts indicate a version change when that metadata is available.
- **Reports**: export selected-time-range quality samples, aggregate app traffic, connection observations, network changes and alerts as JSON. Reports contain app names, addresses and network identifiers.

## Optional outbound filtering

The Network Extension in `Extension/` uses the policy in `Shared/`. The ordinary build supports saving rules but does not bundle or activate the extension.

- Rules match an app’s signing identifier and an IP, hostname, `*.example.com`, or `*`. Unmatched flows are allowed, and newer matching rules take priority.
- “Allow once” grants one new flow; “allow ten minutes” grants new flows until ten minutes after rule creation. Once consumed/expired, these rules block subsequent matching new flows. Existing flows may continue.
- Hostname matching depends on metadata supplied by the OS. Use IP rules when that metadata is unavailable. Flows whose app identity or rule file cannot be read are allowed.

A deployable build requires a Developer ID Application signing identity and app/extension provisioning profiles with Network Extension, System Extension installation and App Group capabilities:

```bash
export NETGLASS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NETGLASS_TEAM_ID="TEAMID"
export NETGLASS_APP_PROFILE="/absolute/path/app.provisionprofile"
export NETGLASS_FILTER_PROFILE="/absolute/path/filter.provisionprofile"
bash Scripts/build_outbound.sh
```

Bundle IDs: `com.allen.netglass` and `com.allen.netglass.filter`; App Group: `group.com.allen.netglass`. Install the resulting signed app in `/Applications`, then enable filtering in **Diagnostics → Outbound rules** and grant the requested system approvals. Signed installation and live traffic enforcement require validation with those credentials.

## Validation

```bash
bash Tests/run.sh   # isolated policy and insights regression checks
./build.sh         # compile the ordinary app
```

The tests cover app isolation, rule priority, one-time grants, expiry, hostname wildcard boundaries, consumed-grant serialization, connection lifecycle, parallel sockets, restart interruption, upload anomalies, cooldown and history reset. They use isolated in-memory storage and do not modify saved monitoring data. They do not exercise live system-extension activation or network enforcement.

## Project layout

```text
NetGlass/
├── build.sh                   # ordinary arm64 app build / run / install
├── Info.plist
├── README.md / README.zh-CN.md
├── Resources/AppIcon.icns
├── Scripts/
│   ├── make_icon.swift        # CoreGraphics app-icon generator
│   └── build_outbound.sh      # build, embed and sign the optional extension
├── Shared/OutboundRule.swift  # outbound policy shared by app, extension and tests
├── Extension/
│   ├── main.swift
│   └── FilterDataProvider.swift
├── Tests/
│   ├── run.sh
│   ├── OutboundRulesTests.swift
│   └── InsightsTests.swift
├── IP检测功能复现调研.md        # IP-detection research; not an implemented feature
└── Sources/
    ├── App.swift / AppState.swift     # lifecycle, menu bar and sampling engine
    ├── Models.swift / Utilities.swift
    ├── NetTopSampler.swift / TrafficStore.swift
    ├── DeviceScanner.swift / LANNudge.swift
    ├── FirewallManager.swift / OutboundFirewall.swift
    ├── AlertCenter.swift / NetworkInsights.swift
    ├── Shell.swift / GraphViews.swift / MenuBarPanel.swift
    ├── UsageAlertsPages.swift / ThingsFirewallPages.swift
    └── DiagnosticsPage.swift / SettingsPage.swift
```

See [IP-detection research](IP检测功能复现调研.md) (Chinese) for candidate local datasets, scoring constraints and live browser measurements. IP geolocation, reputation scoring and browser-leak detection remain research proposals.
