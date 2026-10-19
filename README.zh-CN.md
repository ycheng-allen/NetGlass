[English](README.md) | 中文说明

# NetGlass — GlassWire 风格的 macOS 网络监控器

一个受 [GlassWire](https://www.glasswire.com) 启发的 macOS 原生应用，复刻其核心功能与界面：实时流量图、每应用流量归因、局域网设备发现、应用防火墙管理、安全警报与用量统计。

![界面](https://img.shields.io/badge/macOS-15.0+-blueviolet) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## 功能

| 页面 | 功能 |
|------|------|
| **图表** | 实时上下行流量图（5 分钟/3 小时/24 小时/7 天/30 天），双显示模式：总量图 / **Top5 应用分色堆叠图**（悬停分解到应用），左侧应用列表带每应用实时速率与窗口期 ↓↑ 总量，**点击应用行展开详情**（近 30 分钟迷你曲线、按主机累计流量、当前 ip:port 连接、火焰阻止按钮），警报以彩色小旗标记在图上（悬停查看内容），可拖拽的时间轴导航，悬停查看历史值 |
| **用量** | 按日/周/月统计，按应用与按主机两张排行表（下载/上传/占比），CSV 导出 |
| **设备** | 局域网设备发现（网关标记、新设备徽章、首次/最近在线时间） |
| **防火墙** | 对接 macOS 内置应用防火墙；GlassWire 式**火焰开关**：点亮即阻止该应用联网、再点放行（需管理员密码），显示每应用实时连接数与速率，展开查看远程主机 |
| **警报** | 新应用联网、新设备接入、流量异常升高（均值+Nσ 判定）、DNS 变更、ARP 欺骗、防火墙变更；支持系统通知与分类筛选 |
| **菜单栏** | 实时 ⬇︎/⬆︎ 速率常驻菜单栏，可暂停监控、快速打开主窗口 |
| **设置** | 采样间隔、历史保留天数、深色/浅色主题、开机自启、各类警报开关与 σ 阈值、数据重置 |

## 构建与运行

```bash
cd NetGlass
./build.sh        # 产出 build/NetGlass.app
./build.sh run    # 构建并启动
```

- 需要 Xcode（`xcodebuild` 所在的完整工具链，CLT 的 swiftc 加载不了 SwiftUI 宏插件）。
- 无需 Xcode 工程、无需开发者账号；ad-hoc 签名。
- 数据保存在 `~/Library/Application Support/NetGlass/`（配置、日粒度用量、设备、警报 JSON）。
- Dock 图标：`Resources/AppIcon.icns`，由 `Scripts/make_icon.swift` 用 CoreGraphics 按界面内 Logo（深色圆角底 + 四色渐变风车圆 + 白色高光弧）绘制生成，改 Logo 后重跑该脚本 + `iconutil -c icns` 即可。

## 数据来源（无需特殊权限）

- **每进程流量**：轮询 `nettop -P -L 1 -J bytes_in,bytes_out`（累积字节数做差分），进程经 `NSRunningApplication` 与 `/Applications` 前缀匹配归并到应用（含 Chrome Helper 这类子进程）。
- **远程主机归因**：`lsof -nP -i -F pcn` 提取每进程的远端地址，按连接数均摊该应用的流量增量；主机名经系统解析器反解（异步、缓存）。
- **历史策略**：原始采样驻内存 6 小时 → 分钟桶 24 小时 → 日粒度落盘（保留天数可配）。

## macOS 26+ 本地网络限制（重要）

较新的 macOS 对**没有「本地网络」权限的 GUI 应用**静默实施以下限制（实测 macOS 27.0.1，且系统设置中**没有**对应开关，也不弹授权框）：

- `arp -a` 输出为空、`netstat -rn` 隐藏全部主机路由（MAC 邻居表不可读）
- 所有 UDP `sendto` 返回 `EPERM`（与目标地址无关），`ping` 子进程静默失败
- **TCP 连接不受影响**（`connect` 对存活主机立即返回 refused/unreach）

NetGlass 的应对：

1. 设备发现优先读 `netstat -rn` 主机路由（含 MAC，可做厂商识别与 ARP 欺骗检测）；
2. 被门控时自动降级为 **TCP 连接扫描**（本机 /24，端口 80/445/62078，存活主机立即 RST）——此时拿不到 MAC，设备以 IP+反向 DNS 识别，厂商显示「未识别（系统限制）」；
3. 网关始终显式展示。

若日后系统开放本地网络权限（或在未启用门控的旧版 macOS 上），MAC/厂商/ARP 欺骗检测自动恢复。

## 防火墙说明

基于 `/usr/libexec/ApplicationFirewall/socketfilterfw`（macOS 内置应用防火墙），管理**入站**连接的按应用允许/阻止，修改时通过 osascript 弹管理员密码。严格的应用级**出站**拦截需要 Network Extension 系统扩展（需付费开发者账号签名分发），本版本未包含。

## 目录结构

```
NetGlass/
├── build.sh              # 一键构建脚本（Xcode 工具链 swiftc）
├── Info.plist
└── Sources/
    ├── Utilities.swift        # Shell 执行、格式化、OUI 厂商库、IP/接口工具、反向 DNS
    ├── Models.swift           # 设置/采样/设备/警报/防火墙数据模型
    ├── NetTopSampler.swift    # nettop + lsof 采样、应用身份与图标解析
    ├── TrafficStore.swift     # 流量历史（原始/分钟/日三层）与窗口查询
    ├── DeviceScanner.swift    # 邻居表 + TCP 扫描设备发现、ARP 欺骗检测
    ├── LANNudge.swift         # 应用内 UDP 探测（触发本地网络权限）
    ├── FirewallManager.swift  # socketfilterfw 集成
    ├── AlertCenter.swift      # 警报中心（持久化 + 系统通知）
    ├── AppState.swift         # 中央引擎（定时器、归因、警报规则、窗口计算）
    ├── Shell.swift            # 主题调色板、Logo、顶栏导航
    ├── GraphViews.swift       # 图表页（主图 Canvas、时间轴导航、应用列表）
    ├── UsageAlertsPages.swift # 用量页、警报页
    ├── ThingsFirewallPages.swift # 设备页、防火墙页
    ├── SettingsPage.swift     # 设置页
    └── App.swift              # 入口、菜单栏控制器
```
