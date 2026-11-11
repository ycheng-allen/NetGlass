import AppKit
import NetworkExtension
import SystemExtensions

final class OutboundFirewall: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    static let extensionID = "com.allen.netglass.filter"
    static let groupID = "group.com.allen.netglass"
    @Published var rules = Store.load([OutboundRule].self, "outbound-rules.json") ?? []
    @Published var status = "出站过滤尚未启用"
    @Published var enabled = false
    private var sharedURL: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID)?.appendingPathComponent("rules.json") }

    override init() {
        super.init()
        NEFilterManager.shared().loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                let manager = NEFilterManager.shared()
                self.enabled = error == nil && manager.isEnabled && manager.providerConfiguration?.filterDataProviderBundleIdentifier == Self.extensionID
                if self.enabled { self.status = "出站过滤配置已启用" }
            }
        }
    }

    func disable() {
        NEFilterManager.shared().loadFromPreferences { error in
            DispatchQueue.main.async {
                if let error { self.status = error.localizedDescription; return }
                let manager = NEFilterManager.shared()
                guard manager.providerConfiguration?.filterDataProviderBundleIdentifier == Self.extensionID else {
                    self.enabled = false
                    self.status = "NetGlass 出站过滤尚未启用"
                    return
                }
                manager.isEnabled = false
                manager.saveToPreferences { error in
                    DispatchQueue.main.async {
                        if let error { self.status = error.localizedDescription }
                        else { self.enabled = false; self.status = "出站过滤已关闭" }
                    }
                }
            }
        }
    }

    var bundled: Bool {
        FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions/\(Self.extensionID).systemextension").path)
    }

    func save() {
        Store.save(rules, "outbound-rules.json")
        guard let url = sharedURL else { status = "规则已保存，待签名扩展启用后生效"; return }
        do { try JSONEncoder().encode(rules).write(to: url, options: .atomic) }
        catch { status = "写入过滤规则失败 · \(error.localizedDescription)" }
    }

    func activate() {
        guard bundled else { status = "当前构建缺少已签名的出站过滤扩展"; return }
        save()
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.extensionID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) { status = "请在系统设置中允许 NetGlass 系统扩展" }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) { status = error.localizedDescription }
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        guard result == .completed else { status = "系统扩展将在重新启动后启用"; return }
        NEFilterManager.shared().loadFromPreferences { error in
            DispatchQueue.main.async {
                if let error { self.status = error.localizedDescription; return }
                let manager = NEFilterManager.shared()
                let config = NEFilterProviderConfiguration()
                config.filterSockets = true
                config.filterDataProviderBundleIdentifier = Self.extensionID
                manager.providerConfiguration = config
                manager.localizedDescription = "NetGlass 应用出站规则"
                manager.isEnabled = true
                manager.saveToPreferences { error in
                    DispatchQueue.main.async {
                        self.enabled = error == nil
                        self.status = error?.localizedDescription ?? "出站过滤已启用"
                    }
                }
            }
        }
    }
}
