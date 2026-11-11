import Foundation
import Combine
import Darwin

struct IPExit: Codable, Identifiable {
    var id: String { name + "|" + (ip ?? "") }
    var name: String
    var ip: String?
    var country: String?
    var milliseconds: Double?
    var error: String?
    var geo: IPGeo?
    var geoError: String?
    var source: String?
}

struct IPRiskDetails: Codable {
    var ip: String?
    var cidr: String?
    var country: String?
    var countryCode: String?
    var region: String?
    var city: String?
    var asn: Int?
    var asOrganization: String?
    var isResidential: Bool?
    var is_datacenter: Bool?
    var is_vpn: Bool?
    var is_proxy: Bool?
    var is_tor: Bool?
    var is_crawler: Bool?
    var is_abuser: Bool?
    var company_name: String?
    var company_type: String?
    var timezone: String?
    var signals: [String: Bool]?
    var evidence: [IPRiskEvidence]?
    var datacenterName: String?
    var reverseDNS: String?
    var asnKind: String?
    var registeredCountry: String?
    var rpki: String?
    var isp: String?
    var abuseLevel: String?
    var abuseScoreRaw: String?
    var honeypotThreat: Double?
    var sceneTrustScore: Double?
}

struct IPGeo: Codable {
    var country: String?
    var country_code: String?
    var region: String?
    var city: String?
    var isp: String?
}

struct IPAssessmentResult: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var exits: [IPExit]
    var risk: IPRiskDetails?
    var riskError: String?
    var riskCheckedAt: Date?
    var riskSourceNote: String?
    var dns: [IPExit]
    var dnsMessage: String
    var udp: [String]
    var udpMessage: String
    var device: [String: String]
    var browserError: String?
    var regionMessage: String?
    var regionAssessment: ClaudeRegionAssessment?
    var serviceStatus: String?
    var serviceError: String?
    var rules: IPReferenceRules?
    var serviceDetails: IPServiceResponse?
    var udpExits: [IPExit]?
    var connectivity: [IPExit]?
    var apiRecheck: IPExit?
    var connectivityDate: Date?
    var ipsum: IPsumObservation?
    var checkMyIP: CheckMyIPObservation?
    var checkMyIPBrowser: CheckMyIPBrowserObservation?
    var usageRadar: IPUsageRadar?
}

struct IPAssessmentHTTP {
    let session: URLSession
    let runID: String

