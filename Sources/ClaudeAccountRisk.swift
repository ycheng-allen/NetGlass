import Foundation

struct ClaudeAccountPolicyItem: Identifiable {
    var id: String
    var title: String
    var detail: String
    var sourceTitle: String
    var sourceURL: String
}

enum ClaudeAccountPolicy {
    static let reviewedOn = "2026-11-11"
    static let appealsURL = "https://support.claude.com/en/articles/8241253-safeguards-warnings-and-appeals"
    static let termsURL = "https://www.anthropic.com/legal/consumer-terms"
    static let regionsURL = "https://www.anthropic.com/legal/supported-regions"
    static let items: [ClaudeAccountPolicyItem] = [
        .init(id: "usage", title: "反复违反使用政策", detail: "官方帮助中心列为停用原因。本工具不读取对话内容或平台警告，需自行核对账号通知。", sourceTitle: "停用原因与申诉", sourceURL: appealsURL),
        .init(id: "location", title: "不支持地区注册与地区限制", detail: "官方列明不支持地区注册可能导致停用。IP 定位不能证明实际所在地、注册地或主体资格，需核对官方地区条款。", sourceTitle: "停用原因与地区要求", sourceURL: appealsURL),
        .init(id: "sharing", title: "账号共享、凭据外借或转售", detail: "消费者条款限制共享登录信息、向他人提供账号及转售服务。本工具无法检测账号持有人和使用授权。", sourceTitle: "消费者条款 §2–3", sourceURL: termsURL),
        .init(id: "automation", title: "未经允许的自动化、抓取或绕过措施", detail: "消费者条款限制自动访问、抓取和绕过保护；API Key 或明确获准的访问有例外，正常使用官方 Claude Code 不据此标记违规。", sourceTitle: "消费者条款 §3", sourceURL: termsURL),
        .init(id: "oauth", title: "第三方转用订阅凭据或会话令牌", detail: "官方文档限制第三方收集或中转 Claude.ai 凭据、代用户路由订阅请求。第三方集成需核对获准的 API 或云服务认证方式。", sourceTitle: "Claude Code 认证与凭据使用", sourceURL: "https://code.claude.com/docs/en/legal-and-compliance")
    ]
}

// Stored with each assessment: a third-party region list is never an official verdict.
struct ClaudeRegionAssessment: Codable {
    enum Status: String, Codable { case listed, unlisted, unknown, notEffective }
    var status: Status
    var countryCode: String?
    var checkedAt: Date
    var effectiveAt: Date?
    var sourceURL = ClaudeAccountPolicy.regionsURL
    var message: String

    static func parse(_ html: String, countryCode: String?, now: Date) -> Self {
        let code = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var result = Self(status: .unknown, countryCode: code, checkedAt: now, message: "未取得出口地区或官方列表，支持情况未知")
        guard let code, Locale.Region.isoRegions.contains(where: { $0.identifier == code }) else { return result }
        let datePattern = #"<time\b[^>]*\bdatetime\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: datePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let value = String(html[range])
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var effective = formatter.date(from: value)
            if effective == nil { formatter.formatOptions = [.withInternetDateTime]; effective = formatter.date(from: value) }
            if effective == nil { formatter.formatOptions = [.withFullDate]; effective = formatter.date(from: value) }
            guard let effective else {
                result.message = "官方页面生效日期无法解析，支持情况未知"
                return result
            }
            result.effectiveAt = effective
            if effective > now {
                result.status = .notEffective
                result.message = "来源页面公布的版本尚未生效，当前支持情况未知"
                return result
            }
        }
        if html.range(of: "Effective", options: .caseInsensitive) != nil, result.effectiveAt == nil {
            result.message = "官方页面生效日期未取得，支持情况未知"
            return result
        }
        guard let marker = html.range(of: "Countries and regions where we currently offer access"),
              let start = html[marker.upperBound...].range(of: "<ul", options: .caseInsensitive),
              let end = html[start.lowerBound...].range(of: "</ul>", options: .caseInsensitive),
              let regex = try? NSRegularExpression(pattern: #"<li\b[^>]*>(.*?)</li>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            result.message = "地区列表格式变化，无法判定"
            return result
        }
        let list = String(html[start.lowerBound..<end.lowerBound])
        let names = regex.matches(in: list, range: NSRange(list.startIndex..., in: list)).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: list) else { return nil }
            return String(list[range]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !names.isEmpty else { result.message = "地区列表格式变化，无法判定"; return result }
        let aliases = ["US": ["United States of America", "United States"], "KR": ["South Korea"],
                       "GB": ["United Kingdom"], "TR": ["Türkiye", "Türkiye (Turkey)"], "CZ": ["Czechia", "Czechia (Czech Republic)"],
                       "CY": ["Cyprus", "Republic of Cyprus"], "TL": ["East Timor", "Timor-Leste"]]
        let expected = aliases[code] ?? [Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? code]
        let matched = names.contains { name in expected.contains { name.caseInsensitiveCompare($0) == .orderedSame || name.lowercased().hasPrefix($0.lowercased() + " (") } }
        result.status = matched ? .listed : .unlisted
        result.message = matched ? "出口定位地区出现在官方列表中，请查看地区条款" : "官方列表未匹配该定位地区，请核对地区条款"
        return result
    }
}
