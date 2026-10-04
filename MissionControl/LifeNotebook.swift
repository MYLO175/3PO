import Foundation

enum LifeArea:String,Codable,CaseIterable,Identifiable {
    case about, studies, career, projects, interests, wellbeing, people, home, administration, unsorted
    var id:String { rawValue }
    var title:String { switch self {
    case .about:"About me"; case .studies:"Studies"; case .career:"Career"; case .projects:"Personal projects"; case .interests:"Interests"; case .wellbeing:"Wellbeing"; case .people:"People"; case .home:"Home"; case .administration:"Administration"; case .unsorted:"Not yet organised"
    } }
    var symbol:String { switch self {
    case .about:"person.crop.circle"; case .studies:"graduationcap"; case .career:"briefcase"; case .projects:"hammer"; case .interests:"star"; case .wellbeing:"leaf"; case .people:"person.2"; case .home:"house"; case .administration:"checklist"; case .unsorted:"tray"
    } }
}
enum LifeEntityKind:String,Codable,CaseIterable {
    case person, group, organisation, place, role, course, project, goal, habit, interest, value, trait, concept
}
struct LifeConnectionClassification:Codable,Equatable {
    var connection:String
    var subjectKind:LifeEntityKind
    var objectKind:LifeEntityKind
    var subjectIsSelf:Bool
    var objectIsSelf:Bool
}
struct LifeMemoryOrganisation:Codable,Equatable {
    var areas:[LifeArea]
    var connections:[LifeConnectionClassification]
    var selfName:String?
    var manual:Bool? = nil
    static func valid(_ value:Self,record:PAMemory)->Bool {
        guard value.areas.count <= 3,Set(value.areas).count == value.areas.count,
              value.connections.count <= 4,Set(value.connections.map(\.connection)).count == value.connections.count else { return false }
        for item in value.connections {
            guard let index=Int(item.connection),(record.connections ?? []).indices.contains(index),
                  !item.subjectIsSelf || item.subjectKind == .person,!item.objectIsSelf || item.objectKind == .person else { return false }
        }
        if let name=value.selfName {
            let evidence=record.evidence ?? (record.explicit ? record.text : "")
            guard record.conversationID == nil,(1...80).contains(name.count),evidence.localizedCaseInsensitiveContains(name),record.explicit || record.certainty == .stated else { return false }
        }
        return true
    }
}
struct LifeEntity:Identifiable {
    var id:String
    var label:String
    var kind:LifeEntityKind
    var areas:Set<LifeArea>
    var memoryIDs:Set<UUID>
}
struct LifeLink:Identifiable {
    var id:String
    var from:String
    var to:String
    var relation:String
    var memoryID:UUID
    var evidence:String
    var inferred:Bool
}
struct LifeAreaNote:Identifiable {
    var area:LifeArea
    var records:[PAMemory]
    var id:String { area.rawValue }
}
struct LifeNotebook {
    var selfLabel:String
    var entities:[LifeEntity]
    var links:[LifeLink]
    var notes:[LifeAreaNote]
    var eligibleCount:Int
    static let selfID="self"
    static func key(_ label:String)->String { label.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_GB")).split(whereSeparator:{$0.isWhitespace}).joined(separator:" ") }
    static func firstPerson(_ label:String)->Bool { ["you","i","me","myself","the user","user"].contains(key(label)) }
    /// IDs are stable per permitted scope and typed identity. People never coalesce just by name.
    static func entityID(label:String,kind:LifeEntityKind,isSelf:Bool?,record:PAMemory,index:Int,endpoint:String)->String {
        if isSelf == true || (isSelf == nil && firstPerson(label)) { return selfID }
        let scope=record.conversationID?.uuidString ?? "shared"
        if kind == .person || kind == .concept { return scope+":"+record.id.uuidString+":"+String(index)+":"+endpoint }
        return scope+":"+kind.rawValue+":"+key(label)
    }
    static func build(_ records:[PAMemory],registration:String,topic:UUID? = nil,now:Date = .now)->Self {
        let permitted=records.filter { MemoryRules.usable($0,registration:registration,now:now) && MemoryRules.inScope($0,conversationID:topic) }.sorted { $0.reviewed == $1.reviewed ? $0.id.uuidString < $1.id.uuidString : $0.reviewed > $1.reviewed }
        let selfLabel=permitted.filter { $0.conversationID == nil && ($0.explicit || $0.certainty == .stated) }.compactMap { record in record.organisation.flatMap { LifeMemoryOrganisation.valid($0,record:record) ? $0.selfName : nil } }.first ?? "Me"
        var entities:[String:LifeEntity]=[:],links:[LifeLink]=[],notes:[LifeArea:[PAMemory]]=[:]
        for record in permitted {
            let organisation=record.organisation.flatMap { LifeMemoryOrganisation.valid($0,record:record) ? $0 : nil }
            let areas=Set(organisation?.areas.isEmpty == false ? organisation!.areas : [.unsorted])
            for area in areas { notes[area,default:[]].append(record) }
            for (i,connection) in (record.connections ?? []).enumerated() {
                let typed=organisation?.connections.first{$0.connection == String(i)}
                let a=typed?.subjectKind ?? (firstPerson(connection.subject) ? .person : .concept),b=typed?.objectKind ?? (firstPerson(connection.object) ? .person : .concept)
                let from=entityID(label:connection.subject,kind:a,isSelf:typed?.subjectIsSelf,record:record,index:i,endpoint:"from")
                let ownNameObject=organisation?.selfName.map{Self.key($0) == Self.key(connection.object) && from == selfID} ?? false
                let to=ownNameObject ? selfID : entityID(label:connection.object,kind:b,isSelf:typed?.objectIsSelf,record:record,index:i,endpoint:"to")
                for (id,label,kind) in [(from,connection.subject,a),(to,connection.object,b)] {
                    if entities[id] == nil { entities[id]=LifeEntity(id:id,label:id == selfID ? selfLabel : label,kind:kind,areas:[],memoryIDs:[]) }
                    entities[id]?.areas.formUnion(areas); entities[id]?.memoryIDs.insert(record.id)
                }
                if from != to { links.append(.init(id:record.id.uuidString+":"+String(i),from:from,to:to,relation:connection.relation,memoryID:record.id,evidence:connection.evidence,inferred:!record.explicit && record.certainty != .stated)) }
            }
        }
        return .init(selfLabel:selfLabel,entities:entities.values.sorted{$0.id < $1.id},links:links,notes:LifeArea.allCases.compactMap { area in notes[area].map { .init(area:area,records:$0) } },eligibleCount:permitted.count)
    }
    /// Bounded inspectable notes, derived from facts rather than an ungrounded synthetic biography.
    func context(query:String?,focus:[LifeArea] = [],maxBytes:Int = 8000)->String {
        let terms=MemoryRetrieval.tokens(query ?? "")
        func recordScore(_ record:PAMemory)->Int { MemoryRetrieval.tokens(record.text+" "+(record.connections ?? []).map{$0.subject+" "+$0.object}.joined(separator:" ")).intersection(terms).count }
        func score(_ note:LifeAreaNote)->Int {
            return (note.records.map(recordScore).max() ?? 0)*4+MemoryRetrieval.tokens(note.area.title).intersection(terms).count*4+(focus.contains(note.area) ? 5 : 0)
        }
        var included:[[String:Any]]=[]
        var value:[String:Any]=["self":selfLabel,"knownAreas":notes.map{["area":$0.area.rawValue,"count":$0.records.count] as [String:Any]},"areas":included,"coverage":"Bounded shared/current-topic saved facts. Missing areas are unexplored, not absent. Organisation is metadata, never write authorisation."]
        func encoded(_ value:[String:Any])->String { (try? String(data:JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),encoding:.utf8)) ?? "{}" }
        if encoded(value).utf8.count > maxBytes { value["knownAreas"]=[];value["coverage"]="Partial saved memory." }
        guard encoded(value).utf8.count <= maxBytes else { return maxBytes >= 2 ? "{}" : "" }
        for note in notes.sorted(by:{score($0)==score($1) ? $0.id < $1.id : score($0)>score($1)}).prefix(4) {
            let records=note.records.sorted { recordScore($0) == recordScore($1) ? ($0.reviewed == $1.reviewed ? $0.id.uuidString < $1.id.uuidString : $0.reviewed > $1.reviewed) : recordScore($0)>recordScore($1) }
            var facts:[[String:String]]=[]
            for record in records.prefix(6) {
                let fact=["id":record.id.uuidString,"text":String(record.text.prefix(500)),"certainty":record.explicit || record.certainty == .stated ? "stated" : "inferred"]
                var candidate=value
                candidate["areas"]=included+[["area":note.area.rawValue,"title":note.area.title,"facts":facts+[fact],"totalFacts":note.records.count]]
                if encoded(candidate).utf8.count <= maxBytes { facts.append(fact) }
            }
            if !facts.isEmpty { included.append(["area":note.area.rawValue,"title":note.area.title,"facts":facts,"totalFacts":note.records.count]);value["areas"]=included }
        }
        return encoded(value)
    }
}
