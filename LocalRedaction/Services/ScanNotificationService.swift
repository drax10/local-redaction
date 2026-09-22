import AppKit
import Foundation
import UserNotifications

@MainActor
final class ScanNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ScanNotificationService()

    var onOpenDocument: ((UUID) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var didRequestAccess = false

    func installDelegate() {
        center.delegate = self
    }

    func requestAccessIfNeeded() {
        guard !didRequestAccess else { return }
        didRequestAccess = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyScanFinished(
        id: UUID,
        fileName: String,
        findingCount: Int,
        userIsWatching: Bool
    ) {
        let appIsActive = NSApp.isActive
        if userIsWatching && appIsActive {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Análisis concluido"
        content.body = Self.body(fileName: fileName, findingCount: findingCount)
        content.sound = .default
        content.userInfo = ["documentID": id.uuidString]
        content.threadIdentifier = id.uuidString

        let request = UNNotificationRequest(
            identifier: "scan-finished-\(id.uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        guard let raw = response.notification.request.content.userInfo["documentID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        onOpenDocument?(id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func body(fileName: String, findingCount: Int) -> String {
        let findings = findingCount == 1 ? "1 hallazgo" : "\(findingCount) hallazgos"
        return "«\(fileName)» está listo. \(findings)."
    }
}
