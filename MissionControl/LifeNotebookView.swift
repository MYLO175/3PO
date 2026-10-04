import SwiftUI

extension LifeArea {
    var colour:Color { switch self {
    case .about:.teal;case .studies:.blue;case .career:.indigo;case .projects:.purple;case .interests:.orange;case .wellbeing:.green;case .people:.pink;case .home:.brown;case .administration:.cyan;case .unsorted:.gray
    } }
}
extension LifeEntityKind {
    var symbol:String { switch self {
    case .person:"person";case .group:"person.3";case .organisation:"building.2";case .place:"mappin";case .role:"person.text.rectangle";case .course:"book";case .project:"hammer";case .goal:"target";case .habit:"repeat";case .interest:"star";case .value:"heart";case .trait:"person.crop.rectangle";case .concept:"circle.dotted"
    } }
}

/// A hierarchy of areas is navigation; factual cross-links remain separately inspectable.
struct LifeNotebookMapView:View {
    var notebook:LifeNotebook
    var notes:[LifeAreaNote]
    @Binding var selectedArea:LifeArea?
    var body:some View {
        let rows=(notes.count+1)/2,height=CGFloat(90+rows*86)
        GeometryReader { geometry in
            let width=geometry.size.width,root=CGPoint(x:width/2,y:25)
            ZStack(alignment:.topLeading) {
                Canvas { context,_ in
                    for (index,note) in notes.enumerated() {
                        let point=CGPoint(x:width*(index%2 == 0 ? 0.25 : 0.75),y:CGFloat(100+(index/2)*86))
                        var path=Path();path.move(to:root);path.addCurve(to:point,control1:CGPoint(x:root.x,y:point.y-35),control2:CGPoint(x:point.x,y:point.y-35))
                        context.stroke(path,with:.color(note.area.colour.opacity(selectedArea == note.area ? 0.7 : 0.2)),lineWidth:selectedArea == note.area ? 2 : 1)
                    }
                }.accessibilityHidden(true)
                Label(notebook.selfLabel,systemImage:"person.crop.circle.fill").font(.headline).padding(.horizontal,16).padding(.vertical,9)
                    .background(.regularMaterial,in:Capsule()).position(root)
                ForEach(Array(notes.enumerated()),id:\.element.id) { index,note in
                    Button { selectedArea = selectedArea == note.area ? nil : note.area } label: {
                        VStack(spacing:4) {
                            Label(note.area.title,systemImage:note.area.symbol).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            Text("\(note.records.count) \(note.records.count == 1 ? "fact" : "facts")").font(.caption).foregroundStyle(.secondary)
                        }.frame(width:max(100,width/2-16),height:60)
                            .background(note.area.colour.opacity(selectedArea == note.area ? 0.18 : 0.07),in:RoundedRectangle(cornerRadius:12))
                            .overlay(RoundedRectangle(cornerRadius:12).stroke(note.area.colour.opacity(selectedArea == note.area ? 0.65 : 0.22)))
                    }.buttonStyle(.plain).position(x:width*(index%2 == 0 ? 0.25 : 0.75),y:CGFloat(100+(index/2)*86))
                        .accessibilityLabel("\(note.area.title), \(note.records.count) saved facts").accessibilityAddTraits(selectedArea == note.area ? .isSelected : [])
                }
            }
        }.frame(height:height)
    }
}

