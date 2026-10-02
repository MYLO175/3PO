import Foundation
import EventKit
import AppKit

actor EventKitService {
    private let store = EKEventStore()
    private struct CompletionRecord {
        let originalID: String
        let originalDue: DateComponents?
        let nextDue: DateComponents?
        let detachedID: String?
    }
    private var undoItems: [String: CompletionRecord] = [:]
    private func allReminders(in calendar: EKCalendar) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: [calendar])) { continuation.resume(returning: $0 ?? []) }
        }
    }
    private func access(_ type: EKEntityType) async throws {
        let status = EKEventStore.authorizationStatus(for: type)
        if status == .fullAccess { return }
        if status == .denied || status == .restricted { throw IntegrationError.denied(type == .event ? "Calendar" : "Reminders") }
        let granted = type == .event ? try await store.requestFullAccessToEvents() : try await store.requestFullAccessToReminders()
        if !granted { throw IntegrationError.denied(type == .event ? "Calendar" : "Reminders") }
    }
    private func option(_ calendar: EKCalendar) -> SourceOption {
        let color: SourceRGB?
        if let sRGB = NSColor(cgColor: calendar.cgColor)?.usingColorSpace(.sRGB) {
            color = SourceRGB(red: Double(sRGB.redComponent), green: Double(sRGB.greenComponent), blue: Double(sRGB.blueComponent))
        } else {
            color = nil
        }
        return .init(id: calendar.calendarIdentifier, title: calendar.title, account: calendar.source.title, writable: calendar.allowsContentModifications, color: color)
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
        let originalDue = item.dueDateComponents
        let title = item.title
        let notes = item.notes
        let calendar = item.calendar!
        let wasRecurring = item.hasRecurrenceRules
        let priorIDs = wasRecurring ? Set(await allReminders(in: calendar).map(\.calendarItemIdentifier)) : []
        let saveStarted = Date.now
        item.isCompleted = true
        do { try store.save(item, commit: true) } catch { store.reset(); throw error }
        guard let saved = store.calendarItem(withIdentifier: id) as? EKReminder else { throw IntegrationError.verification }
        var detachedID: String?
        if !saved.isCompleted {
            // EventKit advances the original series and creates a detached completed occurrence.
            guard wasRecurring, saved.dueDateComponents != originalDue else { throw IntegrationError.verification }
            let candidates = await allReminders(in: calendar).filter {
                !priorIDs.contains($0.calendarItemIdentifier) && $0.isCompleted &&
                $0.dueDateComponents == originalDue && $0.title == title && $0.notes == notes &&
                ($0.completionDate ?? .distantPast) >= saveStarted.addingTimeInterval(-2)
            }
            guard candidates.count == 1 else { throw IntegrationError.verification }
            detachedID = candidates[0].calendarItemIdentifier
        }
        let token = UUID().uuidString
        undoItems = [token: CompletionRecord(originalID: id, originalDue: originalDue, nextDue: saved.dueDateComponents, detachedID: detachedID)]
        return token
    }
    func undo(token: String) async throws {
        guard let record = undoItems[token], let item = store.calendarItem(withIdentifier: record.originalID) as? EKReminder else { throw IntegrationError.missing }
        guard item.calendar.allowsContentModifications else { throw IntegrationError.readOnly }
        if let detachedID = record.detachedID {
            guard !item.isCompleted, item.dueDateComponents == record.nextDue,
                  let detached = store.calendarItem(withIdentifier: detachedID) as? EKReminder, detached.isCompleted,
                  detached.dueDateComponents == record.originalDue,
                  detached.calendar.calendarIdentifier == item.calendar.calendarIdentifier else { throw IntegrationError.missing }
            item.dueDateComponents = record.originalDue
            item.isCompleted = false
            do {
                try store.save(item, commit: false)
                try store.remove(detached, commit: false)
                try store.commit()
            } catch { store.reset(); throw error }
            guard let restored = store.calendarItem(withIdentifier: record.originalID) as? EKReminder,
                  !restored.isCompleted, restored.dueDateComponents == record.originalDue,
                  store.calendarItem(withIdentifier: detachedID) == nil else { throw IntegrationError.verification }
        } else {
            guard item.isCompleted else { throw IntegrationError.missing }
            item.isCompleted = false
            do { try store.save(item, commit: true) } catch { store.reset(); throw error }
            guard let restored = store.calendarItem(withIdentifier: record.originalID) as? EKReminder, !restored.isCompleted else { throw IntegrationError.verification }
        }
        undoItems.removeValue(forKey: token)
    }
    // Developer-only acceptance check, invoked by an explicit launch argument.
    // Every write and cleanup is restricted to freshly created UUID-marked items.
    func validateDisposableReminders() async throws -> String {
        try await access(.reminder)
        guard let destination = store.calendars(for: .reminder).first(where: { $0.title == "To do" && $0.allowsContentModifications }) ?? store.defaultCalendarForNewReminders(), destination.allowsContentModifications else { throw IntegrationError.readOnly }
        let marker = "Mission Control validation " + UUID().uuidString
        var created: [EKReminder] = []
        func create(recurring: Bool) throws -> EKReminder {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = destination
            reminder.title = marker + (recurring ? " recurring" : " duplicate")
            reminder.notes = marker
            if recurring {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3)))
            }
            try store.save(reminder, commit: true)
            created.append(reminder)
            return reminder
        }
        var result = ""
        do {
            let first = try create(recurring: false)
            let second = try create(recurring: false)
            let firstID = first.calendarItemIdentifier
            let secondID = second.calendarItemIdentifier
            let token = try await complete(id: firstID)
            guard (store.calendarItem(withIdentifier: secondID) as? EKReminder)?.isCompleted == false else { throw IntegrationError.verification }
            try await undo(token: token)
            guard (store.calendarItem(withIdentifier: firstID) as? EKReminder)?.isCompleted == false else { throw IntegrationError.verification }
            result = "PASS duplicate-title completion and Undo; "
            let recurring = try create(recurring: true)
            let recurringID = recurring.calendarItemIdentifier
            let beforeExternal = recurring.calendarItemExternalIdentifier
            let beforeDue = recurring.dueDateComponents
            let recurringToken: String
            do { recurringToken = try await complete(id: recurringID) }
            catch {
                let diagnostic: [EKReminder] = await withCheckedContinuation { continuation in
                    store.fetchReminders(matching: store.predicateForReminders(in: [destination])) { continuation.resume(returning: $0 ?? []) }
                }
                let matching = diagnostic.filter { $0.notes == marker && $0.title.hasSuffix(" recurring") }
                result += "Recurring metadata: " + matching.map { item in
                    "originalID=\(item.calendarItemIdentifier == recurringID), sameExternal=\(item.calendarItemExternalIdentifier == beforeExternal), completed=\(item.isCompleted), sameDue=\(item.dueDateComponents == beforeDue)"
                }.joined(separator: " | ") + "; "
                throw error
            }
            try await undo(token: recurringToken)
            guard (store.calendarItem(withIdentifier: recurringID) as? EKReminder)?.isCompleted == false else { throw IntegrationError.verification }
            let recurrenceRows = await allReminders(in: destination).filter { $0.notes == marker && $0.title.hasSuffix(" recurring") }
            guard recurrenceRows.count == 1, !recurrenceRows[0].isCompleted, recurrenceRows[0].dueDateComponents == beforeDue else { throw IntegrationError.verification }
            result += "PASS recurring completion and Undo (one restored occurrence, no duplicate)."
        } catch { result += "FAIL: " + error.localizedDescription }
        let all: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: [destination])) { continuation.resume(returning: $0 ?? []) }
        }
        var cleanupErrors = 0
        for item in all where item.notes == marker {
            do { try store.remove(item, commit: true) } catch { cleanupErrors += 1 }
        }
        // Freshly saved objects may precede EventKit's async fetch snapshot.
        for item in created {
            if let remaining = store.calendarItem(withIdentifier: item.calendarItemIdentifier) as? EKReminder, remaining.notes == marker {
                do { try store.remove(remaining, commit: true) } catch { cleanupErrors += 1 }
            }
        }
        return result + (cleanupErrors == 0 ? " Disposable items cleaned up." : " Cleanup failures: \(cleanupErrors). Remove only Mission Control validation items in Reminders.")
    }

}
