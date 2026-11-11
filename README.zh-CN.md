[English](README.md) | 中文说明

# NetGlass — GlassWire 风格的 macOS 网络监控器

一个受 [GlassWire](https://www.glasswire.com) 启发的 macOS 原生应用，复刻其核心功能与界面：实时流量图、每应用流量归因、局域网设备发现、应用防火墙管理、安全警报、用量预算与网络诊断。

![界面](https://img.shields.io/badge/macOS-15.0+-blueviolet) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## 功能

| 页面 | 功能 |
|------|------|
| **图表** | 实时上下行流量图（5 分钟/3 小时/24 小时/7 天/30 天），双显示模式：总量图 / **Top5 应用分色堆叠图**（悬停分解到应用），左侧应用列表带每应用实时速率与窗口期 ↓↑ 总量，**点击应用行展开详情**（近 30 分钟迷你曲线、按主机累计流量、当前 ip:port 连接、火焰阻止按钮），警报以彩色小旗标记在图上（悬停查看内容），可拖拽的时间轴导航，悬停查看历史值 |
| **用量** | 按本地日历的日/周/月统计，应用排行、主机估算流量、CSV 导出、与前一天同时段对比；每网络月度预算及 80% / 100% 提醒 |
| **设备** | 局域网设备发现（网关标记、新设备徽章、首次/最近在线时间），编辑设备别名和信任状态，随网络配置保存 |
| **防火墙** | 对接 macOS 内置应用防火墙；GlassWire 式**火焰开关**：点亮即阻止该应用的**入站连接**、再点放行（需管理员密码），显示每应用实时连接数与速率，展开查看远程主机 |
| **警报** | 新应用/主机/设备、分别检测下载和上传峰值（均值+Nσ）、应用上传/连接数变化、预算阈值、网络健康、DNS、ARP 和防火墙变更；流量峰值保存 Top3 应用快照，可跳转至一分钟图表窗口 |
| **诊断** | 网关/公网 ICMP 与 DNS 测量、按应用连接时间线、自动/手动网络配置、可选出站规则、按时段导出 JSON 报告 |
| **菜单栏** | 实时 ⬇︎/⬆︎ 速率；左键弹出面板（30 分钟迷你图、Top3 应用、预算、暂停/打开窗口），右键显示传统菜单 |
| **设置** | 采样间隔、历史保留天数、深色/浅色主题、开机自启、各类警报开关与 σ 阈值、月度预算与结算日、数据重置 |

## 构建与运行

```bash
cd NetGlass
./build.sh        # 产出 build/NetGlass.app
./build.sh run    # 构建并启动
./build.sh install # 构建、安装到 /Applications 并重新启动
```

- 当前脚本面向 Apple Silicon（`arm64`）及 macOS 15 或更新版本。
- 需要 Xcode（`xcodebuild` 所在的完整工具链，CLT 的 swiftc 加载不了 SwiftUI 宏插件）。
- 项目由独立 Swift 源码和脚本组成，没有 `.xcodeproj` 或 Swift package。普通构建使用 ad-hoc 签名，无需开发者账号；出站过滤需要下述单独签名的扩展。
- 数据保存在 `~/Library/Application Support/NetGlass/`（配置、分钟/日粒度用量、网络配置、连接、健康探测和警报 JSON）。
- Dock 图标：`Resources/AppIcon.icns`，由 `Scripts/make_icon.swift` 用 CoreGraphics 按界面内 Logo（深色圆角底 + 四色渐变风车圆 + 白色高光弧）绘制生成，改 Logo 后重跑该脚本 + `iconutil -c icns` 即可。

## 数据来源与历史保存

- **每进程流量**：轮询 `nettop -P -L 1 -J bytes_in,bytes_out`（累积字节数做差分），进程经 `NSRunningApplication` 与 `/Applications` 前缀匹配归并到应用（含 Chrome Helper 这类子进程）。
- **远程主机归因**：`lsof -nP -i -F pcnP` 提取每进程的远端地址，在该应用当前观察到的远程主机间均摊流量增量；主机名经系统解析器反解（异步、缓存）。
- **历史策略**：原始采样驻内存 6 小时；应用/主机分钟桶落盘保留 7 天；按本地日历汇总的日数据保留 7 / 30 / 90 天。分钟与日历史可跨重启恢复。旧 UTC 日数据只能近似迁移，无法恢复原始本地日期边界。
- 流量只覆盖 NetGlass 监控期间。主机流量由应用计数与观察到的地址估算，不是逐包计量；查询部分分钟或日期时会包含对应汇总桶。系统通知需授权，入站防火墙修改需管理员认证。

## 局域网发现的限制

部分 GUI 运行环境会限制本地网络访问，例如隐藏邻居表、阻止 UDP 或 ICMP 探测。具体表现取决于系统和权限状态，空结果不能证明网络中没有设备。

1. 优先读取 `netstat -rn` 中带 MAC 的主机路由，可用时提供内置厂商查询与网关 MAC 变化告警。
2. 无可见记录时，完整扫描降级为本地 IPv4 /24 的 TCP 探测（端口 80/445/62078）。连接成功或明确拒绝视为响应，静默设备可能漏检。
3. 网关始终显式展示。无法读取 MAC 时以 IP/反向 DNS 展示设备，无法可靠提供厂商与 ARP 欺骗信息；IP 变化也可能影响设备身份识别。

## 入站防火墙

防火墙页与火焰按钮基于 `/usr/libexec/ApplicationFirewall/socketfilterfw`，管理 macOS 应用的**入站**允许/阻止，修改时通过 osascript 弹出管理员认证。出站规则在诊断页单独管理，需要可选的已签名系统扩展。

## 网络诊断与网络配置

- **网络健康**：每 30 秒测量网关与 `1.1.1.1` 的 ICMP 延迟，以及默认 DNS 服务器对 `example.com` 的查询耗时。无响应比例仅代表这些探测，ICMP 受限时不能据此确定断网。
- **连接时间线**：约每十秒轮询 `lsof`，记录应用、协议、本地/远端地址及观察到的开始/结束时间。短连接可能漏记；已结束记录按七天清理，总量以两万条为目标并优先保留活跃连接。重启前尚未观察到结束的连接标为中断。
- **网络配置**：独立保存预算、告警选项、设备别名与信任。自动标识由接口、可取得的 Wi-Fi 名称、网关和 IPv4 子网前缀组成。系统隐藏 Wi-Fi 名称时，不同网络可能共用标识，可新建或手动选择配置区分。每网络日用量最多保留 90 天。
- **预算与行为**：月度额度以十进制 GB 计，`0` 关闭，结算日可设为 1–28 日；达到 80% / 100% 时提醒。应用上传与连接数基线跨重启保存，行为告警有十分钟冷却。版本信息可取得时，连接数告警会标出版本变化。
- **诊断报告**：按所选时段导出质量探测、应用流量汇总、连接观察、网络切换和警报 JSON。文件包含应用名、地址和网络标识。

## 可选出站过滤

`Extension/` 中的 Network Extension 使用 `Shared/` 的共享策略。普通构建可保存规则，但不内置或激活系统扩展。

- 按应用签名标识及 IP、主机名、`*.example.com` 或 `*` 匹配。未匹配的流默认放行，较新的匹配规则优先。
- “允许一次”授权一个新流；“允许十分钟”从规则创建起计算十分钟。耗尽或到期后阻止后续匹配的新流，已有连接可能继续传输。
- 域名匹配依赖系统提供的主机名，缺少时需使用 IP 规则。无法读取应用身份或规则文件的流默认放行。

实际部署需要 Developer ID Application 签名身份、主应用与扩展各自的 provisioning profile，以及 Network Extension、System Extension 安装和 App Group 授权：

```bash
export NETGLASS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NETGLASS_TEAM_ID="TEAMID"
export NETGLASS_APP_PROFILE="/absolute/path/app.provisionprofile"
export NETGLASS_FILTER_PROFILE="/absolute/path/filter.provisionprofile"
bash Scripts/build_outbound.sh
```

Bundle ID 分别为 `com.allen.netglass`、`com.allen.netglass.filter`；App Group 为 `group.com.allen.netglass`。将生成的已签名应用安装到 `/Applications`，在**诊断 → 出站规则**启用，并完成系统批准。签名安装和实际流量拦截仍需使用相应凭据验证。

## 验证

```bash
bash Tests/run.sh   # 隔离的规则与诊断逻辑回归检查
./build.sh         # 编译普通应用
```

测试覆盖应用隔离、规则优先级、单次授权、到期、域名通配边界、授权消耗状态序列化、连接生命周期、并行连接、重启中断、上传异常、冷却和历史重置。测试使用独立的内存存储，不修改已保存的监控数据；不覆盖系统扩展的实际激活与流量拦截。

## 目录结构

```text
NetGlass/
├── build.sh                   # arm64 普通构建 / 运行 / 安装
├── Info.plist
├── README.md / README.zh-CN.md
├── Resources/AppIcon.icns
├── Scripts/
│   ├── make_icon.swift        # CoreGraphics 图标生成
│   └── build_outbound.sh      # 构建、嵌入并签名可选扩展
├── Shared/OutboundRule.swift  # 应用、扩展与测试共享的出站策略
├── Extension/
│   ├── main.swift
│   └── FilterDataProvider.swift
├── Tests/
│   ├── run.sh
│   ├── OutboundRulesTests.swift
│   └── InsightsTests.swift
├── IP检测功能复现调研.md        # 调研材料，尚未实现为应用功能
└── Sources/
    ├── App.swift / AppState.swift     # 生命周期、菜单栏与采样引擎
    ├── Models.swift / Utilities.swift
    ├── NetTopSampler.swift / TrafficStore.swift
    ├── DeviceScanner.swift / LANNudge.swift
    ├── FirewallManager.swift / OutboundFirewall.swift
    ├── AlertCenter.swift / NetworkInsights.swift
    ├── Shell.swift / GraphViews.swift / MenuBarPanel.swift
    ├── UsageAlertsPages.swift / ThingsFirewallPages.swift
    └── DiagnosticsPage.swift / SettingsPage.swift
```

[IP 检测功能复现调研](IP检测功能复现调研.md)整理了候选本地数据源、评分边界与浏览器实时测量方案。IP 定位、信誉评分和浏览器泄漏检测目前仍属于调研计划。
