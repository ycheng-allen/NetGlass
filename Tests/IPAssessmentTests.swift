import Foundation

// Keep model tests independent of the user's history and WebKit process.
enum Store {
    static func load<T: Decodable>(_ type: T.Type, _ file: String) -> T? { nil }
    static func save<T: Encodable>(_ value: T, _ file: String) {}
    static func remove(_ file: String) {}
}
struct IPBrowserResult {
    var addresses: [String] = []
    var device: [String: String] = [:]
    var error: String?
}
@MainActor final class IPBrowserProbe {
    func run() async -> IPBrowserResult { IPBrowserResult() }
}
final class AssessmentProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    static var statusCode = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: ["Cache-Control": "max-age=3600"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        client?.urlProtocol(self, didLoad: Data("ip=2001:db8::1\nloc=US\n".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

assert(IPAssessmentHTTP.validIP("2001:db8::1"))
assert(IPAssessmentHTTP.validIP("192.0.2.1"))
assert(!IPAssessmentHTTP.validIP("999.0.0.1"))
assert(!IPAssessmentHTTP.validIP("<html>"))
assert(IPAssessmentHTTP.traceValues("bad\nip=192.0.2.1\nip=192.0.2.2")["ip"] == "192.0.2.2")
assert(IPAssessmentHTTP.contains("192.0.2.0/24", ip: "192.0.2.9"))
assert(!IPAssessmentHTTP.contains("192.0.2.0/24", ip: "192.0.3.1"))
assert(IPAssessmentHTTP.contains("2001:db8::/32", ip: "2001:db8:1::4"))
assert(!IPAssessmentHTTP.contains("2001:db8::/129", ip: "2001:db8::1"))
let fixture = Data(#"{"ip":"192.0.2.1","asn":64500,"trust_score":99,"is_vpn":false}"#.utf8)
let risk = try JSONDecoder().decode(IPRiskDetails.self, from: fixture)
assert(risk.is_vpn == false && risk.is_tor == nil)
let encodedRisk = try JSONEncoder().encode(risk)
assert(!String(decoding: encodedRisk, as: UTF8.self).contains("trust_score"))
let policy = "Countries and regions where we currently offer access<ul><li>United States of America</li></ul>"
assert(IPAssessmentHTTP.regionPolicy(policy, countryCode: "US", now: Date()).contains("出现在"))
assert(IPAssessmentHTTP.regionPolicy("changed", countryCode: "US", now: Date()).contains("无法判定"))
let future = "<time dateTime=\"2099-11-12T20:20:00.000Z\">future</time>" + policy
assert(IPAssessmentHTTP.regionPolicy(future, countryCode: "US", now: Date()).contains("尚未生效"))
let variedFixture = Data(#"{"asn":"AS64501","is_vpn":"true","is_proxy":0,"is_tor":null,"is_mobile":1,"company":{"name":"Example ISP","type":"isp"},"intelligence":{"threats":[{"label":"Historical abuse","severity":"warn"}]},"security":{"is_crawler":true},"trust_score":77}"#.utf8)
let dataCenterOnly = try JSONDecoder().decode(IPRiskDetails.self, from: Data(#"{"is_datacenter":true}"#.utf8))
assert(dataCenterOnly.hasInformation && dataCenterOnly.is_datacenter == true)
assert(!IPAssessmentHTTP.publicIP("::ffff:192.168.1.2"))
let varied = try JSONDecoder().decode(IPRiskDetails.self, from: variedFixture)
assert(varied.asn == 64501 && varied.is_vpn == true && varied.is_proxy == false)
assert(varied.is_tor == nil && varied.is_crawler == true && varied.signals?["is_mobile"] == true)
assert(varied.company_name == "Example ISP" && varied.evidence?.first?.label == "Historical abuse")
let restoredRisk = try JSONDecoder().decode(IPRiskDetails.self, from: JSONEncoder().encode(varied))
assert(restoredRisk.evidence?.first?.label == "Historical abuse")
assert(restoredRisk.signals?["is_mobile"] == true)
assert(!IPAssessmentHTTP.publicIP("172.31.1.1"))
assert(IPAssessmentHTTP.publicIP("172.217.1.1"))
assert(!IPAssessmentHTTP.publicIP("198.18.0.1"))
assert(IPAssessmentHTTP.udpMessage(["8.8.8.8"], claudeIP: nil, error: nil).contains("无法比较"))
assert(IPAssessmentHTTP.dnsMessage([IPExit(name: "DNS", ip: "1.1.1.1", country: "CN")], claudeCountry: "US").contains("地区不同"))
assert(IPAssessmentHTTP.dnsMessage([IPExit(name: "DNS", ip: "1.1.1.1", country: "DE")], claudeCountry: "US").contains("不能证明泄露"))
let rulesText = "const CLAUDE_RESTRICTED_CC = {'CN': 'China'}; const CC_TO_TZ = {'US': 'America/Los_Angeles'}; const langMap = {'US': ['en', 'es']};"
let rules = IPReferenceRules.parse(rulesText)!
assert(rules.restricted["CN"] == "China" && rules.languages["US"] == ["en", "es"])
assert(IPReferenceRules.parse("changed") == nil)
let model = IPAssessment()
func snapshot(_ date: Date, ip: String) -> IPAssessmentResult {
    IPAssessmentResult(date: date, exits: [IPExit(name: "Claude", ip: ip)], dns: [], dnsMessage: "", udp: [], udpMessage: "", device: ["时区": "America/Los_Angeles", "语言": "en-US"], rules: rules)
}
let now = Date()
model.history = [snapshot(now, ip: "8.8.8.8"), snapshot(now.addingTimeInterval(-100), ip: "8.8.8.8"), snapshot(now.addingTimeInterval(-200), ip: "1.1.1.1")]
assert(model.exitHistory.count == 2)
assert(model.history.first!.timezoneComparison.contains("相近") == false, "missing country preserves unknown timezone")
var sample = model.history.first!
sample.risk = IPRiskDetails(countryCode: "US")
assert(sample.timezoneComparison.contains("相近") && sample.languageComparison.contains("匹配"))
let encodedSample = try JSONEncoder().encode(sample)
let restoredSample = try JSONDecoder().decode(IPAssessmentResult.self, from: encodedSample)
assert(restoredSample.rules?.languages["US"] == ["en", "es"])
assert(IPNetworkType.classify(IPRiskDetails(is_datacenter: true, company_type: "hosting")).kind == .hosting)
assert(IPNetworkType.classify(IPRiskDetails(isResidential: true, is_datacenter: false, company_type: "isp")).kind == .residential)
assert(IPNetworkType.classify(IPRiskDetails(isResidential: true, is_datacenter: true)).kind == .conflict)
assert(IPNetworkType.classify(IPRiskDetails(is_datacenter: false)).kind == .unknown)
assert(IPNetworkType.classify(IPRiskDetails(company_type: "isp")).kind == .isp)
assert(IPNetworkType.classify(IPRiskDetails(signals: ["is_mobile": true])).kind == .mobile)
let feedText = "# IPsum Threat Intelligence Feed\n# Last update: test snapshot\n45.148.10.151\t10\n2001:4860::1\t2\n"
let feed = try IPsumFeed.parse(Data(feedText.utf8))
assert(feed.observation(ip: "45.148.10.151").occurrences == 10)
assert(feed.observation(ip: "45.148.10.152").occurrences == 0)
assert(feed.observation(ip: "2001:4860:0:0:0:0:0:1").occurrences == 2)
assert(feed.observation(ip: nil).occurrences == nil)
assert((try? IPsumFeed.parse(Data("<html>error</html>".utf8))) == nil)
let onlyIPv4 = try IPsumFeed.parse(Data("# IPsum\n# Last update: snapshot\n8.8.8.8 1\n".utf8))
assert(onlyIPv4.observation(ip: "2001:4860::1").occurrences == nil)
let observationData = try JSONEncoder().encode(feed.observation(ip: "45.148.10.151"))
let restoredObservation = try JSONDecoder().decode(IPsumObservation.self, from: observationData)
assert(restoredObservation.occurrences == 10 && restoredObservation.sourceUpdated == "test snapshot")
let catalogText = "const TARGETS = [{cc:'cn', name:'示例', host:'example.com'}, {cc:'us', name:'CF', url:'https://1.1.1.1/cdn-cgi/trace'}];"
let catalog = ConnectivityCatalog.parse(catalogText)!
assert(catalog.count == 2 && catalog[0].endpoint == "https://example.com/favicon.ico")
assert(ConnectivityCatalog.parse("const TARGETS = [{cc:'us',name:'Local',url:'http://127.0.0.1/'}];") == nil)
assert(ConnectivityCatalog.parse("changed") == nil)
let bundledTargets = try JSONDecoder().decode([ConnectivityTarget].self, from: Data(contentsOf: URL(fileURLWithPath: "Resources/LinkTargets.json")))
assert(bundledTargets.count >= 40 && Set(bundledTargets.map(\.id)).count == bundledTargets.count)
assert(ConnectivityCatalog.groups.allSatisfy { group in bundledTargets.contains { $0.group == group.0 } })
assert(NetworkConnectivity.median([ConnectivitySample(milliseconds: 400), ConnectivitySample(error: "timeout"), ConnectivitySample(milliseconds: 100), ConnectivitySample(milliseconds: 200)]) == 200)
assert(NetworkConnectivity.median([ConnectivitySample(error: "timeout")]) == nil)
let representative = IPRiskDetails(ip: "192.0.2.80", cidr: "192.0.2.0/24", asn: 64500, is_datacenter: true, is_vpn: true, is_proxy: false, is_abuser: true, reverseDNS: "other.example")
let scopedRisk = try representative.scoped(to: "192.0.2.1")
assert(scopedRisk.0.asn == 64500 && scopedRisk.0.is_datacenter == true && scopedRisk.1 != nil)
assert(scopedRisk.0.is_vpn == nil && scopedRisk.0.is_proxy == nil && scopedRisk.0.is_abuser == nil && scopedRisk.0.reverseDNS == nil)
assert((try? representative.scoped(to: "192.0.3.1")) == nil)
let exactRisk = try representative.scoped(to: "192.0.2.80")
assert(exactRisk.0.is_vpn == true)
var historical = snapshot(now, ip: "192.0.2.1")
historical.risk = representative
historical.dns = [IPExit(name: "DNS", ip: "1.1.1.1", country: "CN")]
historical.risk?.countryCode = "US"
historical.dnsMessage = "可能存在 DNS 泄露"
let audited = historical.audited()
assert(audited.risk?.is_vpn == nil && audited.riskSourceNote != nil)
assert(audited.dnsMessage.contains("地区不同") && !audited.dnsMessage.contains("泄露"))
let checkFixture = Data(#"""
{"ip":"192.0.2.1","mode":"full","cache":"edge ≤10 min","generated_at":"2026-11-11T09:00:00Z",
 "network":{"asn":64500,"registry_country":"LU","multi_origin":false},
 "type":{"type":"datacenter","source":"heuristic:as-name","confidence":"medium","reasons":["AS name"]},
 "geo":{"consensus":{"country":"US","city":"Example","source_count":2,"agreement_count":2},"sources":[{"id":"registry","kind":"registry","country":"LU"}]},
 "risk":{"score":100,"level":"severe","is_proxy":true,"is_relay":false,"blacklists":[
 {"list":"direct","listed":true,"informational":false,"checked_at":"now"},
 {"list":"asn","listed":true,"informational":true,"checked_at":"now"},
 {"list":"failed","listed":false,"informational":false,"error":"timeout"},
 {"list":"unknown","informational":false}],"factors":[{"id":"proxy","points":35,"source":"fixture"}]}}
"""#.utf8)
let check = try CheckMyIPResponse.validated(checkFixture, requestedIP: "192.0.2.1")
assert((try? CheckMyIPResponse.validated(checkFixture, requestedIP: "192.0.2.2")) == nil)
assert(check.geo?.consensus?.countryVoteSummary == "2 / 2 个来源一致")
assert(check.directHits == 1 && check.checkedLists == 1, "ASN matches and failures cannot count as direct address hits")
assert(check.risk?.blacklists?.last?.status == "未完成／未知")
let noCheck = try CheckMyIPResponse.validated(Data(#"{"ip":"2001:db8::1","risk":{}}"#.utf8), requestedIP: "2001:db8:0:0::1")
let emptyGeo = try JSONDecoder().decode(CheckMyIPResponse.Consensus.self, from: Data("{}".utf8))
assert(emptyGeo.countryVoteSummary == "来源数量未知")
assert(noCheck.checkedLists == 0 && noCheck.risk?.is_vpn == nil)
assert((try? CheckMyIPResponse.validated(Data(#"{"ip":"192.0.2.1"}"#.utf8), requestedIP: "192.0.2.1")) == nil)
let encodedCheck = String(decoding: try JSONEncoder().encode(check), as: UTF8.self)
assert(encodedCheck.contains("score") && encodedCheck.contains("level") && encodedCheck.contains("points"))
assert(check.validRiskScore == 100 && check.networkIdentity.name == "代理出口")
assert(check.reputation.value == 30 && check.reputation.completed == 3)
assert(noCheck.reputation.value == nil)
sample.checkMyIP = CheckMyIPObservation(requestedIP: "192.0.2.1", checkedAt: now, response: check)
sample.risk = IPRiskDetails(countryCode: "DE", isResidential: true, is_proxy: false)
assert(sample.claudeCountry == "US" && sample.locationASN == 64500)
assert(sample.networkType.kind == .conflict)
assert(sample.combinedRisk("代理 Proxy") == true && sample.riskSourceSummary("代理 Proxy").contains("差异"))
assert(sample.combinedRisk("VPN") == nil)
sample.risk = nil
assert(sample.networkType.title.contains("推断"))
let restoredCheckSample = try JSONDecoder().decode(IPAssessmentResult.self, from: JSONEncoder().encode(sample))
assert(restoredCheckSample.checkedIP?.generated_at == "2026-11-11T09:00:00Z")
assert(restoredSample.checkMyIP == nil, "old history remains readable")
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [AssessmentProtocol.self]
let session = URLSession(configuration: config)
var complete = false
Task {
    for run in ["first", "second"] {
        let http = IPAssessmentHTTP(session: session, runID: run)
        let exit = await http.trace(name: "Claude", url: "https://example.test/trace")
        assert(exit.ip == "2001:db8::1")
    }
    _ = try! await IPAssessmentHTTP(session: session, runID: "api").data("https://ip.net.coffee/api/iprisk/192.0.2.1")
    assert(AssessmentProtocol.requests.count == 3)
    assert(AssessmentProtocol.requests.last!.url!.query == nil)
    assert(AssessmentProtocol.requests.last!.value(forHTTPHeaderField: "X-NetGlass-Request-ID") == "api")
    let tokens = AssessmentProtocol.requests.prefix(2).map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems!.first(where: { $0.name == "_netglass" })!.value! }
    assert(tokens == ["first", "second"])
    assert(AssessmentProtocol.requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData && $0.value(forHTTPHeaderField: "Cache-Control") == "no-cache, no-store" })
    AssessmentProtocol.statusCode = 403
    let response = await NetworkConnectivity.probe(ConnectivityTarget(group: "us", name: "fixture", endpoint: "https://example.test/favicon.ico"), session: session, token: "connectivity")
    assert(response.statusCode == 403 && response.milliseconds != nil, "HTTP errors still establish endpoint reachability")
    assert(AssessmentProtocol.requests.last!.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    complete = true
}
let deadline = Date().addingTimeInterval(10)
while !complete && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
assert(complete, "request tests timed out")
session.invalidateAndCancel()
print("PASS IP trace, IPv4/IPv6 ranges, unknown flags, score omission, policy version, fresh requests")

let mediumHosting = try CheckMyIPResponse.validated(Data(#"{"ip":"192.0.2.1","mode":"full","type":{"type":"datacenter","confidence":"medium","source":"heuristic:as-name"},"risk":{"score":0,"factors":[]}}"#.utf8), requestedIP: "192.0.2.1")
assert(mediumHosting.reputation.value == 89 && mediumHosting.reputation.completed == 2)
let missingConfidence = try CheckMyIPResponse.validated(Data(#"{"ip":"192.0.2.1","type":{"type":"datacenter"},"risk":{"score":999}}"#.utf8), requestedIP: "192.0.2.1")
assert(missingConfidence.validRiskScore == nil && missingConfidence.reputation.value == nil)
var riskSample = sample
riskSample.checkMyIP = CheckMyIPObservation(checkedAt: now, response: check)
assert(riskSample.claudeRiskClues.contains { $0.id == "lists" && $0.kind == .attention })

@MainActor final class CheckMyIPBrowserProbe {
    func run() async -> CheckMyIPBrowserObservation { .init(checkedAt: Date(), error: "test") }
}
let siteResult = CheckMyIPBrowserObservation(checkedAt: now, ip: "2001:db8::1", browserScore: 80, ipScore: 90, overallScore: 86)
assert(siteResult.matches("2001:db8:0:0::1") && !siteResult.matches("192.0.2.1"))
