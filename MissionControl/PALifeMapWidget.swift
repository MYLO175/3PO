import SwiftUI
struct PALifeMapWidget: View {
    @Bindable var model:DashboardModel
    var configuration:Binding<WidgetConfiguration>
    @State private var selectedProject:LifeItem?
    @State private var selected:PAMemory?
    @State private var selectedArea:LifeArea?
    @State private var presentation="Map"
    @State private var areaDetails:LifeArea?
    @State private var areaMemory:PAMemory?
    @State private var detailOrganising:PAMemory?
    @State private var detailShowMemory=false
    private var topic:UUID? { nil }
    private var focusAreas:[LifeArea] {
        if let saved=configuration.wrappedValue.lifeFocusSelections?[model.chatGPT.activeID] { return LifeFocusRules.normalised(saved) }
        let legacy=configuration.wrappedValue.paTopicSelections?[model.chatGPT.activeID].flatMap(UUID.init(uuidString:))
        return model.assistant.conversation(legacy)?.notebookAreas ?? []
    }
    private var focusBinding:Binding<[LifeArea]> { Binding(get:{focusAreas},set:{ areas in
        var value=configuration.wrappedValue;if value.lifeFocusSelections == nil { value.lifeFocusSelections=[:] }
        value.lifeFocusSelections?[model.chatGPT.activeID]=areas.map(\.rawValue);configuration.wrappedValue=value;selectedArea=nil;areaDetails=nil;areaMemory=nil
    }) }
    private var notebook:LifeNotebook { model.assistant.memory.notebook(model.chatGPT.activeID,includeTopics:true) }
    private var notes:[LifeAreaNote] { notebook.notes.filter { focusAreas.isEmpty || focusAreas.contains($0.area) } }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Label("Life map",systemImage:"point.3.connected.trianglepath.dotted").font(.title3.weight(.semibold));Spacer()
                LifeFocusPicker(selection:focusBinding).frame(maxWidth:160,alignment:.trailing)
            }
            .fixedSize(horizontal:false,vertical:true)
            Picker("Life map view",selection:$presentation) { Text("Map").tag("Map");Text("Notes").tag("Notes");Text("Structure").tag("Structure") }
                .pickerStyle(.segmented).labelsHidden().frame(width:230).fixedSize(horizontal:false,vertical:true)
            if presentation == "Structure" {
                LifeProjectWidget(model:model,configuration:configuration,showsHeader:false,focusAreas:focusAreas)
            } else if presentation == "Map",!notebook.anchors.isEmpty {
                LifeCanonicalMapView(notebook:notebook,focus:focusAreas) { id in selectedProject=model.assistant.projects.items(model.chatGPT.activeID,includeTopics:true).first{$0.id == id} }
            } else if !model.assistant.memory.enabled {
                Text("Saved memory is off. Enable it in Memory to use your life notebook.").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else if notes.isEmpty {
                Text("Your life notebook grows from useful things you tell your PA. Set up your profile in the PA menu, or organise saved memories below.").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else if presentation == "Map" {
                LifeNotebookMapView(notebook:notebook,notes:notes,selectedArea:Binding(get:{selectedArea},set:{ selectedArea=$0;areaDetails=$0 }),fitsAvailableSpace:true)
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    VStack(alignment:.leading,spacing:16) { ForEach(notes) { note in LifeNotebookAreaView(notebook:notebook,note:note) { selected=$0 } } }
                        .frame(maxWidth:.infinity,alignment:.leading)
                }
            }
            HStack {
                Text("\(Set(notes.flatMap { $0.records.map(\.id) }).count) saved facts").font(.caption).foregroundStyle(.secondary).lineLimit(1).help(model.lifeOrganisation.summary(model))
                Spacer()
                if model.lifeOrganisation.busy { Button("Stop") { model.lifeOrganisation.cancel() } }
                else { Button("Organise memories") { model.lifeOrganisation.check(model,manual:true,topic:topic) }.disabled(!model.assistant.memory.enabled || !model.assistant.memory.learningEnabled || model.chatGPT.busy || model.assistant.busy || !model.chatGPT.inferenceVerified || model.chatGPT.usagePaused) }
            }.controlSize(.small)
            if let error=model.lifeOrganisation.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .sheet(item:$selectedProject) { item in
            LifeMapProjectDetails(model:model,item:item)
        }
        .sheet(item:$areaDetails) { area in
            VStack(alignment:.leading,spacing:14) {
                HStack { Label(area.title,systemImage:area.symbol).font(.title3.weight(.semibold));Spacer();Button("Done") { areaDetails=nil } }
                ScrollView { if let note=notes.first(where:{$0.area == area}) { LifeNotebookAreaView(notebook:notebook,note:note,showsHeading:false) { areaMemory=$0 } } }
            }.padding(24).frame(width:520,height:580)
                .sheet(item:$areaMemory) { memory in memoryDetails(memory,fromArea:true) }
        }
        .sheet(item:$selected) { memory in memoryDetails(memory)
        }
        .onChange(of:model.chatGPT.activeID) { selectedProject=nil;selected=nil;areaDetails=nil;areaMemory=nil;detailOrganising=nil;detailShowMemory=false;selectedArea=nil }
    }
    private func memoryDetails(_ memory:PAMemory,fromArea:Bool=false)->some View {
            VStack(alignment:.leading,spacing:14) {
                Text(memory.text).font(.title3.weight(.semibold)).textSelection(.enabled)
                Text(memory.attribution).font(.caption).foregroundStyle(.secondary)
                if let evidence=memory.evidence { Text("“"+evidence+"”").textSelection(.enabled) }
                ForEach(Array((memory.connections ?? []).enumerated()),id:\.offset) { _,edge in Text(edge.subject+" → "+edge.relation+" → "+edge.object).font(.callout) }
                Text(memory.provenance).font(.caption).foregroundStyle(.secondary)
                HStack { Button("Close") { if fromArea { areaMemory=nil } else { selected=nil } };Button("Organise") { detailOrganising=memory };Spacer();Button("Manage memories") { detailShowMemory=true } }
            }.padding(24).frame(width:480)
                .sheet(item:$detailOrganising) { memory in LifeOrganisationEditor(memory:model.assistant.memory,record:memory) }
                .sheet(isPresented:$detailShowMemory) { PAMemoryView(memory:model.assistant.memory,registration:model.chatGPT.activeID,conversationID:topic,topicTitle:model.assistant.conversation(topic)?.title,learning:model.memoryLearning,assistant:model.assistant,checkContext:{model.memoryLearning.check(model,manual:true)},organisation:model.lifeOrganisation,organiseContext:{model.lifeOrganisation.check(model,manual:true,topic:topic)}) }

    }
}

private struct LifeMapProjectDetails:View {
    @Bindable var model:DashboardModel
    var item:LifeItem
    @State private var configuration=WidgetConfiguration()
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("Life map").font(.headline);Spacer();Button("Done") { dismiss() } }
            LifeProjectWidget(model:model,configuration:$configuration,showsHeader:false)
        }.padding(24).frame(width:540,height:620)
        .onAppear { configuration.projectRoots=[item.registration:item.id.uuidString] }
    }
}
