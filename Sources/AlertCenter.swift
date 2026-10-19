import Foundation
import UserNotifications

final class AlertCenter: ObservableObject {
    @Published var alerts: [AppAlert] = []
    @Published var unread = 0

    private static let maxCount = 500

    init() {
        if let saved = Store.load([AppAlert].self, "alerts.json") {
            alerts = saved.sorted { $0.date > $1.date }
        }
        unread = Store.load(Int.self, "alerts-unread.json") ?? 0
    }

    func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func add(_ type: AlertType, title: String, detail: String) {
        let alert = AppAlert(type: type, title: title, detail: detail, date: Date())
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.alerts.insert(alert, at: 0)
            if self.alerts.count > Self.maxCount {
                self.alerts.removeLast(self.alerts.count - Self.maxCount)
            }
            self.unread += 1
            Store.save(self.alerts, "alerts.json")
            Store.save(self.unread, "alerts-unread.json")
            self.postNotification(alert)
        }
    }

    private func postNotification(_ alert: AppAlert) {
        let content = UNMutableNotificationContent()
        content.title = "NetGlass · \(alert.type.rawValue)"
        content.body = alert.detail
        let req = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func markAllRead() {
        DispatchQueue.main.async { [weak self] in
            self?.unread = 0
            Store.save(0, "alerts-unread.json")
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.alerts.removeAll()
            self?.unread = 0
            Store.save(self?.alerts ?? [], "alerts.json")
            Store.save(0, "alerts-unread.json")
        }
    }
}
