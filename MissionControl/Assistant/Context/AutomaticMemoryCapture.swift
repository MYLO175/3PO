import Foundation

struct AutomaticMemoryCapture:Equatable {
    var records:[[String:String]]
    var dependencies:[MemoryDependency]
    var eligibleCount:Int
    var whatsappChats:Set<String> = []
    var pageContext:String = "{}"
    var contextPageDependencies:[String:String] = [:]
    /// Feature context excludes the ordinary-chat directory, whose labels are navigation metadata.
    static func pagePayload(_ text:String)->String {
        guard var object=(try? JSONSerialization.jsonObject(with:Data(text.utf8))) as? [String:Any] else {return "{}"}
        object.removeValue(forKey:"directory");object.removeValue(forKey:"directoryCount")
        return (try? JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])).map{String(decoding:$0,as:UTF8.self)} ?? "{}"
    }
    var context:String {
        var value:[String:Any]=["savedMemory":records,"commitmentReports":CommitmentRules.context(records),"eligibleMemoryCount":eligibleCount,"selectedMemoryCount":records.count,"coverage":"At most 40 usable saved facts and 20KB, with exact evidence and certainty. Partial local retrieval, not a complete life history. Source memories additionally follow this feature's source permissions; learning permission alone never enables WhatsApp briefing or automatic suggestions."]
        if !contextPageDependencies.isEmpty,let pages=try? JSONSerialization.jsonObject(with:Data(pageContext.utf8)) {value["contextPages"]=pages}
        return (try? String(data:JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),encoding:.utf8)) ?? "{}"
    }
}
