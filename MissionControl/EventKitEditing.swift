import Foundation
import EventKit

extension EventKitService {
    private func editorDetails(_ item: EKCalendarItem) -> NativeEditDetails {
        var value = NativeEditDetails(kind:item is EKEvent ? .event : .reminder,itemID:item.calendarItemIdentifier,occurrenceID:item.calendarItemIdentifier,sourceID:item.calendar.calendarIdentifier,title:item.title ?? "",notes:item.notes ?? "",recurring:item.hasRecurrenceRules,writable:item.calendar.allowsContentModifications,modified:item.lastModifiedDate)
        if let event = item as? EKEvent {
            value.occurrenceID = DateRules.occurrenceID(event.eventIdentifier ?? event.calendarItemIdentifier,start:event.startDate)
            value.start = event.startDate; value.end = event.endDate; value.allDay = event.isAllDay; value.location = event.location ?? ""
            if event.isAllDay {
                let endDay = Calendar.current.startOfDay(for:event.endDate)
                if event.endDate != endDay { value.end = Calendar.current.date(byAdding:.day,value:1,to:endDay)! }
            }
            value.timeZoneID = event.isAllDay ? TimeZone.current.identifier : (event.timeZone?.identifier ?? TimeZone.current.identifier)
        } else if let reminder = item as? EKReminder {
            var calendar = reminder.dueDateComponents?.calendar ?? Calendar.current
            calendar.timeZone = reminder.dueDateComponents?.timeZone ?? .current
            value.due = reminder.dueDateComponents.flatMap { calendar.date(from:$0) }
            value.hasTime = reminder.dueDateComponents?.hour != nil; value.timeZoneID = calendar.timeZone.identifier
        }
        return value
    }
    private func editorEvent(_ id: String, sourceID: String, start: Date, end: Date) throws -> EKEvent {
        guard let source = store.calendar(withIdentifier:sourceID) else { throw IntegrationError.missing }
        let matches = store.events(matching:store.predicateForEvents(withStart:start.addingTimeInterval(-1),end:max(end,start).addingTimeInterval(1),calendars:[source])).filter { DateRules.occurrenceID($0.eventIdentifier ?? $0.calendarItemIdentifier,start:$0.startDate) == id }
        guard matches.count == 1, let event = matches.first else { throw IntegrationError.missing }; return event
    }
    func editSession(_ target: NativeEditTarget) async throws -> NativeEditSession {
        switch target {
        case .event(let expected):
            try await access(.event); store.reset()
            let event = try editorEvent(expected.id,sourceID:expected.calendarID,start:expected.start,end:expected.end)
            guard (event.title ?? "Untitled event") == expected.title, event.startDate == expected.start, event.endDate == expected.end, event.isAllDay == expected.allDay, (event.location ?? "") == expected.location else { throw IntegrationError.missing }
            return NativeEditSession(item:editorDetails(event),sources:store.calendars(for:.event).map(option))
        case .reminder(let expected):
            try await access(.reminder); store.reset()
            guard let reminder = store.calendarItem(withIdentifier:expected.id) as? EKReminder, !reminder.isCompleted else { throw IntegrationError.missing }
            let details = editorDetails(reminder)
            guard (reminder.title ?? "Untitled reminder") == expected.title, details.sourceID == expected.listID, details.due == expected.due, details.hasTime == expected.hasTime, details.recurring == expected.recurring else { throw IntegrationError.missing }
            return NativeEditSession(item:details,sources:store.calendars(for:.reminder).map(option))
        }
    }
    func saveEdit(baseline: NativeEditDetails, edited: NativeEditDetails) async throws {
        try NativeEditRules.validate(edited,baseline:baseline)
        try await access(baseline.kind == .event ? .event : .reminder)
        store.reset()
        do {
            let native: EKCalendarItem
            if baseline.kind == .event { native = try editorEvent(baseline.occurrenceID,sourceID:baseline.sourceID,start:baseline.start,end:baseline.end) }
            else {
                guard let reminder = store.calendarItem(withIdentifier:baseline.itemID) as? EKReminder, !reminder.isCompleted else { throw IntegrationError.missing }; native = reminder
            }
            // Compare all exposed fields and revision before mutating, including notes not held in dashboard caches.
            guard editorDetails(native) == baseline else { throw IntegrationError.missing }
            guard let destination = store.calendar(withIdentifier:edited.sourceID), destination.allowsContentModifications,
                  destination.allowedEntityTypes.contains(baseline.kind == .event ? .event : .reminder) else { throw IntegrationError.readOnly }
            native.title = edited.title; native.notes = edited.notes.isEmpty ? nil : edited.notes; native.calendar = destination
            if let event = native as? EKEvent {
                event.location = edited.location.isEmpty ? nil : edited.location
                if edited.start != baseline.start || edited.end != baseline.end || edited.allDay != baseline.allDay {
                    event.timeZone = TimeZone(identifier:edited.timeZoneID) ?? .current
                    event.isAllDay = edited.allDay
                    // EventKit normalises dates when changing all-day/time-zone state.
                    // Set the requested boundaries after that conversion.
                    event.startDate = edited.start; event.endDate = edited.allDay ? edited.end.addingTimeInterval(-1) : edited.end
                }
                try store.save(event,span:.thisEvent,commit:true)
                let matches = store.events(matching:store.predicateForEvents(withStart:edited.start.addingTimeInterval(-1),end:edited.end.addingTimeInterval(1),calendars:[destination])).filter { $0.calendarItemIdentifier == event.calendarItemIdentifier && $0.startDate == edited.start }
                guard matches.count == 1, let saved = matches.first else {
                    #if DEBUG
                    throw ActionFailure.message("Event verification found \(matches.count) exact start/identity matches (all-day: \(edited.allDay)).")
                    #else
                    throw IntegrationError.verification
                    #endif
                }
                guard saved.title == edited.title, (saved.notes ?? "") == edited.notes, (saved.location ?? "") == edited.location, editorDetails(saved).end == edited.end, saved.isAllDay == edited.allDay else {
                    #if DEBUG
                    throw ActionFailure.message("Event verification mismatch: title=\(saved.title == edited.title), notes=\((saved.notes ?? "") == edited.notes), location=\((saved.location ?? "") == edited.location), end=\(editorDetails(saved).end == edited.end), allDay=\(saved.isAllDay == edited.allDay).")
                    #else
                    throw IntegrationError.verification
                    #endif
                }
            } else if let reminder = native as? EKReminder {
                if edited.due != baseline.due || edited.hasTime != baseline.hasTime {
                    var calendar = Calendar.current; calendar.timeZone = TimeZone(identifier:edited.timeZoneID) ?? .current
                    reminder.dueDateComponents = edited.due.map { calendar.dateComponents(edited.hasTime ? [.year,.month,.day,.hour,.minute,.second,.timeZone] : [.year,.month,.day],from:$0) }
                }
                try store.save(reminder,commit:true)
                guard let saved = store.calendarItem(withIdentifier:reminder.calendarItemIdentifier) as? EKReminder, !saved.isCompleted else { throw IntegrationError.verification }
                let details = editorDetails(saved)
                guard details.title == edited.title, details.notes == edited.notes, details.sourceID == edited.sourceID, details.hasTime == edited.hasTime else { throw IntegrationError.verification }
                if edited.hasTime { guard details.due == edited.due else { throw IntegrationError.verification } }
                else { let savedDay = details.due.map { DateRules.localDate($0) }, editedDay = edited.due.map { DateRules.localDate($0) }; guard savedDay == editedDay else { throw IntegrationError.verification } }
            }
        } catch { store.reset(); throw error }
    }
    #if DEBUG
    func validateNativeEditors() async throws -> String {
        try await access(.event); try await access(.reminder)
        guard let list = store.defaultCalendarForNewReminders(), list.allowsContentModifications,
              let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else { throw IntegrationError.readOnly }
        let marker = "Mission Control editor validation " + UUID().uuidString
        var fixtures: [(String,NativeItemKind)] = []
        var stage = "create reminder fixtures"
        let fixtureStart = Calendar.current.startOfDay(for:.now)
        let fixtureEnd = Calendar.current.date(byAdding:.day,value:5,to:fixtureStart)!
        func cleanup() throws {
            for (id,kind) in fixtures where kind == .reminder {
                guard let item = store.calendarItem(withIdentifier:id), item.notes?.hasPrefix(marker) == true else { throw IntegrationError.verification }
                if kind == .reminder, let reminder = item as? EKReminder { try store.remove(reminder,commit:true) }
                guard store.calendarItem(withIdentifier:id) == nil else { throw IntegrationError.verification }
            }
            // A detached occurrence can acquire a new ID. Reconcile only this UUID's
            // own notes marker in the fixture calendar/range, never titles.
            for _ in 0..<10 {
                let remaining = store.events(matching:store.predicateForEvents(withStart:fixtureStart,end:fixtureEnd,calendars:[calendar])).filter { $0.notes?.hasPrefix(marker) == true }.sorted { $0.startDate < $1.startDate }
                guard let event = remaining.first else { break }
                try store.remove(event,span:event.hasRecurrenceRules ? .futureEvents : .thisEvent,commit:true)
            }
            guard store.events(matching:store.predicateForEvents(withStart:fixtureStart,end:fixtureEnd,calendars:[calendar])).allSatisfy({ $0.notes?.hasPrefix(marker) != true }) else { throw IntegrationError.verification }
            fixtures = []
        }
        do {
            for _ in 0..<2 {
                let item = EKReminder(eventStore:store); item.title = marker; item.notes = marker; item.calendar = list
                try store.save(item,commit:true); fixtures.append((item.calendarItemIdentifier,.reminder))
            }
            guard let reminder = try await reminders().reminders.first(where:{ $0.id == fixtures[0].0 }) else { throw IntegrationError.missing }
            let baseline = try await editSession(.reminder(reminder)).item
            var edit = baseline; edit.title += " edited"; edit.notes += "\nEditor notes"; edit.due = Calendar.current.startOfDay(for:.now); edit.hasTime = false
            stage = "save date-only reminder"; try await saveEdit(baseline:baseline,edited:edit)
            store.reset()
            guard let other = store.calendarItem(withIdentifier:fixtures[1].0) as? EKReminder, other.title == marker, other.notes == marker, other.dueDateComponents == nil else { throw IntegrationError.verification }
            let current = editorDetails(store.calendarItem(withIdentifier:fixtures[0].0)!)
            var timed = current; timed.due = Date(timeIntervalSince1970:floor(Date.now.addingTimeInterval(7200).timeIntervalSince1970)); timed.hasTime = true
            stage = "save timed reminder"; try await saveEdit(baseline:current,edited:timed)
            store.reset()
            var staleRejected = false
            do { try await saveEdit(baseline:baseline,edited:edit) } catch IntegrationError.missing { staleRejected = true }
            guard staleRejected else { throw IntegrationError.verification }
            let timedCurrent = editorDetails(store.calendarItem(withIdentifier:fixtures[0].0)!)
            var undated = timedCurrent; undated.due = nil; undated.hasTime = false
            stage = "save undated reminder"; try await saveEdit(baseline:timedCurrent,edited:undated)
            let event = EKEvent(eventStore:store); event.title = marker; event.notes = marker; event.calendar = calendar
            event.startDate = Date(timeIntervalSince1970:floor(Date.now.addingTimeInterval(86400).timeIntervalSince1970)); event.endDate = event.startDate.addingTimeInterval(3600)
            try store.save(event,span:.thisEvent,commit:true); fixtures.append((event.calendarItemIdentifier,.event))
            let eventBaseline = editorDetails(event)
            var eventEdit = eventBaseline; eventEdit.title += " edited"; eventEdit.notes += "\nEditor notes"; eventEdit.location = "Fictional test room"
            eventEdit.start = eventEdit.start.addingTimeInterval(3600); eventEdit.end = eventEdit.end.addingTimeInterval(3600)
            stage = "save timed event"; try await saveEdit(baseline:eventBaseline,edited:eventEdit)
            store.reset()
            guard let savedEvent = store.calendarItem(withIdentifier:fixtures[2].0) as? EKEvent else { throw IntegrationError.verification }
            let eventCurrent = editorDetails(savedEvent)
            let wholeDay = NativeEditRules.allDay(eventCurrent,enabled:true)
            stage = "save all-day event"; try await saveEdit(baseline:eventCurrent,edited:wholeDay)
            store.reset()
            guard let changed = store.calendarItem(withIdentifier:fixtures[2].0) as? EKEvent else { throw IntegrationError.verification }
            let beforeExternalChange = editorDetails(changed)
            changed.notes = marker + "\nExternal fixture change"; try store.save(changed,span:.thisEvent,commit:true)
            var rejectedExternal = false
            do { try await saveEdit(baseline:beforeExternalChange,edited:beforeExternalChange) } catch IntegrationError.missing { rejectedExternal = true }
            guard rejectedExternal else { throw IntegrationError.verification }
            stage = "edit one recurring occurrence"
            let series = EKEvent(eventStore:store); series.calendar = calendar; series.title = marker; series.notes = marker
            series.startDate = Calendar.current.date(byAdding:.day,value:2,to:fixtureStart)!.addingTimeInterval(12*3600); series.endDate = series.startDate.addingTimeInterval(3600)
            series.addRecurrenceRule(EKRecurrenceRule(recurrenceWith:.daily,interval:1,end:EKRecurrenceEnd(occurrenceCount:2)))
            try store.save(series,span:.thisEvent,commit:true); store.reset()
            let occurrences = store.events(matching:store.predicateForEvents(withStart:series.startDate,end:fixtureEnd,calendars:[calendar])).filter { $0.notes == marker && $0.title == marker }.sorted { $0.startDate < $1.startDate }
            guard occurrences.count == 2 else { throw IntegrationError.verification }
            let occurrence = editorDetails(occurrences[0]); var one = occurrence; one.title += " selected occurrence"
            try await saveEdit(baseline:occurrence,edited:one); store.reset()
            let after = store.events(matching:store.predicateForEvents(withStart:occurrence.start,end:fixtureEnd,calendars:[calendar])).filter { $0.notes == marker }.sorted { $0.startDate < $1.startDate }
            guard after.count == 2, after[0].title == one.title, after[1].title == marker, after[1].startDate == occurrences[1].startDate else { throw IntegrationError.verification }
            stage = "cleanup"; try cleanup()
            return "PASS native editors: duplicate identity, notes, date-only/timed/undated reminder, event title/location/time/all-day, single recurring occurrence, stale/external-change refusal; fixtures removed and absence verified."
        } catch {
            do { try cleanup() } catch { throw ActionFailure.message("Native editor validation failed and fixture cleanup needs review. Only UUID-marked editor fixtures were touched.") }
            throw ActionFailure.message("Native editor check (" + stage + "): " + error.localizedDescription + " Fixtures removed.")
        }
    }
    #endif

}
