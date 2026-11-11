# Claude 账号风险标记依据

核对日期：2026-11-11。标记用于解释观测结果，不计算封号概率。账号规则自查清单已从风险页移除，下表保留为文档参考。

## 官方说明与可检测范围

| 事项 | 依据 | NetGlass 的处理 |
| --- | --- | --- |
| 反复违反使用政策 | [官方停用与申诉说明](https://support.claude.com/en/articles/8241253-safeguards-warnings-and-appeals) | 文档自查参考，不读取对话或平台警告 |
| 不支持地区注册及地区要求 | [官方停用说明](https://support.claude.com/en/articles/8241253-safeguards-warnings-and-appeals)、[地区帮助页](https://support.claude.com/en/articles/8461763-where-can-i-access-claude) | 仅在官方列表解析成功、版本可用且与本次定位一致时标记规则关联；不能证明实际所在地或注册地 |
| 账号或凭据共享、转售 | [消费者条款 §2–3](https://www.anthropic.com/legal/consumer-terms) | 文档自查参考，无法从网络属性判断 |
| 未经允许的自动化、抓取、绕过保护 | [消费者条款 §3](https://www.anthropic.com/legal/consumer-terms) | 文档自查参考，保留 API Key 和明确许可的例外，不把正常官方 Claude Code 使用认作违规 |
| 第三方收集或中转订阅凭据 | [Claude Code 官方认证说明](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use) | 文档自查参考，不扫描或收集用户凭据 |

这些规则本身有官方依据，但不代表本工具已检测到用户违反它们。账号层面是否违规和处理结果由平台判断。

## 观测项目如何标记

- **官方规则关联**：本次出口定位未匹配有效的官方地区列表。标签要求人工核对，不直接判定地区违规。
- **第三方信誉**：地址级 DNSBL、botnet-c2、IPsum 收录、VPN/代理/中继或机房标记。保留提供者链接，不当作 Anthropic 的封号标准。
- **环境观测**：HTTP/UDP 路径、DNS、时区、语言、指纹差异。只解释测试环境，不判定账号违规。
- **第三方地区参考**：参考站的受限地区表独立呈现，不能升级成官方规则命中。

未找到官方公开的“机房 IP 必封”“VPN 必封”或 DNS、时区、语言不一致的封号阈值。社区帖与代理服务商的归因没有用于生成官方标签。第三方低信誉也不等于账号违规。

## 验证弹窗的解释

[官方身份验证说明](https://support.claude.com/en/articles/14328960-identity-verification-on-claude)介绍了部分功能或平台检查中的身份/业务核验及 Persona 流程。验证要求本身不能确定封号原因，也不能从一次网络测量推断验证结果。网络排查与证件核验分开说明，不采用参考站的“纯净分阈值”作为官方规则。

## 生效日期与证据边界

查询时，[Usage Policy](https://www.anthropic.com/legal/aup) 和 [Supported Regions Policy](https://www.anthropic.com/legal/supported-regions) 页面标注 2026-11-12 生效，晚于核对日期。未将这些未来版本中的新增条款当作 11 月 11 日的现行规则。

地区解析遇到未来生效、无效日期、结构变化或缺失列表时保留未知；旧历史中只有说明文字或第三方规则时，不补造官方判定。历史记录保留原查询时间，应重新评估后判断当前环境。

第三方资料可能过时或冲突；缺失不算通过，住宅属性与高信誉分也不能保证账号安全。HTTP 探测成功不代表账号已获准使用服务。

## 回归检查

`bash Tests/run.sh` 覆盖政策日期格式、未来版本、来源冲突、历史兼容、IPsum 地址范围，以及等价 IPv6 文本不产生错误的路径差异提示。真实账号通知、停用判断和申诉结果不在测试范围内。
