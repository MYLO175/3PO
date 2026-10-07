import Foundation
import EventKit

extension DashboardModel {
    /// Pure local projection. A missing item is unknown; this never fetches sources or infers.
    func nativeLearningItems(_ kind:MemorySourceKind,now:Date = .now)->[NativeLearningItem]? {
        guard assistant.contextEnabled,!ProcessInfo.processInfo.arguments.contains("--sample") else { return nil }
        switch kind {
        case .calendar:
            guard orientationCollectionRevision == sourceRevision,EKEventStore.authorizationStatus(for:.event) == .fullAccess,NativeSourceAdapters.fresh(paOrientationHealth,now:now),let orientation=paOrientation,Calendar.current.isDate(orientation.refreshed,inSameDayAs:now) else { return nil }
            return NativeSourceAdapters.calendar(orientation,sources:assistant.excludedCalendars,now:now)
        case .reminder:
            guard reminderCollectionRevision == sourceRevision,EKEventStore.authorizationStatus(for:.reminder) == .fullAccess,NativeSourceAdapters.fresh(reminderHealth,now:now) else { return nil }
            return NativeSourceAdapters.reminders(reminderData,excluded:assistant.excludedLists)
        case .mail:
            guard NativeSourceAdapters.fresh(mailHealth,now:now) else { return nil }
            return NativeSourceAdapters.mail(mailData.messages,summaries:emailSummaries.records,registration:chatGPT.activeID,excluded:assistant.excludedAccounts,now:now)
        case .whatsapp:return nil
        }
    }
}
