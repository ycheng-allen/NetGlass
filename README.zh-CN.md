[English](README.md) | 中文说明

# NetGlass — GlassWire 风格的 macOS 网络监控器

一个受 [GlassWire](https://www.glasswire.com) 启发的 macOS 原生应用，复刻其核心功能与界面：实时流量图、每应用流量归因、局域网设备发现、应用防火墙管理、安全警报、用量预算、网络诊断与 Claude 出口 IP 风险检测。

![界面](https://img.shields.io/badge/macOS-15.0+-blueviolet) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## 功能

| 页面 | 功能 |
|------|------|
| **图表** | 实时上下行流量图（5 分钟/3 小时/24 小时/7 天/30 天），双显示模式：总量图 / **Top5 应用分色堆叠图**（悬停分解到应用），左侧应用列表带每应用实时速率与窗口期 ↓↑ 总量，**点击应用行展开详情**（近 30 分钟迷你曲线、按主机累计流量、当前 ip:port 连接、火焰阻止按钮），警报以彩色小旗标记在图上（悬停查看内容），可拖拽的时间轴导航，悬停查看历史值 |
| **用量** | 按本地日历的日/周/月统计，应用排行、主机估算流量、CSV 导出、与前一天同时段对比；每网络月度预算及 80% / 100% 提醒 |
| **设备** | 局域网设备发现（网关标记、新设备徽章、首次/最近在线时间），编辑设备别名和信任状态，随网络配置保存 |
| **防火墙** | 对接 macOS 内置应用防火墙；GlassWire 式**火焰开关**：点亮即阻止该应用的**入站连接**、再点放行（需管理员密码），显示每应用实时连接数与速率，展开查看远程主机 |
| **警报** | 新应用/主机/设备、分别检测下载和上传峰值（均值+Nσ）、应用上传/连接数变化、预算阈值、网络健康、DNS、ARP 和防火墙变更；流量峰值保存 Top3 应用快照，可跳转至一分钟图表窗口 |
| **诊断** | 网关/公网 ICMP 与 DNS 测量、按应用连接时间线、自动/手动网络配置、可选出站规则、按时段导出 JSON 报告、分组 HTTP 连通性测试 |
| **Claude 风险检测** | 按需检查出口 IP、归属/ASN、网络身份、信誉估算、来源风险、IPsum/DNSBL、DNS/WebRTC 路径、浏览器环境与本地历史 |
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
- 数据保存在 `~/Library/Application Support/NetGlass/`（配置、分钟/日粒度用量、网络配置、连接、健康探测、警报及最近 30 次 IP 评估 JSON）。
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
bash Tests/run.sh   # 隔离的规则、诊断、IP 评估与连通性回归检查
./build.sh         # 编译普通应用
```

测试覆盖应用隔离、规则优先级、单次授权、到期、域名通配边界、授权消耗状态序列化、连接生命周期、并行连接、重启中断、上传异常、冷却和历史重置。IP 与连通性测试另覆盖 IPv4/IPv6、风险字段未知状态、来源地址匹配与网段粒度、网络分类冲突、IPsum 解析、信誉计算、参考规则、历史兼容、新请求策略、站点列表校验及 HTTP 错误响应。测试使用独立存储和本地 HTTP 模拟，不修改已保存的监控数据，也不访问真实评估服务；不覆盖 WebKit 页面实际执行、第三方服务可用性、系统扩展激活与真实流量拦截。

## 目录结构

```text
NetGlass/
├── build.sh                   # arm64 普通构建 / 运行 / 安装
├── Info.plist
├── README.md / README.zh-CN.md
├── Resources/
│   ├── AppIcon.icns
│   ├── IPProbe.html           # 本地 WebKit 环境与 STUN 探测
│   ├── LinkTargets.json       # 内置 60 个连通性目标
│   └── SiteIcons/             # 内置站点图标
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
│   ├── InsightsTests.swift
│   └── IPAssessmentTests.swift
├── IP检测功能复现调研.md        # 原始调研及仍存在的数据缺口
└── Sources/
    ├── App.swift / AppState.swift     # 生命周期、菜单栏与采样引擎
    ├── Models.swift / Utilities.swift
    ├── NetTopSampler.swift / TrafficStore.swift
    ├── DeviceScanner.swift / LANNudge.swift
    ├── FirewallManager.swift / OutboundFirewall.swift
    ├── AlertCenter.swift / NetworkInsights.swift
    ├── Shell.swift / GraphViews.swift / MenuBarPanel.swift
    ├── UsageAlertsPages.swift / ThingsFirewallPages.swift
    ├── DiagnosticsPage.swift / SettingsPage.swift
    ├── IPAssessment.swift / IPAssessmentDetails.swift / IPAssessmentPage.swift
    ├── IPReputation.swift / IPReputationSummary.swift / IPRiskOverview.swift
    ├── IPBrowserProbe.swift / CheckMyIPBrowserProbe.swift / CheckMyIP.swift
    ├── NetworkConnectivity.swift / NetworkConnectivityPage.swift
    ├── ClaudeAccountRisk.swift / ClaudeAccountPolicyView.swift
    ├── IPEnvironmentRisk.swift
    └── IPExitStability.swift / IPUsage.swift
```

[IP 检测功能复现调研](IP检测功能复现调研.md)整理了候选本地数据源、评分边界与浏览器实时测量方案。当前实现见下面的风险检测与数据来源说明。

## Claude 出口 IP 与网络环境评估

在顶层“Claude风险检测”点击“评估”，查询 Claude、Cloudflare、国内查询服务与 Anthropic 的出口或 HTTP trace 响应，以及 Claude 出口的地理位置、ASN、网络组织和风险标记。支持信誉评分与网络身份，缺失字段保持未知。

每次点击都会新建无持久缓存的请求会话，使用禁止缓存的请求策略及全新请求标识，重新请求属性、官方地区页面和服务状态。DNS 使用新的随机子域名探测令牌，WebRTC 在独立、非持久化的 WebKit 环境内通过 Cloudflare / Google STUN 采集反射地址，同时重新读取设备语言、时区和绘制 Canvas 指纹。页面显示本轮查询时间，第三方数据源自身的更新时间可能未知，后端仍可能使用其服务端缓存。

出口测量代表 NetGlass 的请求路径，WebKit 环境也可能与用户其他浏览器的代理配置不同。HTTP trace 成功不能证明业务登录可用。DNS 展示本轮取得的全部解析器。DNS / UDP 无结果时保留为无法判断，页面省略空结果区域，出口或地区不同只提示核对分流配置。官方地区页面格式变化、查询失败或页面版本尚未生效时，地区支持情况保持未知。

评估会访问页面列明的外部服务，并将出口 IP 交给 Net.Coffee 查询属性和风险标记。NetGlass 自行采集的设备指纹只保存在本机评估历史，不提交到风险查询接口；另行加载的 CheckMyIP 页面会运行其自身的网络与浏览器检测，并可能与其服务通信。最近 30 次结果存储在 `ip-assessments.json`，可隐藏显示中的 IP 或清空历史；隐藏显示不会删除已保存的地址。全局数据重置也会清除此历史。

### 出口与环境检查

- 风险标记支持 VPN、代理、Tor、爬虫、滥用记录、机房、移动网络和 Bogon 等来源字段，并显示来源提供的风险依据、机房名称、ASN 类型、反向 DNS 和路由认证信息。布尔、数字、字符串和嵌套字段分别兼容，缺失项保持未知。
- 为各 HTTP 出口及 UDP 地址查询归属信息，提供 IP 详情链接。DNS 展示本轮取得的全部解析器，地区不同时提示核对分流；地理位置差异无法单独证明泄露。无观测结果仍保持无法判断，页面省略对应空结果。
- 每轮重新下载参考页公开脚本，仅提取地区、代表时区和常用语言规则，记录规则内容版本与获取时间。官方支持地区页面独立查询。时区按当前时刻的 UTC 偏移比较，包含夏令时；地区推定的代表时区会明确标注。
- 设备环境包含系统／WebKit、Cookie、触屏、网络类型、Do Not Track、Canvas SHA-256、WebGL 渲染器及 WebGL SHA-256。指纹采集采用 NetGlass 自己的固定内容，结果代表内置 WebKit 环境。
- 连通性支持独立刷新，并展示官方服务组件及事件状态。HTTP 请求完成与地区规则分别呈现。出口变更历史将相邻的同一 IP 在 24 小时内合并，展示最近六条；完整评估记录继续保留最近 30 次。

### IP 属性分类与 IPsum

IP 属性数据包含机房 IP (Hosting)、家宽 IP (Residential)、移动、企业、教育或运营商网络分类，结合网络身份与来源详情核对。机房依据为数据中心标记、公司 hosting/datacenter/cdn 类型或 ASN 同类标记；家宽要求明确住宅标记。只知道“不是数据中心”时保留属性未知，ISP 标签也不会直接变成家宽。住宅与机房依据同时存在时显示冲突，并可展开分类依据。住宅属性不能验证实际接入线路，也可能出现在住宅代理中。

每次完整评估重新下载 [IPsum](https://github.com/stamparm/ipsum) 的 `ipsum.txt`，校验格式后在本机按 Claude 出口精确匹配。结果展示来源名单的收录数量、快照更新时间、内容版本、条目数量及本轮获取时间。名单获取失败时保留未知状态，页面不显示该项结果，当前快照没有 IPv6 条目时也不会把 IPv6 结果显示成未命中。IPsum 的收录数量独立于 IP 属性分类和原有来源风险标记；未命中不代表没有风险。原始名单不随应用分发，使用项目声明的 Unlicense 数据源并提供来源链接。

### 网络连通性测试

顶层“Claude风险检测”集中显示出口、属性、风险及环境评估。诊断页原来的 IP 子标签改为“网络连通性测试”，按中国、日本、美国和全球分组。内置 60 个参考站点，每次全部测试会重新检查参考页站点列表，失败则保留当前列表并显示原因。

每站测量三次轻量 HTTP 请求，最多九站并发，移除预热和轮间等待。站点图标随应用内置，显示取得 HTTP 响应的请求耗时中位值、每轮状态及分组汇总。支持全部重测、按组重测和停止。结果代表 NetGlass 的网络路径，HTTP 错误状态仍表示取得了响应；圆点提示保留 HTTP 状态或失败原因。这里测量 HTTP 请求耗时，不是 ICMP 延迟或带宽。

### CheckMyIP 来源核对

每次完整评估同时请求 CheckMyIP 的指定 IP `/json?ip=…&mode=full` 接口，校验返回地址与 Claude 出口一致后才采用数据。其首页和 `/api/intel` 可能只返回访问查询站的出口，因此不用于推断 Claude 属性。失败保留原来源和错误信息，历史记录兼容旧版本。Net.Coffee 若返回同一网段其他代表地址，仅保留网络归属参考，清除地址级 VPN、代理、Tor、爬虫、滥用、反向 DNS 及其他地址标记，并提示来源粒度。

地理位置、城市、ASN 和 IP 时区优先使用 CheckMyIP 非空结果，缺失时回退 Net.Coffee；可展开同时核对两个来源及各地理数据库、更新时间和注册资料。新增路由前缀、RIR、注册国家、多起源 ASN、Anycast、城市来源分散距离、Private Relay 与逐项 DNSBL 核查。注册地与定位分开，网段／ASN 名单命中不计为地址命中，未完成核查保持未知，页面仅展示已完成的名单核查。CheckMyIP 的网络名称推断标注“疑似”，住宅／机房正面证据矛盾时显示来源分类差异。

VPN、代理和 Tor 综合展示两家来源的正面线索，并列显示各自状态；未标记不能证明安全。时区和语言仅作环境对照。保留 CheckMyIP 源站风险分，并按其公开公式复算指定 IP 信誉；两种分数的方向分别标注。客户端每次评估重新请求，但第三方及其上游仍可能缓存；界面展示 CheckMyIP 的生成时间、缓存策略和本次查询时间。定位与风险资料并非 Claude 官方风控依据。

数据来源与许可：[CheckMyIP 方法说明](https://checkmyip.com/zh-cn/methodology)、[IP Geolocation by DB-IP（CC BY 4.0）](https://db-ip.com)、[IP2Location.io](https://www.ip2location.io)、[iptoasn（PDDL）](https://iptoasn.com)。

### 信誉与现场检查

每次评估使用全新的临时 WebKit 会话请求 CheckMyIP 页面，运行源站脚本并读取其浏览器信誉、页面 IP 信誉、综合分和逐项检查结果（最长 45 秒）。源站页面出口与 Claude 出口一致时才将页面 IP／综合结果用于 Claude 对照，不一致时保留浏览器现场结果与检查明细，并继续通过指定 IP 接口评估 Claude 出口。远程页面会运行其自身的网络与浏览器检测；临时会话不使用用户浏览器的登录数据。源站页面结构改变或检查失败时在评估记录中保留错误／缺失，不生成虚构分数；页面仅展示已取得的分数与已完成的检查。

IP 信誉依据 CheckMyIP 公开的三类扣分公式（名单、滥用、网络身份），至少两类资料可用才输出估算值；指定地址的接口归类和源站浏览器综合身份推断可能不同，因此分数不保证等同首页现场结果。复用接口中的 hostname、网络身份及依据、ASN 多来源记录、定位共识、名单、源站风险分、计分因素与托管域名查询状态；服务端额度耗尽保持未知，页面省略无结果项目。Claude 使用风险标签仅用于排查出口信誉、匿名工具、托管及地区限制线索，不能预测封号，不代表 Anthropic 官方风控模型。

### 页面展示范围

页面省略未取得的字段、失败的出口探测、空 DNS/UDP/设备区域及未完成的浏览器或 DNSBL 检查。评估记录仍保留原始缺失或错误状态；省略展示不表示检查通过，也不表示不存在风险。

风险检测界面仅展示成功取得的数据：缺失字段、失败的名单项、源站未运行的浏览器检查、无结果的评分卡片和不适用于 Claude 出口的页面评分均隐藏，空结果区块也不显示。隐藏不改变底层计分资格：缺失检查仍不算通过，部分评分仍注明资料完整度；真实的否定结果（例如未命中名单）继续保留。

DNS、WebRTC UDP、设备与 IP 时区差异在风险区独立展示，标为环境观测并计入需要核对的项目。UDP 仅比较有效公网候选地址且标准化 IPv6；DNS 仅对已有解析器地区作差异提示，地区差异不能确认泄露；时区按本次时间的 UTC 偏移比较，考虑夏令时与同偏移别名，不以国家代表时区估算产生风险。源站现场结果作为缺失本地观测时的补充并说明出口范围，失败或未运行不产生风险。完整评估和刷新连通性都会探测 claude.ai、api.anthropic.com 和 www.anthropic.com。同一轮出现同协议族的不同地址时提示分流差异；双栈使用不同协议本身不触发提示。API 域名 HTTP 探测达到 2 秒会复测一次，两次均达到阈值才提醒。探测来自 NetGlass，无法读取 Claude Code 的 TLS 指纹、连接复用、并发或请求耗时。

参考 [Net.Coffee Claude Code 指南](https://ip.net.coffee/claude/claudecode.html) 和[身份验证排查](https://ip.net.coffee/claude/identity.html)，经验性分数阈值不作官方风控规则。验证说明以[官方帮助](https://support.claude.com/en/articles/14328960-identity-verification-on-claude)核对，区分网络验证与证件核验，不预测账号处理结果。

## 账号风险标记的依据

账号停用规则自查清单已按需求从风险页移除。首页优先展示触发项与实测原因，信誉、网络类型、原始情报和历史可按需查看。VPN、机房属性以及 DNS／时区差异不直接判定为 Claude 违规。账号内容、共享与凭据使用未进行检测。官方地区规则只有在版本可用、解析成功且与本次定位匹配时才产生关联提示；未来版本和未经验证的历史不生成官方命中。

详见 [账号风险标记依据](Docs/Claude-account-risk.md)，含 2026-11-11 的核对结果、生效日期边界与测试范围。

### 使用类型、威胁情报与出口稳定性

复用 Net.Coffee IP 页实际使用的 `/api/ip/lookup/{Claude出口IP}` 替换简版属性查询；验证返回地址或限定同网段归属。使用类型整合进原网络身份卡片，包含运营商类型、企业／服务商及来源的公共服务、爬虫、住宅、移动或托管标记。人机流量仅给类型参考，不冒充实测流量比例。IP 情报集中展示两家风险标记、Net.Coffee 威胁条目、滥用等级与原始值、HTTP 蜜罐值、RPKI、IPsum 及逐项 DNSBL；蜜罐值按参考页原始值 /25.5 映射到 0–10，缺失不算 0。同网段代表记录不迁移地址级威胁情报。定位与来源信息折叠，移除重复类型、名单和账号停用自查区块。

出口稳定性使用最多 30 条本地评估：观察截止于当前记录的最近 1 小时，只有相邻两次均有明确机房依据的地址改变才计数。至少 3 次切换且当前仍为机房时提示核对；住宅、未知或冲突记录中断计数。相同 IP 的 IPv6 写法归一化，重复记录 ID、不在时间窗口或未来记录不参与。家宽偶尔变化或长期不变均不按此规则提醒；这是本地排查阈值，不是 Anthropic 的风控或限速标准，也不能据此认定已有行为异常。


使用场景卡展示 Net.Coffee 返回的运营商类型、服务商及按定位与注册地区对照的“原生／广播 IP”。每次完整评估重新请求 ASN Radar 数据，按源站公开规则调整人机比例；来源不可用时按网络类型估算并标注。比例描述 ASN 群体参考，无法代表本机流量。TikTok、社媒运营、AI 应用分数按源站公开场景规则在本机复算并以圆环展示，实际可用性以访问为准。IPv6 和缺失必要字段时省略比例与场景分数。机房类型卡显示最近一小时本地样本与切换次数，达到三次切换时在顶部风险区提示。

机房类型本身会显示使用风险提示，名称推断的机房会明确标为“疑似”。最近一小时至少三次机房出口切换升级为红色“重大风险”，替换普通机房提示，并优先显示。这是本地网络风险分级。