    func data(_ address: String, maximumBytes: Int = 2_000_000) async throws -> Data {
        guard var components = URLComponents(string: address) else { throw URLError(.badURL) }
        // The source API rejects extra query parameters on path-based endpoints.
        if !(components.host == "ip.net.coffee" && components.path.hasPrefix("/api/")) {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "_netglass", value: runID)]
        }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 12)
        request.setValue(runID, forHTTPHeaderField: "X-NetGlass-Request-ID")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            throw NSError(domain: "IPAssessment", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        guard data.count <= maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
        return data
    }

    func json<T: Decodable>(_ type: T.Type, _ url: String) async throws -> T {
        try JSONDecoder().decode(type, from: await data(url))
    }

    static func validIP(_ value: String) -> Bool {
        var address = in6_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) == 1 || inet_pton(AF_INET6, $0, &address) == 1 }
    }

    static func traceValues(_ text: String) -> [String: String] {
        Dictionary(text.split(separator: "\n").compactMap { line -> (String, String)? in
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            return (pair[0], pair[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }, uniquingKeysWith: { _, last in last })
    }

    static func contains(_ cidr: String, ip: String) -> Bool {
        let parts = cidr.split(separator: "/").map(String.init)
        guard parts.count == 2, let prefix = Int(parts[1]) else { return false }
        let family = ip.contains(":") ? AF_INET6 : AF_INET
        let count = family == AF_INET6 ? 16 : 4
        guard prefix >= 0, prefix <= count * 8 else { return false }
        var network = [UInt8](repeating: 0, count: 16)
        var address = [UInt8](repeating: 0, count: 16)
        guard inet_pton(family, parts[0], &network) == 1, inet_pton(family, ip, &address) == 1 else { return false }
        for index in 0..<count {
            let bits = min(8, max(0, prefix - index * 8))
            let mask = bits == 0 ? UInt8(0) : UInt8(255 << (8 - bits) & 255)
            if network[index] & mask != address[index] & mask { return false }
        }
        return true
    }

    static func regionPolicy(_ html: String, countryCode: String?, now: Date) -> String {
        ClaudeRegionAssessment.parse(html, countryCode: countryCode, now: now).message
    }

    func trace(name: String, url: String) async -> IPExit {
        let began = Date()
        do {
            let values = Self.traceValues(String(decoding: try await data(url), as: UTF8.self))
            if name == "Claude API", values["h"]?.lowercased() != "api.anthropic.com" { throw URLError(.cannotParseResponse) }
            guard let ip = values["ip"], Self.validIP(ip) else { throw URLError(.cannotParseResponse) }
            return IPExit(name: name, ip: ip, country: values["loc"], milliseconds: Date().timeIntervalSince(began) * 1000)
        } catch { return IPExit(name: name, error: error.localizedDescription) }
    }

    static let slowAPIThresholdMS: Double = 2000

    func apiTrace() async -> (first: IPExit, repeatSample: IPExit?) {
        let url = "https://api.anthropic.com/cdn-cgi/trace"
        let first = await trace(name: "Claude API", url: url)
        guard let duration = first.milliseconds, duration >= Self.slowAPIThresholdMS, !Task.isCancelled else {
            return (first, nil)
        }
        return (first, await trace(name: "Claude API", url: url))
    }

    func domestic() async -> IPExit {
        for url in ["https://2026.ip138.com/", "https://my.ip.cn/"] {
            do {
                let text = String(decoding: try await data(url), as: UTF8.self)
                let regex = try NSRegularExpression(pattern: #"(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])"#)
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(match.range, in: text) else { continue }
                    let ip = String(text[range])
                    if Self.validIP(ip) { return IPExit(name: "国内查询服务", ip: ip, source: URL(string: url)?.host) }
                }
            } catch { continue }
        }
        return IPExit(name: "国内查询服务", error: "IP138 与 IP.cn 均未返回可识别的地址")
    }

    func dnsExits(claudeCountry: String?) async -> ([IPExit], String) {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        // Each assessment uses a new authoritative DNS token, bypassing resolver caches.
        async let first: Data? = try? data("https://\(token)-1.d.ip.net.coffee/pixel.gif")
        async let second: Data? = try? data("https://\(token)-2.d.ip.net.coffee/pixel.gif")
        _ = await (first, second)
        struct DNSResponse: Decodable { var dns_servers: [String] }
        var addresses: [String] = []
        var failure: String?
        for _ in 0..<3 {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let response = try await json(DNSResponse.self, "https://ip.net.coffee/api/dns/result/\(token)")
                addresses = Array(Set(response.dns_servers.filter(Self.validIP))).sorted()
                if !addresses.isEmpty { break }
            } catch { failure = error.localizedDescription }
        }
        guard !addresses.isEmpty else { return ([], "未取得 DNS 出口，无法判断是否泄露\(failure.map { " · " + $0 } ?? "")") }
        let results = await geographies(addresses.map { IPExit(name: "DNS 解析器", ip: $0) })
        return (results, Self.dnsMessage(results, claudeCountry: claudeCountry))
    }
}

