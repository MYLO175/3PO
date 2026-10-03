import Foundation

extension EventKitService {
    func applyTool(_ draft: ActionDraft, reminder: TaskItem?, event: AgendaEvent?, marker: String, allowedCalendars: Set<String>, allowedLists: Set<String>) async throws -> ActionResult {
        try ActionRules.validate(draft)
        guard (draft.notes?.count ?? 0) <= 10_000, (draft.location?.count ?? 0) <= 2000 else { throw ActionFailure.message("Notes/location exceed supported size.") }
        guard draft.kind == .editReminder || draft.kind == .editEvent else {
            return try await apply(draft,reminder:reminder,event:event,marker:marker,allowedCalendars:allowedCalendars,allowedLists:allowedLists)
        }
        let target: NativeEditTarget
        if draft.kind == .editReminder {
            guard let reminder, allowedLists.contains(reminder.listID) else { throw IntegrationError.readOnly }
            target = .reminder(reminder)
        } else {
            guard let event, allowedCalendars.contains(event.calendarID) else { throw IntegrationError.readOnly }
            target = .event(event)
        }
        let session = try await editSession(target), baseline = session.item
        guard baseline.canEdit else { throw IntegrationError.readOnly }
        if baseline.recurring && draft.scope != "occurrence" { throw ActionFailure.message("Choose the single recurring event occurrence; series edits are deferred.") }
        var edited = baseline
        if let title = draft.title { edited.title = title }
        if let notes = draft.notes { edited.notes = notes }
        if let location = draft.location { edited.location = location }
        if let destination = draft.destination { edited.sourceID = destination }
        if baseline.kind == .reminder, let due = draft.due {
            if due == "undated" { edited.due = nil; edited.hasTime = false }
            else {
                guard let timed = draft.hasTime else { throw ActionFailure.message("Specify whether the due date includes a time.") }
                edited.due = try ActionRules.date(due,dateOnly:!timed); edited.hasTime = timed
            }
        }
        if baseline.kind == .event {
            let allDay = draft.allDay ?? baseline.allDay
            guard allDay == baseline.allDay || draft.start != nil && draft.end != nil else { throw ActionFailure.message("Changing all-day status requires both boundaries.") }
            edited.allDay = allDay
            if let start = draft.start { edited = NativeEditRules.movingStart(edited,to:try ActionRules.date(start,dateOnly:allDay)) }
            if let end = draft.end { edited.end = try ActionRules.date(end,dateOnly:allDay) }
        }
        let saved = try await saveEdit(baseline:baseline,edited:edited)
        return .init(message:"Updated " + (baseline.kind == .event ? "event: " : "reminder: ") + saved.title,itemID:saved.itemID,nativeUndo:NativeEditUndo(original:baseline,saved:saved))
    }
}
