import SwiftUI

struct NativeItemEditor: View {
    @Bindable var model: DashboardModel
    var target: NativeEditTarget
    @Environment(\.dismiss) private var dismiss
    @State private var baseline: NativeEditDetails?
    @State private var edited: NativeEditDetails?
    @State private var sources: [SourceOption] = []
    @State private var loading = true
    @State private var error: String?
    @State private var saving = false
    private var isEvent: Bool { if case .event = target { return true }; return false }
    private func field<Value>(_ path: WritableKeyPath<NativeEditDetails,Value>, fallback: Value) -> Binding<Value> {
        Binding(get:{ edited?[keyPath:path] ?? fallback },set:{ edited?[keyPath:path] = $0 })
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Label(isEvent ? "Event details" : "Reminder details",systemImage:isEvent ? "calendar" : "checklist").font(.title2.weight(.semibold)); Spacer(); if loading || saving { ProgressView().controlSize(.small) } }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if let baseline, let edited {
                if !baseline.writable { Label("This source is read-only.",systemImage:"lock").font(.callout).foregroundStyle(.secondary) }
                else if !baseline.canEdit { Text("Recurring reminder editing is deferred. You can still complete an occurrence and Undo from the dashboard.").font(.callout).foregroundStyle(.secondary) }
                else if baseline.recurring { Text("Changes apply to this occurrence only; the rest of the series stays unchanged.").font(.callout).foregroundStyle(.secondary) }
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        TextField("Title",text:field(\.title,fallback:"")).textFieldStyle(.roundedBorder)
                        Picker(isEvent ? "Calendar" : "List",selection:field(\.sourceID,fallback:baseline.sourceID)) {
                            ForEach(sources.filter { $0.writable || $0.id == baseline.sourceID }) { Text($0.label + ($0.writable ? "" : " · Read-only")).tag($0.id) }
                        }.disabled(baseline.recurring && isEvent)
                        if isEvent {
                            Toggle("All day",isOn:Binding(get:{ self.edited?.allDay ?? false },set:{ enabled in if let value = self.edited { self.edited = NativeEditRules.allDay(value,enabled:enabled) } }))
                            DatePicker("Starts",selection:field(\.start,fallback:.now),displayedComponents:edited.allDay ? .date : [.date,.hourAndMinute])
                            if edited.allDay {
                                DatePicker("Last day",selection:Binding(get:{ Calendar.current.date(byAdding:.day,value:-1,to:self.edited?.end ?? .now)! },set:{ self.edited?.end = Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:$0))! }),displayedComponents:.date)
                            } else { DatePicker("Ends",selection:field(\.end,fallback:.now),displayedComponents:[.date,.hourAndMinute]) }
                            TextField("Location",text:field(\.location,fallback:"")).textFieldStyle(.roundedBorder)
                        } else {
                            Toggle("Due date",isOn:Binding(get:{ self.edited?.due != nil },set:{ enabled in self.edited?.due = enabled ? Calendar.current.startOfDay(for:.now) : nil; if !enabled { self.edited?.hasTime = false } }))
                            if edited.due != nil {
                                Toggle("Include time",isOn:field(\.hasTime,fallback:false))
                                DatePicker("Due",selection:Binding(get:{ self.edited?.due ?? .now },set:{ self.edited?.due = $0 }),displayedComponents:edited.hasTime ? [.date,.hourAndMinute] : .date)
                            }
                        }
                        Text("Notes").font(.subheadline.weight(.semibold))
                        TextEditor(text:field(\.notes,fallback:"")).frame(minHeight:115).padding(5).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.primary.opacity(0.12)))
                        if isEvent && !edited.allDay || !isEvent && edited.hasTime { Text("Times shown in " + TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary) }
                    }.disabled(!baseline.canEdit || saving).padding(2)
                        .environment(\.timeZone,TimeZone.current)
                }
            } else if loading { Text("Loading the current Apple item…").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity) }
            Spacer(minLength:0)
            Divider()
            HStack {
                Button(saving ? "Saving…" : "Cancel") { dismiss() }.disabled(saving).keyboardShortcut(.cancelAction)
                if error != nil && !saving { Button("Reload current item") { Task { await load() } } }
                Spacer()
                if let baseline, baseline.canEdit {
                    Button(baseline.recurring ? "Save this occurrence" : "Save changes") { Task { await save() } }.keyboardShortcut(.defaultAction).disabled(saving || model.writing || model.assistant.busy || edited == baseline)
                }
            }
        }.padding(24).frame(width:520,height:620).interactiveDismissDisabled(saving).task { await load() }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        guard !ProcessInfo.processInfo.arguments.contains("--sample") else { error = "Sample items are read-only; open the normal app to edit Apple items."; return }
        do {
            let session = try await model.eventKit.editSession(target)
            try Task.checkCancellation(); baseline = session.item; edited = session.item; sources = session.sources
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func save() async {
        guard let baseline, let edited else { return }
        saving = true; error = nil; defer { saving = false }
        do { try await model.saveNativeEdit(baseline:baseline,edited:edited); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
