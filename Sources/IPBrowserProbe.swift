import Foundation
import WebKit

struct IPBrowserResult {
    var addresses: [String] = []
    var device: [String: String] = [:]
    var error: String?
}

@MainActor
final class IPBrowserProbe: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<IPBrowserResult, Never>?
    private var timeout: Task<Void, Never>?

    func run() async -> IPBrowserResult {
        guard let url = Bundle.main.url(forResource: "IPProbe", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            return IPBrowserResult(error: "设备探测资源缺失")
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.add(self, name: "assessment")
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
            view.navigationDelegate = self
            webView = view
            view.loadHTMLString(html, baseURL: URL(string: "https://localhost/"))
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finish(IPBrowserResult(error: "WebKit 探测超时"))
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { finish(IPBrowserResult(error: "设备探测返回格式异常")); return }
        let addresses = (body["addresses"] as? [String] ?? []).filter { IPAssessmentHTTP.validIP($0) }
        finish(IPBrowserResult(addresses: Array(Set(addresses)).sorted(), device: body["device"] as? [String: String] ?? [:], error: body["error"] as? String))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(IPBrowserResult(error: error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(IPBrowserResult(error: error.localizedDescription))
    }

    private func finish(_ result: IPBrowserResult) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "assessment")
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(returning: result)
    }
}
