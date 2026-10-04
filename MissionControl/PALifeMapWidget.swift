import SwiftUI
struct PALifeMapWidget: View {
    @Bindable var model:DashboardModel
    var configuration:Binding<WidgetConfiguration>
    @State private var selected:PAMemory?
    @State private var organising:PAMemory?
    @State private var search=""
    @State private var showMemory=false
    @State private var selectedArea:LifeArea?
    @State private var presentation="Map"
    private var topic:UUID? {
        ConversationRules.topicSelection(configuration.wrappedValue.paTopicSelections?[model.chatGPT.activeID],legacy:nil,in:model.assistant.conversations,registration:model.chatGPT.activeID)
    }
    private var notebook:LifeNotebook { model.assistant.memory.notebook(model.chatGPT.activeID,topic:topic) }
    private var notes:[LifeAreaNote] {
        notebook.notes.compactMap { note in
            let records=note.records.filter { search.isEmpty || note.area.title.localizedCaseInsensitiveContains(search) || ($0.text+" "+($0.connections ?? []).map{$0.subject+" "+$0.relation+" "+$0.object}.joined(separator:" ")).localizedCaseInsensitiveContains(search) }
            return records.isEmpty ? nil : .init(area:note.area,records:records)
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Label("Life map",systemImage:"point.3.connected.trianglepath.dotted").font(.title3.weight(.semibold));Spacer()
                Picker("Map topic",selection:Binding(get:{topic?.uuidString ?? ""},set:{ value in var config=configuration.wrappedValue;if config.paTopicSelections == nil { config.paTopicSelections=[:] };config.paTopicSelections?[model.chatGPT.activeID]=value;configuration.wrappedValue=config;selectedArea=nil })) {
                    Text("General").tag("");ForEach(model.assistant.topics) { Text($0.title).tag($0.id.uuidString) }
                }.labelsHidden().frame(maxWidth:130)
            }
            HStack {
                TextField("Find a person, project or area",text:$search).textFieldStyle(.plain)
                Picker("Life map view",selection:$presentation) { Text("Map").tag("Map");Text("Notes").tag("Notes") }.pickerStyle(.segmented).frame(width:125)
            }
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    if !model.assistant.memory.enabled { Text("Saved memory is off. Enable it in Memory to use your life notebook.").foregroundStyle(.secondary) }
                    else if notes.isEmpty { Text(search.isEmpty ? "Your life notebook grows from useful things you tell your PA. Set up your profile in the PA menu, or organise saved memories below." : "No matching saved facts.").foregroundStyle(.secondary).padding(.vertical,15) }
                    else if presentation == "Map" {
                        LifeNotebookMapView(notebook:notebook,notes:notes,selectedArea:$selectedArea)
                        if let note=notes.first(where:{$0.area == selectedArea}) { LifeNotebookAreaView(notebook:notebook,note:note) { selected=$0 } }
                        else { Text("Choose an area to explore its people, goals, projects and connections. Area branches organise facts; factual links stay backed by evidence.").font(.caption).foregroundStyle(.secondary) }
                    } else { ForEach(notes) { note in LifeNotebookAreaView(notebook:notebook,note:note) { selected=$0 } } }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack {
                Text(model.lifeOrganisation.summary(model)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if model.lifeOrganisation.busy { Button("Stop") { model.lifeOrganisation.cancel() } }
                else { Button("Organise memories") { model.lifeOrganisation.check(model,manual:true,topic:topic) }.disabled(!model.assistant.memory.enabled || !model.assistant.memory.learningEnabled || model.chatGPT.busy || model.assistant.busy || !model.chatGPT.inferenceVerified || model.chatGPT.usagePaused) }
            }.controlSize(.small)
            if let error=model.lifeOrganisation.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .sheet(item:$selected) { memory in
            VStack(alignment:.leading,spacing:14) {
                Text(memory.text).font(.title3.weight(.semibold)).textSelection(.enabled)
                Text(memory.explicit || memory.certainty == .stated ? "You stated this" : "Provisional interpretation").font(.caption).foregroundStyle(.secondary)
                if let evidence=memory.evidence { Text("“"+evidence+"”").textSelection(.enabled) }
                ForEach(Array((memory.connections ?? []).enumerated()),id:\.offset) { _,edge in Text(edge.subject+" → "+edge.relation+" → "+edge.object).font(.callout) }
                Text(memory.provenance).font(.caption).foregroundStyle(.secondary)
                HStack { Button("Close") { selected=nil };Button("Organise") { selected=nil;organising=memory };Spacer();Button("Manage memories") { selected=nil;showMemory=true } }
            }.padding(24).frame(width:480)
        }.sheet(item:$organising) { memory in LifeOrganisationEditor(memory:model.assistant.memory,record:memory) }
        .sheet(isPresented:$showMemory) { PAMemoryView(memory:model.assistant.memory,registration:model.chatGPT.activeID,conversationID:topic,topicTitle:model.assistant.conversation(topic)?.title,learning:model.memoryLearning,assistant:model.assistant,checkContext:{model.memoryLearning.check(model,manual:true)},organisation:model.lifeOrganisation,organiseContext:{model.lifeOrganisation.check(model,manual:true,topic:topic)}) }
        .onChange(of:model.chatGPT.activeID) { selected=nil;organising=nil;search="";showMemory=false;selectedArea=nil }
    }
}
