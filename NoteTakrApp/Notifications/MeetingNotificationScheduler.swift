import UserNotifications
import NoteTakrCore

// Schedules UNUserNotification banners before detected calendar meetings.
// Registers a "Start Recording" action so users can begin a recording
// directly from the notification banner.
// Verified only on the macOS CI runner / physical Mac.
final class MeetingNotificationScheduler: NSObject {
    static let categoryID = "MEETING_REMINDER"
    static let startRecordingActionID = "START_RECORDING"

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        registerCategory()
    }

    func registerCategory() {
        let startAction = UNNotificationAction(
            identifier: Self.startRecordingActionID,
            title: "Start Recording",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [startAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // Schedules a reminder `minutesBefore` minutes before the event starts.
    // Silently skips if the computed fire date is already in the past.
    func scheduleReminder(for event: CalendarEvent, minutesBefore: Int = 5) {
        let fireDate = event.startDate.addingTimeInterval(-Double(minutesBefore) * 60)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Meeting starting in \(minutesBefore) minutes"
        content.body = event.title
        content.sound = .default
        content.categoryIdentifier = Self.categoryID

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = "meeting-\(event.startDate.timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}

extension MeetingNotificationScheduler: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == Self.startRecordingActionID {
            NotificationCenter.default.post(
                name: .meetingNotificationStartRecording,
                object: nil
            )
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let meetingNotificationStartRecording =
        Notification.Name("MeetingNotificationStartRecording")
}