final class IPAssessment: ObservableObject {
    @Published var running = false
    @Published var connectivityRunning = false
    @Published var phase = ""
    @Published var result: IPAssessmentResult?
    @Published var history = (Store.load([IPAssessmentResult].self, "ip-assessments.json") ?? []).map { $0.audited() }
    private var task: Task<Void, Never>?
    private var connectivityTask: Task<Void, Never>?

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }

    @MainActor
    func evaluate() {
        guard !running, !connectivityRunning else { return }
        running = true
        result = nil
        phase = "正在重新获取出口与设备环境…"
        let browser = IPBrowserProbe()
        let checkMyIPBrowser = CheckMyIPBrowserProbe()
        task = Task {
            let session = Self.session()
            defer { session.invalidateAndCancel(); running = false; task = nil }
            let http = IPAssessmentHTTP(session: session, runID: UUID().uuidString)
            async let claudeTask = http.trace(name: "Claude", url: "https://claude.ai/cdn-cgi/trace")
            async let cloudflareTask = http.trace(name: "Cloudflare", url: "https://1.1.1.1/cdn-cgi/trace")
            async let domesticTask = http.domestic()
            async let apiTask = http.apiTrace()
            async let anthropicTask = http.trace(name: "Anthropic", url: "https://www.anthropic.com/cdn-cgi/trace")
            async let browserTask = browser.run()
            async let checkMyIPBrowserTask = checkMyIPBrowser.run()
            async let policyTask: Data? = try? http.data("https://www.anthropic.com/legal/supported-regions")
            async let ruleTask: Data? = try? http.data("https://ip.net.coffee/claude/claude-page.js")
            async let statusTask: IPServiceResponse? = try? http.json(IPServiceResponse.self, "https://status.claude.com/api/v2/summary.json")
            let (claude, cloudflare, domestic, anthropic) = await (claudeTask, cloudflareTask, domesticTask, anthropicTask)
            guard !Task.isCancelled else { return }
            let observedAt = Date()
            result = IPAssessmentResult(date: observedAt, exits: [claude, cloudflare, domestic, anthropic], dns: [], dnsMessage: "正在探测 DNS…", udp: [], udpMessage: "正在探测 WebRTC…", device: [:])
            phase = "正在获取出口归属、风险标记与 DNS…"
            async let checkMyIPTask = http.checkMyIP(ip: claude.ip)
            async let ipsumTask = http.ipSum(ip: claude.ip)
            async let exitGeo = http.geographies([claude, cloudflare, domestic, anthropic])
            async let dnsTask = http.dnsExits(claudeCountry: claude.country)
            var risk: IPRiskDetails?
            var riskError: String?
            var checkedAt: Date?
            var riskSourceNote: String?
            if let ip = claude.ip {
                do {
                    risk = try await http.json(IPRiskDetails.self, "https://ip.net.coffee/api/ip/lookup/\(ip)")
                    if let record = risk {
                        let scoped = try record.scoped(to: ip)
                        risk = scoped.0
                        riskSourceNote = scoped.1
                    }
                    guard risk?.hasInformation == true else {
                        risk = nil
                        throw URLError(.cannotParseResponse)
                    }
                    checkedAt = Date()
                } catch { riskError = error.localizedDescription }
            } else { riskError = "未取得 Claude 出口 IP" }
            let usageASN = risk?.asn
            async let usageRadar = http.usageRadar(asn: usageASN)
            let exits = await exitGeo
            if let geo = exits.first?.geo {
                var combined = risk ?? IPRiskDetails()
                combined.country = combined.country ?? geo.country
                combined.countryCode = combined.countryCode ?? geo.country_code
                combined.region = combined.region ?? geo.region
                combined.city = combined.city ?? geo.city
                combined.asOrganization = combined.asOrganization ?? geo.isp
                risk = combined
            }
            let probe = await browserTask
            let udpAddresses = probe.addresses.filter(IPAssessmentHTTP.publicIP)
            async let udpGeo = http.geographies(udpAddresses.map { IPExit(name: "UDP", ip: $0) })
            let rules = await ruleTask.flatMap { IPReferenceRules.parse(String(decoding: $0, as: UTF8.self)) }
            let policy = await policyTask
            let regionAssessment = policy.map { ClaudeRegionAssessment.parse(String(decoding: $0, as: UTF8.self), countryCode: risk?.countryCode ?? claude.country, now: Date()) }
            var device = probe.device
            device["系统版本"] = ProcessInfo.processInfo.operatingSystemVersionString
            let service = await statusTask
            result?.exits = exits
            result?.risk = risk
            result?.riskError = riskError
            result?.riskCheckedAt = checkedAt
            result?.riskSourceNote = riskSourceNote
            result?.rules = rules
            result?.regionAssessment = regionAssessment
            result?.regionMessage = regionAssessment?.message ?? "官方地区列表获取失败，支持情况未知"
            result?.device = device
            result?.browserError = probe.error
            result?.udp = udpAddresses
            result?.udpMessage = IPAssessmentHTTP.udpMessage(udpAddresses, claudeIP: claude.ip, error: probe.error)
            result?.serviceStatus = service?.status.description
            result?.serviceError = service == nil ? "服务状态获取失败" : nil
            result?.serviceDetails = service
            let api = await apiTask
            result?.connectivity = [claude, api.first, anthropic]
            result?.apiRecheck = api.repeatSample
            result?.connectivityDate = observedAt
            phase = "正在完成 DNS、UDP 与 IPsum 名单匹配…"
            let (dns, dnsMessage) = await dnsTask
            let udpExits = await udpGeo
            let ipsum = await ipsumTask
            let checkMyIP = await checkMyIPTask
            result?.checkMyIP = checkMyIP
            phase = "正在读取 CheckMyIP 现场信誉与网络身份…"
            let checkMyIPBrowserResult = await checkMyIPBrowserTask
            guard !Task.isCancelled else { return }
            result?.dns = dns
            result?.dnsMessage = dnsMessage
            result?.udpExits = udpExits
            result?.ipsum = ipsum
            result?.checkMyIP = checkMyIP
            result?.checkMyIPBrowser = checkMyIPBrowserResult
            if let country = result?.claudeCountry, let policy {
                let assessment = ClaudeRegionAssessment.parse(String(decoding: policy, as: UTF8.self), countryCode: country, now: Date())
                result?.regionAssessment = assessment
                result?.regionMessage = assessment.message
            }
            result?.usageRadar = await usageRadar
            result?.date = Date()
            if let report = result {
                history.insert(report, at: 0)
                history = Array(history.prefix(30))
                Store.save(history, "ip-assessments.json")
            }
            phase = "评估完成"
        }
    }

    @MainActor
    func refreshConnectivity() {
        guard !running, !connectivityRunning, let id = result?.id else { return }
        connectivityRunning = true
        connectivityTask = Task {
            let session = Self.session()
            defer { session.invalidateAndCancel(); connectivityRunning = false; connectivityTask = nil }
            let http = IPAssessmentHTTP(session: session, runID: UUID().uuidString)
            async let claude = http.trace(name: "Claude", url: "https://claude.ai/cdn-cgi/trace")
            async let apiTask = http.apiTrace()
            async let anthropic = http.trace(name: "Anthropic", url: "https://www.anthropic.com/cdn-cgi/trace")
            async let service: IPServiceResponse? = try? http.json(IPServiceResponse.self, "https://status.claude.com/api/v2/summary.json")
            let (first, api, second, status) = await (claude, apiTask, anthropic, service)
            guard !Task.isCancelled, result?.id == id else { return }
            result?.connectivity = [first, api.first, second]
            result?.apiRecheck = api.repeatSample
            result?.connectivityDate = Date()
            result?.serviceDetails = status
            result?.serviceStatus = status?.status.description
            result?.serviceError = status == nil ? "服务状态获取失败" : nil
            if let index = history.firstIndex(where: { $0.id == id }), let result {
                history[index] = result
                Store.save(history, "ip-assessments.json")
            }
        }
    }

    var exitHistory: [IPAssessmentResult] {
        var output: [IPAssessmentResult] = []
        for item in history {
            guard let ip = item.exits.first(where: { $0.name == "Claude" })?.ip else { continue }
            if let last = output.last, last.exits.first(where: { $0.name == "Claude" })?.ip == ip, last.date.timeIntervalSince(item.date) < 86400 { continue }
            output.append(item)
            if output.count == 6 { break }
        }
        return output
    }

    func reset() {
        task?.cancel()
        connectivityTask?.cancel()
        result = nil
        clearHistory()
    }

    func clearHistory() {
        history.removeAll()
        Store.remove("ip-assessments.json")
    }
}
