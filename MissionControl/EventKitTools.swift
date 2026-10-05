import Foundation

extension NativeEditDetails {
    mutating func applyToolOptions(_ raw: String?) throws {
        guard let raw,let object=try JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [String:Any] else { return }
        if let values=object["recurrence"] as? [[String:Any]] {
            recurrenceRules = try values.map { value in
                let days=(value["weekdays"] as? [[String:Int]] ?? []).map { NativeRepeatDay(weekday:$0["weekday"] ?? 0,week:$0["week"] ?? 0) }
                let end = try (value["endDate"] as? String).map { try ActionRules.date($0,dateOnly:false) }
                return NativeRecurrence(frequency:value["frequency"] as? String ?? "",interval:value["interval"] as? Int ?? 0,weekdays:days,monthDays:value["monthDays"] as? [Int] ?? [],months:value["months"] as? [Int] ?? [],yearWeeks:value["yearWeeks"] as? [Int] ?? [],yearDays:value["yearDays"] as? [Int] ?? [],positions:value["positions"] as? [Int] ?? [],endDate:end,count:value["count"] as? Int ?? 0)
            }
        }
        if let values=object["alerts"] as? [[String:Any]] {
            alarms = try values.map { value in
                let absolute = try (value["absolute"] as? String).map { try ActionRules.date($0,dateOnly:false) }
                return NativeTimeAlarm(absolute:absolute,offset:-(value["minutesBefore"] as? Double ?? 0)*60)
            }
        }
        if let value=object["url"] as? String { url=value }
        if let value=object["timeZone"] as? String { guard kind == .event && !allDay else {throw ActionFailure.message("Editable time zones apply to timed Calendar events; reminder and date-only controls use local dates/times.")};guard TimeZone(identifier:value) != nil else { throw ActionFailure.message("Unknown time zone.") };timeZoneID=value }
        if let value=object["priority"] as? String { guard kind == .reminder,let priority=["none":0,"high":1,"medium":5,"low":9][value] else {throw ActionFailure.message("Priority applies to Reminders only.")};self.priority=priority }
        if let value=object["availability"] as? String { guard kind == .event,let availability=["busy":0,"free":1,"tentative":2,"unavailable":3][value] else {throw ActionFailure.message("Availability applies to Calendar only.")};self.availability=availability }
    }
    mutating func applyToolFields(_ draft: ActionDraft) throws {
        if let title=draft.title {self.title=title}
        if let notes=draft.notes {self.notes=notes}
        if let location=draft.location {self.location=location}
        if let destination=draft.destination {sourceID=destination}
        if kind == .reminder,let due=draft.due {
            if due == "undated" { self.due=nil;hasTime=false }
            else {guard let timed=draft.hasTime else {throw ActionFailure.message("Specify whether the due date includes a time.")};self.due=try ActionRules.date(due,dateOnly:!timed);hasTime=timed}
        }
        if kind == .event {
            let allDay=draft.allDay ?? self.allDay
            guard allDay == self.allDay || draft.start != nil && draft.end != nil else {throw ActionFailure.message("Changing all-day status requires both boundaries.")}
            self.allDay=allDay
            if let start=draft.start {self=NativeEditRules.movingStart(self,to:try ActionRules.date(start,dateOnly:allDay))}
            if let end=draft.end {self.end=try ActionRules.date(end,dateOnly:allDay)}
        }
        try applyToolOptions(draft.options)
    }
}
extension EventKitService {
    func applyTool(_ draft: ActionDraft, reminder: TaskItem?, event: AgendaEvent?, marker: String, allowedCalendars: Set<String>, allowedLists: Set<String>, expectedDetails: NativeEditDetails? = nil, valid: NativeWriteValidity? = nil) async throws -> ActionResult {
        try ActionRules.validate(draft)
        guard (draft.notes?.count ?? 0) <= 10_000, (draft.location?.count ?? 0) <= 2000 else {throw ActionFailure.message("Notes/location exceed supported size.")}
        if draft.kind == .completeReminder {return try await apply(draft,reminder:reminder,event:event,marker:marker,allowedCalendars:allowedCalendars,allowedLists:allowedLists)}
        if draft.kind == .createEvent || draft.kind == .createReminder {
            let request=NativeCreationRequest(kind:draft.kind == .createEvent ? .event : .reminder,registration:"tool",title:draft.title ?? "",notes:draft.notes ?? "Mission Control request " + marker)
            let session=try await creationSession(request),baseline=session.item
            var edited=baseline;try edited.applyToolFields(draft)
            guard (edited.kind == .event ? allowedCalendars : allowedLists).contains(edited.sourceID) else {throw IntegrationError.readOnly}
            let receipt=try await createItem(request:request,baseline:baseline,edited:edited,scope:"tool",valid:valid)
            return .init(message:"Created " + (edited.kind == .event ? "event: " : "reminder: ") + receipt.title,itemID:receipt.itemID)
        }
        let target: NativeEditTarget
        if draft.kind == .editReminder || draft.kind == .deleteReminder {
            guard let reminder,allowedLists.contains(reminder.listID) else {throw IntegrationError.readOnly};target = .reminder(reminder)
        } else {guard let event,allowedCalendars.contains(event.calendarID) else {throw IntegrationError.readOnly};target = .event(event)}
        let baseline=try await editSession(target).item
        if let expectedDetails {guard baseline == expectedDetails else {throw IntegrationError.missing}}
        guard baseline.canEdit else {throw IntegrationError.readOnly}
        let scope: NativeChangeScope
        if baseline.recurring {
            guard let raw=draft.scope,let resolved=NativeChangeScope(rawValue:raw) else {throw ActionFailure.message(baseline.kind == .event ? "Choose only this event or this and all future events." : "Choose the repeating reminder; its edit/delete affects future repeats.")};scope=resolved
        } else {scope = .occurrence;guard draft.scope == nil || draft.scope == "occurrence" else {throw ActionFailure.message("This item is not recurring.")}}
        if draft.kind == .deleteEvent || draft.kind == .deleteReminder {return .init(message:try await deleteItem(baseline:baseline,scope:scope,valid:valid),itemID:baseline.itemID)}
        var edited=baseline;try edited.applyToolFields(draft)
        let saved=try await saveEdit(baseline:baseline,edited:edited,scope:scope,valid:valid)
        let undo=NativeEditRules.supportsUndo(baseline:baseline,edited:edited,scope:scope) ? NativeEditUndo(original:baseline,saved:saved) : nil
        return .init(message:"Updated " + (baseline.kind == .event ? "event: " : "reminder: ") + saved.title + (scope == .futureEvents ? " (this and all future events)" : scope == .reminderSeries ? " (repeating reminder)" : ""),itemID:saved.itemID,nativeUndo:undo)
    }
}
