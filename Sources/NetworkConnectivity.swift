import Foundation
import Combine

struct ConnectivityTarget: Codable, Identifiable {
    var group: String
    var name: String
    var endpoint: String
    var icon: String?
    var id: String { group + "|" + name }
    var host: String { URL(string: endpoint)?.host ?? endpoint }
}

struct ConnectivitySample {
    var milliseconds: Double?
    var statusCode: Int?
    var error: String?
}

struct ConnectivityCatalog {
    static let groups = [("cn", "中国"), ("jp", "日本"), ("us", "美国"), ("gl", "全球")]
    static let source = "https://ip.net.coffee/link/link-page.js"

    static func parse(_ source: String) -> [ConnectivityTarget]? {
        guard let start = source.range(of: "const TARGETS = ["), let end = source[start.upperBound...].range(of: "];") else { return nil }
        let body = String(source[start.upperBound..<end.lowerBound])
        guard let rows = try? NSRegularExpression(pattern: #"\{([^{}]+)\}"#),
              let fields = try? NSRegularExpression(pattern: #"(cc|name|host|url):\s*'([^']*)'"#) else { return nil }
        let bundledIcons = Dictionary(uniqueKeysWithValues: bundled().map { ($0.id, $0.icon) })
        var targets: [ConnectivityTarget] = []
        var identifiers = Set<String>()
        for match in rows.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let range = Range(match.range(at: 1), in: body) else { return nil }
            let row = String(body[range])
            var values: [String: String] = [:]
            for field in fields.matches(in: row, range: NSRange(row.startIndex..., in: row)) {
                if let key = Range(field.range(at: 1), in: row), let value = Range(field.range(at: 2), in: row) { values[String(row[key])] = String(row[value]) }
            }
            guard let group = values["cc"], groups.contains(where: { $0.0 == group }), let name = values["name"], !name.isEmpty else { return nil }
            let endpoint = values["url"] ?? values["host"].map { "https://" + $0 + "/favicon.ico" }
            guard let endpoint, let url = URL(string: endpoint), url.scheme == "https", url.user == nil, url.password == nil,
                  let host = url.host, host != "localhost", !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
                  !IPAssessmentHTTP.validIP(host) || IPAssessmentHTTP.publicIP(host) else { return nil }
            var target = ConnectivityTarget(group: group, name: name, endpoint: endpoint)
            target.icon = bundledIcons[target.id] ?? nil
            guard identifiers.insert(target.id).inserted else { return nil }
            targets.append(target)
        }
        return targets.isEmpty ? nil : targets
    }

    static func bundled() -> [ConnectivityTarget] {
        guard let url = Bundle.main.url(forResource: "LinkTargets", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ConnectivityTarget].self, from: data)) ?? []
    }
}

final class NetworkConnectivity: ObservableObject {
    static let rounds = 3
    @Published var targets = ConnectivityCatalog.bundled()
    @Published var samples: [String: [ConnectivitySample]] = [:]
    @Published var running = false
    @Published var activeGroup: String?
    @Published var checkedAt: Date?
    @Published var duration: TimeInterval?
    @Published var catalogMessage = "内置站点列表 · 全部测试时检查最新列表"
    private var task: Task<Void, Never>?
    private var session: URLSession?

    static func median(_ samples: [ConnectivitySample]) -> Double? {
        let values = samples.compactMap(\.milliseconds).sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }

    static func probe(_ target: ConnectivityTarget, session: URLSession, token: String) async -> ConnectivitySample {
        guard var components = URLComponents(string: target.endpoint) else { return ConnectivitySample(error: "目标地址无效") }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "_netglass", value: token)]
        guard let url = components.url else { return ConnectivitySample(error: "目标地址无效") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 2.5)
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.httpShouldHandleCookies = false
        let began = ProcessInfo.processInfo.systemUptime
        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return ConnectivitySample(error: "响应格式异常") }
            return ConnectivitySample(milliseconds: (ProcessInfo.processInfo.systemUptime - began) * 1000, statusCode: response.statusCode)
        } catch { return ConnectivitySample(error: error.localizedDescription) }
    }

    @MainActor
    func start(group: String? = nil) {
        guard !running else { return }
        running = true
        activeGroup = group
        duration = nil
        let began = ProcessInfo.processInfo.systemUptime
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(configuration: configuration)
        self.session = session
        task = Task {
            defer { session.invalidateAndCancel(); self.session = nil; duration = ProcessInfo.processInfo.systemUptime - began; running = false; activeGroup = nil; task = nil }
            if group == nil {
                do {
                    let http = IPAssessmentHTTP(session: session, runID: UUID().uuidString)
                    let data = try await http.data(ConnectivityCatalog.source)
                    guard let latest = ConnectivityCatalog.parse(String(decoding: data, as: UTF8.self)) else { throw URLError(.cannotParseResponse) }
                    targets = latest
                    catalogMessage = "站点列表更新于 " + Date().formatted(date: .omitted, time: .standard)
                } catch { catalogMessage = "列表更新失败，使用当前列表 · " + error.localizedDescription }
            }
            guard !Task.isCancelled else { return }
            let selected = targets.filter { group == nil || $0.group == group }
            if group == nil { samples.removeAll() }
            for target in selected { samples[target.id] = [] }
            checkedAt = Date()
            await withTaskGroup(of: Void.self) { pool in
                let initial = min(9, selected.count)
                for index in 0..<initial { pool.addTask { await self.test(selected[index], session: session) } }
                var next = initial
                for await _ in pool {
                    if next < selected.count, !Task.isCancelled {
                        let target = selected[next]
                        next += 1
                        pool.addTask { await self.test(target, session: session) }
                    }
                }
            }
        }
    }

    @MainActor
    private func test(_ target: ConnectivityTarget, session: URLSession) async {
        for _ in 0..<Self.rounds {
            guard !Task.isCancelled else { return }
            let sample = await Self.probe(target, session: session, token: UUID().uuidString)
            guard !Task.isCancelled else { return }
            samples[target.id, default: []].append(sample)
        }
    }

    @MainActor
    func stop() {
        task?.cancel()
        session?.invalidateAndCancel()
    }
}
