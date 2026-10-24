import SwiftUI

struct GraphitiMemoryView: View {
    @Bindable var model: DashboardModel
    let registration: String
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var indexingFocus = ""
    @State private var showingGraph = false
    @State private var showingSettings = true
    @State private var selectedNode: String?
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
            DisclosureGroup("Memory and indexing settings", isExpanded: $showingSettings) {
            VStack(alignment: .leading, spacing: 16) {
            Text("Compare how 3PO remembers your life. Your existing context pages, supporting facts and history stay saved.")
                .foregroundStyle(.secondary)
            Picker("Memory for ordinary chat", selection: Binding(get: { state.mode }, set: { model.graphiti.configure(registration, mode: $0) })) {
                ForEach(GraphitiMemoryMode.allCases) { mode in Text(mode.title).tag(mode) }
            }.pickerStyle(.segmented).disabled(model.assistant.busy || model.graphiti.busy)
            Text("Graphiti mode retrieves relationships from the graph and withholds factual context pages. Instructions and current source tools remain available. Review and briefs continue using the existing system.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Learn Graphiti relationships during heartbeats", isOn: Binding(get: { state.learningEnabled }, set: { model.graphiti.configure(registration, learning: $0) }))
                .disabled(model.graphiti.busy)
            Text("Learns lasting background from permitted shared conversations, supporting facts and human notes. Calendar events, reminders and project task state stay in their source apps. Mixed records are screened before graph extraction. Existing memory and learning controls still apply. AI extraction uses your connected ChatGPT plan; semantic search runs locally.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Label(model.graphiti.runtimeAvailable ? "Local Graphiti runtime ready" : "Local runtime needs setup", systemImage: model.graphiti.runtimeAvailable ? "checkmark.circle" : "exclamationmark.circle")
                Spacer()
                Text("\(state.indexedCount) indexed · \(state.pendingCount) pending").monospacedDigit()
            }.font(.callout)
            HStack {
                Button("Index next record") { model.graphiti.update(model) }
                    .disabled(!model.graphiti.runtimeAvailable || model.graphiti.busy || model.assistant.busy || model.chatGPT.busy || model.heartbeat.busy || !model.assistant.memory.enabled || !model.assistant.memory.learningEnabled)
                Button("Index all pending") { model.graphiti.update(model, all: true) }
                    .disabled(model.graphiti.busy || model.assistant.busy || model.chatGPT.busy || model.heartbeat.busy || !model.graphiti.runtimeAvailable)
                if model.graphiti.busy {
                    ProgressView().controlSize(.small)
                    Button("Stop") { searchTask?.cancel(); model.graphiti.cancel() }
                }
                Button("Delete experimental graph", role: .destructive) { Task { await model.graphiti.clear(model) } }.disabled(model.graphiti.busy || !model.graphiti.runtimeAvailable)
                if let updated = state.updated { Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                TextField("Index a person or topic, e.g. Cipolla", text: $indexingFocus)
                Button("Index matching background") { model.graphiti.update(model, focus: indexingFocus) }
                    .disabled(indexingFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || indexingFocus.utf8.count > 200 || !model.graphiti.runtimeAvailable || model.graphiti.busy || model.assistant.busy || model.chatGPT.busy || model.heartbeat.busy || !model.assistant.memory.enabled || !model.assistant.memory.learningEnabled)
            }
            Text("Processes up to six pending original records containing this phrase. Existing relationships are retained; this does not add a new memory.").font(.caption).foregroundStyle(.secondary)
            Text("The first background-only update rebuilds the earlier broad experimental index. Original records and context pages stay saved. Records with no lasting background are marked processed without adding relationships.").font(.caption).foregroundStyle(.secondary)
            Text(model.graphiti.status).font(.caption).textSelection(.enabled)
            if let error = model.graphiti.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if !model.graphiti.runtimeAvailable {
                Text("Install this experiment's local runtime with scripts/graphiti/setup.sh. Setup downloads Graphiti and its local embedding model; it does not read your personal data.")
                    .font(.caption).textSelection(.enabled)
            }
            }
            }
            Divider()
            HStack {
                Button("View saved graph") { lookup(browse: true) }
                    .disabled(searching || model.graphiti.busy || model.assistant.busy || model.heartbeat.busy)
                if searching { ProgressView().controlSize(.small) }
                Text("Viewing and searching use saved relationships, without AI extraction.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Try a graph lookup").font(.headline)
            HStack {
                TextField("For example: Which projects relate to my current goals?", text: $question)
                Button("Search") {
                    lookup(browse: false)
                }.disabled(searching || model.graphiti.busy || model.assistant.busy || model.heartbeat.busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                if resultCapture.map({ !$0.current() }) == true {
                    Text("These results are no longer current. Search again.")
                } else if let data = result.data(using: .utf8), let report = try? JSONDecoder().decode(GraphitiLookupReport.self, from: data) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(report.indexedEpisodes) records indexed · \(report.pendingEpisodes) awaiting update · \(report.omittedEpisodes) outside this snapshot")
                            .font(.caption).foregroundStyle(.secondary)
                        if report.facts.isEmpty {
                            Text(showingGraph ? "No current relationships are available in this graph sample. Index a record or try a focused search." : "No matching relationships were retrieved. The graph may be incomplete; this does not mean the information is absent from your life or original records.")
                        }
                        if showingGraph && !report.facts.isEmpty {
                            GraphitiNetwork(report: report, selected: $selectedNode).frame(height: 360)
                            HStack {
                                Text("Select a node to inspect its relationships below.").font(.caption)
                                if selectedNode != nil { Button("Show all relationships") { selectedNode = nil } }
                            }
                            if report.bounded == true { Text("Showing a bounded sample from the first 201 stored relationships. Search to find other connections.").font(.caption).foregroundStyle(.secondary) }
                        }
                        ForEach(report.facts.filter { selectedNode == nil || $0.source == selectedNode || $0.target == selectedNode }) { fact in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(fact.text)
                                if let start = fact.valid_at { Text("Applies from: " + GraphitiLookupReport.date(start)).font(.caption).foregroundStyle(.secondary) }
                                if let end = fact.invalid_at { Text("Applies until: " + GraphitiLookupReport.date(end)).font(.caption).foregroundStyle(.secondary) }
                                DisclosureGroup("Evidence · \(fact.sources.count) sources") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(Array(fact.sources.enumerated()), id: \.offset) { _, source in
                                            Text(source.title + " · " + GraphitiLookupReport.date(source.observed)).font(.caption)
                                            Text(source.reference).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                                        }
                                        Text("An AI interpretation of these sources. Check attribution, dates and the original evidence before relying on it.").font(.caption).foregroundStyle(.secondary)
                                    }.padding(.top, 4)
                                }.font(.caption)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                    }.textSelection(.enabled)
                } else {
                    Text(result.isEmpty ? "Ask about a person, project, goal or connection. Results include dates and evidence; searching does not run AI extraction." : result)
                        .textSelection(.enabled)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)

        }.padding(24).frame(width: 960, height: 760)
            .disabled(registration != model.chatGPT.activeID || !model.graphiti.readable)
            .onChange(of: model.chatGPT.activeID) { searchTask?.cancel(); result = ""; dismiss() }
            .onDisappear { searchTask?.cancel() }
    }
    private func lookup(browse: Bool) {
        let query = browse ? "Saved graph" : question
        searching = true; result = ""; resultCapture = nil; selectedNode = nil; showingGraph = browse
        if browse { showingSettings = false }
        searchTask = Task {
            defer { searching = false; searchTask = nil }
            do {
                let capture = try await model.graphiti.search(query, model: model, registration: registration, browse: browse)
                guard capture.current() else { throw CancellationError() }
                resultCapture = capture; result = capture.text
            } catch is CancellationError { result = "Lookup stopped." }
            catch { result = error.localizedDescription }
        }
    }

}

