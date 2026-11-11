import Foundation
import WebKit

@MainActor
final class CheckMyIPBrowserProbe: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var view: WKWebView?
    private var continuation: CheckedContinuation<CheckMyIPBrowserObservation, Never>?
    private var timeout: Task<Void, Never>?
    private var polling: Task<Void, Never>?

    func run() async -> CheckMyIPBrowserObservation {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                configuration.userContentController.add(self, name: "checkMyIPResult")
                // Offscreen pages do not receive display frames. Drive source UI scheduling
                // with timers so its own tests can finish without a visible browser window.
                configuration.userContentController.addUserScript(WKUserScript(source: Self.schedulingScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                configuration.userContentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
                let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1100, height: 900), configuration: configuration)
                self.view = view
                view.navigationDelegate = self
                var url = URLComponents(string: "https://checkmyip.com/zh-cn")!
                url.queryItems = [URLQueryItem(name: "_netglass", value: UUID().uuidString)]
                var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
                request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
                view.load(request)
                polling = Task { [weak self] in
                    var settledAt: Date?
                    for tick in 0..<45 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled, let self, self.continuation != nil else { return }
                        if let body = try? await self.view?.evaluateJavaScript(Self.snapshotScript) as? [String: Any] {
                            let complete = body["complete"] as? Bool == true
                            if complete && settledAt == nil { settledAt = Date() }
                            if (complete && Date().timeIntervalSince(settledAt ?? Date()) > 1.2) || tick >= 43 {
                                self.receive(body)
                                return
                            }
                        }
                    }
                    self?.finish(CheckMyIPBrowserObservation(checkedAt: Date(), error: "CheckMyIP 现场检查超时，请重新评估"))
                }
                timeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 45_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.finish(CheckMyIPBrowserObservation(checkedAt: Date(), error: "CheckMyIP 现场检查超时，请重新评估"))
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(CheckMyIPBrowserObservation(checkedAt: Date(), error: "现场检查已取消")) } }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.host == "checkmyip.com", let body = message.body as? [String: Any] else { return }
        receive(body)
    }

    private func receive(_ body: [String: Any]) {
        func score(_ key: String) -> Int? {
            guard let n = body[key] as? Int, (0...100).contains(n) else { return nil }
            return n
        }
        let checks = (body["checks"] as? [[String: String]] ?? []).compactMap { item -> CheckMyIPBrowserObservation.Check? in
            guard let id = item["id"], let state = item["state"], let text = item["text"] else { return nil }
            return .init(id: id, state: state, text: String(text.prefix(1200)))
        }
        let ip = (body["ip"] as? String).flatMap { IPAssessmentHTTP.validIP($0) ? $0 : nil }
        finish(CheckMyIPBrowserObservation(checkedAt: Date(), ip: ip, browserScore: score("browser"), ipScore: score("ipScore"), overallScore: score("overall"), identity: body["identity"] as? String, summary: body["summary"] as? String, checks: checks,
            error: body["complete"] as? Bool == true ? nil : "现场检查未全部完成；仅保留源站已生成的结果"))
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.init(checkedAt: Date(), error: error.localizedDescription)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.init(checkedAt: Date(), error: error.localizedDescription)) }
    private func finish(_ result: CheckMyIPBrowserObservation) {
        guard let continuation else { return }
        self.continuation = nil
        polling?.cancel()
        polling = nil
        timeout?.cancel()
        timeout = nil
        view?.configuration.userContentController.removeScriptMessageHandler(forName: "checkMyIPResult")
        view?.stopLoading()
        view?.navigationDelegate = nil
        view = nil
        continuation.resume(returning: result)
    }
    private static let schedulingScript = #"""
    window.requestAnimationFrame = callback => setTimeout(() => callback(performance.now()), 20);
    window.cancelAnimationFrame = token => clearTimeout(token);
    window.requestIdleCallback = callback => setTimeout(() => callback({didTimeout:false,timeRemaining:()=>20}), 100);
    window.cancelIdleCallback = token => clearTimeout(token);
    """#

    private static let snapshotScript = #"""
    (() => {
      const root = document.querySelector('#reputation');
      root?.scrollIntoView({block:'center'});
      const text = s => document.querySelector(s)?.textContent?.trim() || '';
      const score = (node, digits) => {
        if (document.querySelector(node)?.dataset.state !== 'done') return null;
        const s = text(digits); return /^\d{1,3}$/.test(s) ? Number(s) : null;
      };
      const complete = ['done','na'].includes(root?.dataset.state);
      return { complete, ip:document.querySelector('#home')?.dataset.ip || '',
        browser:score('#rep-browser','#rep-browser-num'), ipScore:score('#rep-ip','#rep-ip-num'),
        overall:complete && /^\d{1,3}$/.test(text('#rep-overall-digits')) ? Number(text('#rep-overall-digits')) : null,
        identity:text('#idstrip .idstrip__title') || text('#idstrip').replace(/^.*?(检测到)/,'$1'), summary:text('#rep-overall-line'),
        checks:Array.from(document.querySelectorAll('.replist [data-id]')).map(e => ({id:e.dataset.id,state:e.dataset.state||'unknown',text:e.innerText})),
        diagnostic:document.readyState + ' ' + document.title + ' ' + (root?.dataset.state || 'missing')
      };
    })()
    """#

    private static let script = #"""
    (() => {
      let sent = false, doneAt = 0;
      const started = Date.now();
      const text = s => document.querySelector(s)?.textContent?.trim() || '';
      const score = (node, digits) => {
        if (document.querySelector(node)?.dataset.state !== 'done') return null;
        const s = text(digits); return /^\d{1,3}$/.test(s) ? Number(s) : null;
      };
      const poll = setInterval(() => {
        const root = document.querySelector('#reputation');
        if (Date.now() - started < 5000) root?.scrollIntoView({block:'center'});
        const complete = ['done','na'].includes(root?.dataset.state);
        if (complete && !doneAt) doneAt = Date.now();
        if (sent || !(doneAt && Date.now()-doneAt > 1200) && Date.now()-started < 40000) return;
        sent = true; clearInterval(poll);
        const checks = Array.from(document.querySelectorAll('.replist [data-id]')).map(e => ({id:e.dataset.id, state:e.dataset.state||'unknown', text:e.innerText}));
        window.webkit.messageHandlers.checkMyIPResult.postMessage({
          complete, ip:document.querySelector('#home')?.dataset.ip || '',
          browser:score('#rep-browser','#rep-browser-num'), ipScore:score('#rep-ip','#rep-ip-num'),
          overall:complete && /^\d{1,3}$/.test(text('#rep-overall-digits')) ? Number(text('#rep-overall-digits')) : null,
          identity:text('#idstrip .idstrip__title') || text('#idstrip').replace(/^.*?(检测到)/,'$1'), summary:text('#rep-overall-line'), checks
        });
      }, 350);
    })();
    """#
}
