import Foundation
import EventKit

actor EventKitService {
    private let store = EKEventStore()
    private var undoItems: [String: EKReminder] = [:]
    private func access(_ type: EKEntityType) async throws {
        let status = EKEventStore.authorizationStatus(for: type)
        if status == .fullAccess { return }
        if status == .denied || status == .restricted { throw IntegrationError.denied(type == .event ? "Calendar" : "Reminders") }
        let granted = type == .event ? try await store.requestFullAccessToEvents() : try await store.requestFullAccessToReminders()
        if !granted { throw IntegrationError.denied(type == .event ? "Calendar" : "Reminders") }
    }
    private func option(_ calendar: EKCalendar) -> SourceOption {
        .init(id: calendar.calendarIdentifier, title: calendar.title, account: calendar.source.title, writable: calendar.allowsContentModifications)
    }
    func calendar(from start: Date, to end: Date) async throws -> CalendarSnapshot {
        try await access(.event)
        let calendars = store.calendars(for: .event)
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars)).map { event in
            AgendaEvent(id: DateRules.occurrenceID(event.eventIdentifier ?? event.calendarItemIdentifier, start: event.startDate), calendarID: event.calendar.calendarIdentifier, title: event.title ?? "Untitled event", start: event.startDate, end: event.endDate, allDay: event.isAllDay, location: event.location ?? "", sourceLabel: option(event.calendar).label)
        }.sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
        return .init(sources: calendars.map(option).sorted { $0.label < $1.label }, events: events)
    }
    func reminders() async throws -> ReminderSnapshot {
        try await access(.reminder)
        let calendars = store.calendars(for: .reminder)
        let items: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)) { continuation.resume(returning: $0 ?? []) }
        }
        let reminders = items.map { item in
            let components = item.dueDateComponents
            var calendar = components?.calendar ?? Calendar.current
            calendar.timeZone = components?.timeZone ?? .current
            let due = components.flatMap { calendar.date(from: $0) }
            return TaskItem(id: item.calendarItemIdentifier, listID: item.calendar.calendarIdentifier, title: item.title ?? "Untitled reminder", due: due, hasTime: components?.hour != nil, sourceLabel: option(item.calendar).label, writable: item.calendar.allowsContentModifications, recurring: item.hasRecurrenceRules)
        }
        return .init(sources: calendars.map(option).sorted { $0.label < $1.label }, reminders: DateRules.ordered(reminders))
    }
    func complete(id: String) async throws -> String {
        try await access(.reminder)
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder, !item.isCompleted else { throw IntegrationError.missing }
        guard item.calendar.allowsContentModifications else { throw IntegrationError.readOnly }
        item.isCompleted = true
        do { try store.save(item, commit: true) } catch { store.reset(); throw error }
        guard let saved = store.calendarItem(withIdentifier: item.calendarItemIdentifier) as? EKReminder, saved.isCompleted else { throw IntegrationError.verification }
        let token = UUID().uuidString
        undoItems[token] = saved
        return token
    }
    func undo(token: String) async throws {
        guard let original = undoItems[token], let item = store.calendarItem(withIdentifier: original.calendarItemIdentifier) as? EKReminder, item.isCompleted else { throw IntegrationError.missing }
        guard item.calendar.allowsContentModifications else { throw IntegrationError.readOnly }
        item.isCompleted = false
        do { try store.save(item, commit: true) } catch { store.reset(); throw error }
        guard let saved = store.calendarItem(withIdentifier: item.calendarItemIdentifier) as? EKReminder, !saved.isCompleted else { throw IntegrationError.verification }
        undoItems.removeValue(forKey: token)
    }
}