private struct GraphitiLookupReport: Decodable {
    struct Source: Decodable { let reference: String; let title: String; let observed: String }
    struct Fact: Decodable, Identifiable {
        let id: String
        let text: String
        let source: String?
        let target: String?
        let valid_at: String?
        let invalid_at: String?
        let sources: [Source]
    }
    struct Node: Decodable, Identifiable { let id: String; let name: String }
    let nodes: [Node]?
    let bounded: Bool?
    let facts: [Fact]
    let indexedEpisodes: Int
    let pendingEpisodes: Int
    let omittedEpisodes: Int
    static func date(_ value: String) -> String {
        guard let date = try? Date(value, strategy: .iso8601) else { return value }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}


private struct GraphitiNetwork: View {
    let report: GraphitiLookupReport
    @Binding var selected: String?
    @State private var scale = 1.0
    private var nodes: [GraphitiLookupReport.Node] {
        let used = Set(report.facts.flatMap { [$0.source, $0.target].compactMap { $0 } })
        return (report.nodes ?? []).filter { used.contains($0.id) }.sorted { $0.name < $1.name }
    }
    private func point(_ index: Int, count: Int, size: CGSize) -> CGPoint {
        let angle = Double(index) * 2 * Double.pi / Double(max(count, 1)) - Double.pi / 2
        return CGPoint(x: size.width / 2 + cos(angle) * max(0, size.width / 2 - 80), y: size.height / 2 + sin(angle) * max(0, size.height / 2 - 40))
    }
    var body: some View {
        let items = nodes
        VStack(alignment: .leading) {
            HStack {
                Text("\(items.count) entities · \(report.facts.count) relationships").font(.caption)
                Spacer()
                Button("−") { scale = max(1, scale - 0.25) }.accessibilityLabel("Zoom out")
                Button("+") { scale = min(2, scale + 0.25) }.accessibilityLabel("Zoom in")
            }
            GeometryReader { geometry in
            let size = CGSize(width: geometry.size.width * scale, height: geometry.size.height * scale)
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        let positions = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, point($0.offset, count: items.count, size: size)) })
                        for edge in report.facts {
                            guard let source = edge.source, let target = edge.target, let a = positions[source], let b = positions[target] else { continue }
                            var path = Path(); path.move(to: a); path.addLine(to: b)
                            let highlighted = selected == source || selected == target
                            context.stroke(path, with: .color(highlighted ? .accentColor : .secondary.opacity(0.3)), lineWidth: highlighted ? 2.5 : 1)
                        }
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, node in
                        Button { selected = selected == node.id ? nil : node.id } label: {
                            VStack(spacing: 3) {
                                Circle().fill(selected == node.id ? Color.accentColor : Color.secondary).frame(width: 14, height: 14)
                                Text(node.name).font(.caption).lineLimit(3).multilineTextAlignment(.center)
                                    .padding(3).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                            }.frame(width: 120)
                        }.buttonStyle(.plain).help(node.name).position(point(index, count: items.count, size: size))
                    }
                }.frame(width: size.width, height: size.height)
            }.background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
