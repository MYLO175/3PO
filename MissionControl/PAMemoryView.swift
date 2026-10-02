import SwiftUI

struct PAMemoryView: View {
    @Bindable var memory: PAMemoryStore
    var registration: String
    var conversationID: UUID? = nil
    var topicTitle: String? = nil
    var learning: MemoryLearningService?
    var assistant: AssistantService?
    var checkContext: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PAMemory?
    @State private var text = ""
    @State private var scope: UUID?
    @State private var kind = MemoryKind.preference
    @State private var provisional = false
    @State private var forgotten: PAMemory?
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Label("What your PA remembers",systemImage:"brain").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            Toggle("Use saved memory in chats and briefs",isOn:$memory.enabled)
            Toggle("Learn useful context from conversations",isOn:$memory.learningEnabled)
            Text("When on, small batches of your chat messages are assessed through your ChatGPT plan. Learned entries stay provisional until confirmed. No email backlog is processed. Pausing stops future learning; you can still save explicit memories.").font(.caption).foregroundStyle(.secondary)
            if let learning, let assistant { HStack { Text(learning.status(assistant)).font(.caption).foregroundStyle(.secondary); Spacer(); if learning.busy { Button("Stop") { learning.cancel() } } else { Button("Check context") { checkContext?() }.disabled(assistant.connection.busy || assistant.busy || assistant.connection.usagePaused || !assistant.connection.inferenceVerified || !assistant.contextEnabled || assistant.hasDraft || !memory.enabled || !memory.learningEnabled) } }; if let error = learning.error { Text(error).font(.caption).foregroundStyle(.orange) } }
            Text("Shared memories are available everywhere; topic memories are supplied only in their topic (and when relevant in a daily brief). Explicit facts stay until you forget them. Provisional context needs review after 90 days. Completing a commitment here only updates memory; Apple reminders are separate.").font(.callout).foregroundStyle(.secondary)
            if let error = memory.error { Text(error).foregroundStyle(.orange).font(.caption) }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    ForEach(memory.items(registration)) { item in
                        VStack(alignment:.leading,spacing:6) {
                            HStack { Text(item.conversationID.map { "Topic · " + (assistant?.conversation($0)?.title ?? "Saved topic") } ?? "Shared").font(.caption).foregroundStyle(.secondary); Text(item.kind.rawValue.capitalized).font(.caption.weight(.semibold)); if item.resolved != nil { Text(MemoryRules.archived(item) ? "Archived" : "Resolved").font(.caption).foregroundStyle(.secondary) }; if MemoryRules.needsReview(item) { Text("Review needed").foregroundStyle(.orange).font(.caption) }; Spacer() }
                            Text(item.text).textSelection(.enabled)
                            if let evidence = item.evidence { Text("“" + evidence + "”").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                            Text((item.explicit ? "Explicit · " : "Provisional · ") + item.provenance).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            HStack {
                                if !item.explicit { Button("Confirm") { memory.accept(item.id) } }
                                Button("Edit") { editing = item; text = item.text; kind = item.kind; provisional = !item.explicit; scope = item.conversationID }
                                if item.resolved == nil && item.kind == .commitment { Button("Mark resolved") { memory.resolve(item.id) } }
                                if item.resolved != nil { Button("Reopen") { memory.reopen(item.id) } }
                                Button("Forget") { if memory.forget(item.id) { forgotten = item } }
                            }.controlSize(.small)
                        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                    }
                    if memory.items(registration).isEmpty { Text("Tell your PA ‘Remember that…’, or add something below.").foregroundStyle(.secondary).padding(.vertical) }
                }
            }
            if let forgotten { HStack { Text("Memory forgotten").font(.caption); Button("Undo") { if memory.put(forgotten) { self.forgotten = nil } }; Spacer() } }
            Divider()
            Text(editing == nil ? "Add a memory" : "Edit memory").font(.headline)
            TextField("For example: I need two weeks to arrange birthday presents",text:$text,axis:.vertical).lineLimit(2...4)
            Picker("Memory scope",selection:$scope) { Text("Shared PA memory").tag(Optional<UUID>.none); if let conversationID { Text(topicTitle ?? "This topic").tag(Optional(conversationID)) }; if let scope, scope != conversationID { Text(assistant?.conversation(scope)?.title ?? "Saved topic").tag(Optional(scope)) } }
            HStack { Picker("Kind",selection:$kind) { ForEach(MemoryKind.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }.frame(width:230); Toggle("Provisional",isOn:$provisional); Spacer() }
            HStack { if editing != nil { Button("Cancel edit") { clear() } }; Spacer(); Button("Save memory") {
                var item = editing ?? PAMemory(registration:registration,text:text,kind:kind,provenance:"Added by you in Memory")
                item.text = text; item.kind = kind; item.explicit = !provisional; item.conversationID = scope
                if memory.put(item) { clear() }
            }.disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || registration.isEmpty) }
        }.onAppear { scope = conversationID }.onChange(of:memory.learningEnabled) { _, enabled in if !enabled { learning?.cancel() } }.onChange(of:memory.enabled) { _, enabled in if !enabled { learning?.cancel() } }.padding(24).frame(width:680,height:760)
    }
    private func clear() { editing = nil; text = ""; provisional = false; kind = .preference; scope = conversationID }
}
