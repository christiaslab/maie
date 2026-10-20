import Foundation

/// The notification-center surface the notifier needs. The app backs it with
/// UNUserNotificationCenter; offline checks use a recorder, because a process
/// without an app bundle (model-checks) must never touch the real center.
@MainActor protocol QuestionNotificationCenter: AnyObject {
    func requestBannerAuthorization()
    func post(identifier: String, title: String, body: String)
    func remove(identifiers: [String])
}

/// Posts one macOS notification per new live question set and withdraws it when
/// the set stops being pending (sent, cancelled, expired, quit). Restored sets are
/// never pending, so they never notify. Bodies carry only the session label and a
/// count; question text is untrusted data and may be sensitive on a lock screen.
@MainActor final class QuestionNotifier {
    static let title = "Maie"
    private let center: QuestionNotificationCenter
    private(set) var notified = Set<UUID>()

    init(center: QuestionNotificationCenter) { self.center = center }

    static func body(for notice: QuestionNotice) -> String {
        "\(notice.title): \(notice.count) question\(notice.count == 1 ? "" : "s") waiting"
    }

    func requestAuthorization() { center.requestBannerAuthorization() }

    /// Reconciles against the current pending list. A set appearing for the first
    /// time is recorded exactly once; it is posted unless Maie is already showing
    /// (`windowVisible`), in which case the in-app notice suffices and the set
    /// still never fires later. A set that disappears is removed and forgotten.
    func reconcile(_ pending: [QuestionNotice], windowVisible: Bool) {
        let current = Set(pending.map(\.id))
        let gone = notified.subtracting(current)
        if !gone.isEmpty {
            center.remove(identifiers: gone.map(\.uuidString).sorted())
            notified.subtract(gone)
        }
        for notice in pending where notified.insert(notice.id).inserted && !windowVisible {
            center.post(identifier: notice.id.uuidString, title: Self.title, body: Self.body(for: notice))
        }
    }
}
