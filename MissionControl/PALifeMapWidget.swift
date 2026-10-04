import SwiftUI
struct PALifeMapWidget: View {
    @Bindable var model:DashboardModel
    var configuration:Binding<WidgetConfiguration>
    @State private var selected:PAMemory?
    @State private var search=""
    @State private var showMemory=false
    private var topic:UUID? {
        ConversationRules.topicSelection(configuration.wrappedValue.paTopicSelections?[model.chatGPT.activeID],legacy:nil,in:model.assistant.conversations,registration:model.chatGPT.activeID)
    }
    private var records:[PAMemory] {
        model.assistant.memory.items(model.chatGPT.activeID).filter { MemoryRules.usable($0,registration:model.chatGPT.activeID) && MemoryRules.inScope($0,conversationID:topic) && (search.isEmpty || ($0.text+" "+($0.connections ?? []).map{$0.subject+" "+$0.relation+" "+$0.object}.joined(separator:" ")).localizedCaseInsensitiveContains(search)) }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Label("Life map",systemImage:"point.3.connected.trianglepath.dotted").font(.title3.weight(.semibold)); Spacer()
                Picker("Map topic",selection:Binding(get:{topic?.uuidString ?? ""},set:{ value in var config=configuration.wrappedValue; if config.paTopicSelections == nil { config.paTopicSelections=[:] }; config.paTopicSelections?[model.chatGPT.activeID]=value; configuration.wrappedValue=config })) {
                    Text("Shared").tag(""); ForEach(model.assistant.topics) { Text($0.title).tag($0.id.uuidString) }
                }.labelsHidden().frame(maxWidth:130)
            }
            TextField("Find a person, project or topic",text:$search).textFieldStyle(.plain)
            GeometryReader { geometry in
                ScrollView {
                    PAMemoryGraphView(graph:PAMemoryGraph.build(records,registration:model.chatGPT.activeID,topic:topic),records:records,inspect:{selected=$0},height:max(220,geometry.size.height-70))
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .sheet(item:$selected) { memory in
            VStack(alignment:.leading,spacing:14) {
                Text(memory.text).font(.title3.weight(.semibold)).textSelection(.enabled)
                Text(memory.explicit || memory.certainty == .stated ? "You stated this" : "Provisional interpretation").font(.caption).foregroundStyle(.secondary)
                if let evidence=memory.evidence { Text("“"+evidence+"”").textSelection(.enabled) }
                ForEach(Array((memory.connections ?? []).enumerated()),id:\.offset) { _,edge in Text(edge.subject+" → "+edge.relation+" → "+edge.object).font(.callout) }
                Text(memory.provenance).font(.caption).foregroundStyle(.secondary)
                HStack { Button("Close") { selected=nil }; Spacer(); Button("Manage memories") { selected=nil; showMemory=true } }
            }.padding(24).frame(width:480)
        }.sheet(isPresented:$showMemory) { PAMemoryView(memory:model.assistant.memory,registration:model.chatGPT.activeID,conversationID:topic,topicTitle:model.assistant.conversation(topic)?.title,learning:model.memoryLearning,assistant:model.assistant) { model.memoryLearning.check(model,manual:true) } }.onChange(of:model.chatGPT.activeID) { selected=nil; search=""; showMemory=false }
    }
}
