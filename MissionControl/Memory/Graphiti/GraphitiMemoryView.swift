import SwiftUI

struct GraphitiMemoryView: View {
    @Bindable var model: DashboardModel
    let registration: String
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var result = ""
    @State private var resultCapture: AssistantPageContext?
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    var body: some View {
        let state = model.graphiti.settings(registration)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Graphiti memory experiment").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Compare how 3PO remembers your life. Your existing context pages, supporting facts and history stay saved.")
                .foregroundStyle(.secondary)
            Picker("Memory for ordinary chat", selection: Binding(get: { state.mode }, set: { model.graphiti.configure(registration, mode: $0) })) {
                ForEach(GraphitiMemoryMode.allCases) { mode in Text(mode.title).tag(mode) }
            }.pickerStyle(.segmented).disabled(model.assistant.busy || model.graphiti.busy)
            Text("Graphiti mode retrieves relationships from the graph and withholds factual context pages. Instructions and current source tools remain available. Review and briefs continue using the existing system.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Learn Graphiti relationships during heartbeats", isOn: Binding(get: { state.learningEnabled }, set: { model.graphiti.configure(registration, learning: $0) }))
                .disabled(model.graphiti.busy)
            Text("Uses permitted shared conversations, supporting facts, project records, human notes and eligible source updates. Existing memory and learning controls still apply. AI extraction uses your connected ChatGPT plan; semantic search runs locally.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Label(model.graphiti.runtimeAvailable ? "Local Graphiti runtime ready" : "Local runtime needs setup", systemImage: model.graphiti.runtimeAvailable ? "checkmark.circle" : "exclamationmark.circle")
                Spacer()
                Text("\(state.indexedCount) indexed · \(state.pendingCount) pending").monospacedDigit()
            }.font(.callout)
            HStack {
                Button(state.paused ? "Resume graph update" : "Update graph") { model.graphiti.update(model) }
                    .disabled(!model.graphiti.runtimeAvailable || model.graphiti.busy || model.assistant.busy || model.chatGPT.busy || model.heartbeat.busy || !model.assistant.memory.enabled || !model.assistant.memory.learningEnabled)
                if model.graphiti.busy {
                    ProgressView().controlSize(.small)
                    Button("Stop") { searchTask?.cancel(); model.graphiti.cancel() }
                }
                Button("Delete experimental graph", role: .destructive) { Task { await model.graphiti.clear(model) } }.disabled(model.graphiti.busy || !model.graphiti.runtimeAvailable)
                if let updated = state.updated { Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            }
            Text(model.graphiti.status).font(.caption).textSelection(.enabled)
            if let error = model.graphiti.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if !model.graphiti.runtimeAvailable {
                Text("Install this experiment's local runtime with scripts/graphiti/setup.sh. Setup downloads Graphiti and its local embedding model; it does not read your personal data.")
                    .font(.caption).textSelection(.enabled)
            }
            Divider()
            Text("Try a graph lookup").font(.headline)
            HStack {
                TextField("For example: Which projects relate to my current goals?", text: $question)
                Button("Search") {
                    let query = question
                    searching = true; result = ""; resultCapture = nil
                    searchTask = Task {
                        defer { searching = false; searchTask = nil }
                        do {
                            let capture = try await model.graphiti.search(query, model: model, registration: registration)
                            guard capture.current() else { throw CancellationError() }
                            resultCapture = capture; result = capture.text
                        } catch is CancellationError { result = "Search stopped." }
                        catch { result = error.localizedDescription }
                    }
                }.disabled(searching || model.graphiti.busy || model.assistant.busy || model.heartbeat.busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView { Text(resultCapture.map { !$0.current() } == true ? "These results are no longer current. Search again." : result.isEmpty ? "Results include relationship dates and the original evidence references. Searching does not run AI extraction." : result).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(24).frame(width: 760, height: 660)
            .disabled(registration != model.chatGPT.activeID || !model.graphiti.readable)
            .onChange(of: model.chatGPT.activeID) { searchTask?.cancel(); result = ""; dismiss() }
            .onDisappear { searchTask?.cancel() }
    }
}