struct LifeNotebookAreaView:View {
    var notebook:LifeNotebook
    var note:LifeAreaNote
    var inspect:(PAMemory)->Void
    private var entities:[LifeEntity] { let ids=Set(note.records.map(\.id));return notebook.entities.filter{$0.id != LifeNotebook.selfID && $0.areas.contains(note.area) && !$0.memoryIDs.isDisjoint(with:ids)} }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Label(note.area.title,systemImage:note.area.symbol).font(.headline).foregroundStyle(note.area.colour)
            if !entities.isEmpty {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:140),alignment:.leading)],alignment:.leading,spacing:8) {
                    ForEach(Array(entities.prefix(24))) { entity in
                        Button { if let record=note.records.first(where:{entity.memoryIDs.contains($0.id)}) { inspect(record) } } label: {
                            VStack(alignment:.leading,spacing:3) {
                                Label(entity.label,systemImage:entity.kind.symbol).font(.callout.weight(.medium)).lineLimit(2)
                                Text(caption(entity)).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity,alignment:.leading).padding(9).background(note.area.colour.opacity(0.06),in:RoundedRectangle(cornerRadius:9))
                        }.buttonStyle(.plain)
                    }
                }
                if entities.count > 24 { Text("Showing 24 of \(entities.count) entities; search to narrow the view.").font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(Array(note.records.prefix(30))) { record in
                Button { inspect(record) } label: {
                    VStack(alignment:.leading,spacing:6) {
                        Text(record.text).font(.callout).frame(maxWidth:.infinity,alignment:.leading)
                        let links=notebook.links.filter{$0.memoryID == record.id}
                        ForEach(links) { link in
                            Text(label(link.from)+" → "+link.relation+" → "+label(link.to)).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing:6) {
                            if !record.explicit && record.certainty != .stated { Text("Inferred").font(.caption).foregroundStyle(.orange) }
                            ForEach((record.organisation?.areas ?? []).filter{$0 != note.area}) { area in Label(area.title,systemImage:area.symbol).font(.caption2).foregroundStyle(area.colour) }
                            if record.organisation?.manual == true { Image(systemName:"pin.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("Organisation pinned by you") }
                        }
                    }.padding(11).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                }.buttonStyle(.plain)
            }
            if note.records.count > 30 { Text("Showing 30 of \(note.records.count) facts. Search to narrow them.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func label(_ id:String)->String { id == LifeNotebook.selfID ? notebook.selfLabel : notebook.entities.first(where:{$0.id == id})?.label ?? "Saved entity" }
    private func caption(_ entity:LifeEntity)->String { if entity.kind == .person,let relation=notebook.links.first(where:{$0.to == entity.id && $0.from == LifeNotebook.selfID})?.relation { return relation.capitalized };return entity.kind.rawValue.capitalized }
}

struct LifeOrganisationEditor:View {
    @Bindable var memory:PAMemoryStore
    var record:PAMemory
    @Environment(\.dismiss) private var dismiss
    @State private var areas:Set<LifeArea>=[]
    @State private var connections:[LifeConnectionClassification]=[]
    @State private var selfName=""
    @State private var error:String?
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Organise memory").font(.title2.weight(.semibold));Spacer();Button("Done") { dismiss() } }
            Text(record.text).font(.callout).textSelection(.enabled)
            Text("Choose up to three areas. This changes how the fact is organised; its wording and evidence stay saved.").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:160),alignment:.leading)],alignment:.leading) {
                ForEach(LifeArea.allCases.filter{$0 != .unsorted}) { area in
                    Toggle(area.title,isOn:Binding(get:{areas.contains(area)},set:{ if $0 { areas.insert(area) } else { areas.remove(area) } })).disabled(!areas.contains(area) && areas.count >= 3)
                }
            }
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(Array((record.connections ?? []).enumerated()),id:\.offset) { index,link in
                        VStack(alignment:.leading,spacing:5) {
                            Text(link.subject+" → "+link.relation+" → "+link.object).font(.callout.weight(.medium))
                            endpoint(index:index,subject:true,label:link.subject)
                            endpoint(index:index,subject:false,label:link.object)
                        }
                    }
                }
            }.frame(maxHeight:220)
            if record.conversationID == nil {
                TextField("Your name, only if you stated it in this fact's evidence",text:$selfName)
                Text("Leave blank unless this fact actually says your name. A contact's name is not your identity.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Clear organisation") {
                    guard memory.records.first(where:{$0.id == record.id}) == record else { error="This memory changed. Reopen it before organising.";return }
                    if memory.setOrganisation(record.id,value:nil) { dismiss() }
                }
                Spacer();Button("Save organisation") {
                    let value=LifeMemoryOrganisation(areas:LifeArea.allCases.filter{areas.contains($0)},connections:connections,selfName:selfName.isEmpty ? nil : selfName,manual:true)
                    guard let current=memory.records.first(where:{$0.id == record.id}),current == record else { error="This memory changed. Reopen it before organising.";return }
                    if memory.setOrganisation(record.id,value:value) { dismiss() } else { error=memory.error ?? "The name or connection classification is not supported by this fact." }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width:560).onAppear {
            areas=Set(record.organisation?.areas ?? [])
            selfName=record.organisation?.selfName ?? ""
            connections=(record.connections ?? []).enumerated().map { index,link in record.organisation?.connections.first(where:{$0.connection == String(index)}) ?? .init(connection:String(index),subjectKind:LifeNotebook.firstPerson(link.subject) ? .person : .concept,objectKind:LifeNotebook.firstPerson(link.object) ? .person : .concept,subjectIsSelf:LifeNotebook.firstPerson(link.subject),objectIsSelf:LifeNotebook.firstPerson(link.object)) }
        }
    }
    @ViewBuilder private func endpoint(index:Int,subject:Bool,label:String)->some View {
        if connections.indices.contains(index) {
            HStack {
                Text(label).lineLimit(1).frame(maxWidth:160,alignment:.leading)
                Picker("Type",selection:Binding(get:{subject ? connections[index].subjectKind : connections[index].objectKind},set:{ value in
                    if subject { connections[index].subjectKind=value;if value != .person { connections[index].subjectIsSelf=false } }
                    else { connections[index].objectKind=value;if value != .person { connections[index].objectIsSelf=false } }
                })) { ForEach(LifeEntityKind.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }.labelsHidden().frame(width:130)
                Toggle("This is me",isOn:Binding(get:{subject ? connections[index].subjectIsSelf : connections[index].objectIsSelf},set:{ if subject { connections[index].subjectIsSelf=$0 } else { connections[index].objectIsSelf=$0 } }))
                    .disabled((subject ? connections[index].subjectKind : connections[index].objectKind) != .person)
            }.font(.caption)
        }
    }
}
