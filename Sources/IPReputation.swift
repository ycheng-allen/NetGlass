import Foundation
import CryptoKit
import Darwin

struct IPNetworkType {
    enum Kind { case hosting, residential, mobile, business, education, isp, nonResidential, conflict, unknown }
    var kind: Kind
    var title: String
    var evidence: [String]

    static func classify(_ risk: IPRiskDetails?) -> IPNetworkType {
        guard let risk else { return IPNetworkType(kind: .unknown, title: "属性未知", evidence: ["IP 属性数据未取得"]) }
        var hosting: [String] = []
        let company = risk.company_type?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let asn = risk.asnKind?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if risk.is_datacenter == true { hosting.append("数据源标记 is_datacenter = true") }
        if let company, ["hosting", "datacenter", "cdn"].contains(company) { hosting.append("公司类型为 " + company) }
        if let asn, ["hosting", "datacenter", "cdn"].contains(asn) { hosting.append("ASN 类型为 " + asn) }
        let residential = risk.isResidential == true || company == "residential"
        if !hosting.isEmpty {
            if residential { return IPNetworkType(kind: .conflict, title: "属性信息冲突", evidence: hosting + ["数据源同时提供住宅属性，请核对来源"]) }
            return IPNetworkType(kind: .hosting, title: "机房 IP (Hosting)", evidence: hosting)
        }
        if risk.signals?["is_mobile"] == true { return IPNetworkType(kind: .mobile, title: "移动网络 (Mobile)", evidence: ["数据源标记 is_mobile = true"]) }
        if residential {
            return IPNetworkType(kind: .residential, title: "家宽 IP (Residential)", evidence: ["数据源提供明确住宅属性", "住宅网络属性无法验证最后一公里接入方式，也可能用于住宅代理"])
        }
        if company == "business" { return IPNetworkType(kind: .business, title: "企业网络 (Business)", evidence: ["公司类型为 business"]) }
        if company == "education" { return IPNetworkType(kind: .education, title: "教育网络 (Education)", evidence: ["公司类型为 education"]) }
        if company == "isp" || asn == "isp" {
            return IPNetworkType(kind: .isp, title: "运营商网络 (ISP)", evidence: ["来源类型为 ISP，家宽属性待确认"])
        }
        if risk.isResidential == false { return IPNetworkType(kind: .nonResidential, title: "非住宅 IP · 类型待确认", evidence: ["数据源标记 isResidential = false，尚无明确机房依据"]) }
        return IPNetworkType(kind: .unknown, title: "属性未知", evidence: ["缺少明确的住宅或机房属性依据"])
    }
}

struct IPsumObservation: Codable {
    var ip: String?
    var occurrences: Int?
    var checkedAt: Date
    var sourceUpdated: String?
    var version: String?
    var recordCount: Int?
    var error: String?
}

struct IPsumFeed {
    var entries: [String: Int]
    var updated: String?
    var version: String
    static let source = "https://raw.githubusercontent.com/stamparm/ipsum/master/ipsum.txt"

    static func canonical(_ ip: String) -> String? {
        var bytes = [UInt8](repeating: 0, count: 16)
        let family: Int32 = ip.contains(":") ? AF_INET6 : AF_INET
        guard inet_pton(family, ip, &bytes) == 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(family, bytes, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return String(cString: buffer)
    }

    static func parse(_ data: Data) throws -> IPsumFeed {
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix("# IPsum") else { throw URLError(.cannotParseResponse) }
        var entries: [String: Int] = [:]
        var updated: String?
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("# Last update:") {
                updated = String(line.dropFirst("# Last update:".count)).trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("#") { continue }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, let ip = canonical(String(fields[0])), let count = Int(fields[1]), count > 0 else { throw URLError(.cannotParseResponse) }
            entries[ip] = max(entries[ip] ?? 0, count)
        }
        guard !entries.isEmpty, updated != nil else { throw URLError(.cannotParseResponse) }
        let version = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
        return IPsumFeed(entries: entries, updated: updated, version: version)
    }

    func observation(ip: String?) -> IPsumObservation {
        guard let ip, let normalized = Self.canonical(ip) else { return IPsumObservation(checkedAt: Date(), sourceUpdated: updated, version: version, recordCount: entries.count, error: "Claude 出口未知，无法匹配名单") }
        if normalized.contains(":"), !entries.keys.contains(where: { $0.contains(":") }) {
            return IPsumObservation(ip: ip, checkedAt: Date(), sourceUpdated: updated, version: version, recordCount: entries.count, error: "当前名单未包含 IPv6 条目，此 IPv6 出口无法评估")
        }
        return IPsumObservation(ip: ip, occurrences: entries[normalized] ?? 0, checkedAt: Date(), sourceUpdated: updated, version: version, recordCount: entries.count)
    }
}

extension IPAssessmentHTTP {
    func ipSum(ip: String?) async -> IPsumObservation {
        do {
            let body = try await data(IPsumFeed.source, maximumBytes: 20_000_000)
            let feed = try IPsumFeed.parse(body)
            return feed.observation(ip: ip)
        } catch { return IPsumObservation(ip: ip, checkedAt: Date(), error: error.localizedDescription) }
    }
}

extension IPAssessmentResult {
    var networkType: IPNetworkType {
        let original = IPNetworkType.classify(risk)
        guard let identity = checkedIP?.type else { return original }
        let hosting = ["datacenter", "hosting"].contains(identity.type ?? "") || checkedIP?.risk?.is_datacenter == true
        let residential = identity.type == "residential"
        let source = "CheckMyIP · " + (identity.source ?? "来源未说明") + " · " + (identity.confidence ?? "置信度未知")
        let evidence = [source] + (identity.reasons ?? []) + ["Net.Coffee：" + original.title]
        if (hosting && original.kind == .residential) || (residential && original.kind == .hosting) || original.kind == .conflict {
            return IPNetworkType(kind: .conflict, title: "来源分类有差异", evidence: evidence + original.evidence)
        }
        if hosting {
            let estimated = identity.source?.hasPrefix("heuristic:") == true
            return IPNetworkType(kind: .hosting, title: estimated ? "疑似机房 IP · 名称推断" : "机房 IP (Hosting)", evidence: evidence)
        }
        if residential && [.unknown, .nonResidential, .isp].contains(original.kind) {
            return IPNetworkType(kind: .residential, title: "疑似住宅网络 · 待核实", evidence: evidence + ["网络归类不能证明实际家宽接入，也不能排除住宅代理"])
        }
        if identity.type == "mobile", [.unknown, .nonResidential, .isp].contains(original.kind) {
            return IPNetworkType(kind: .mobile, title: "移动网络 (Mobile)", evidence: evidence)
        }
        return IPNetworkType(kind: original.kind, title: original.title, evidence: original.evidence + evidence)
    }
}
