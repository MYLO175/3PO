import Foundation
import CoreFoundation

/// A completed preparation result only. This tool never executes source or workspace actions.
enum ProactiveResultRules {
    static let toolName = "prepare_review"
    static let maximumArgumentBytes = 32_000
    static let instructions = "Return the finished comparison by calling pa.prepare_review exactly once. Do not answer in ordinary text or call any other tool. Return suggestions, handled and resolved arrays, using empty arrays when there is no supported result. This tool returns preparation data only: it does not create, change, complete, dismiss or send anything. Use null for inapplicable optional fields. Respect each action kind's fields: connection belongs only to projectTask/change/remove; targetID only to change/remove; scope only to remove; draft only to WhatsApp reply; projectID only to projectTask. Preserve all exact evidence, action, date and ownership rules. Keep the entire result below 32000 UTF-8 bytes by using concise messages and evidence IDs instead of repeating Mail quotes. Return at most 24 suggestions, 12 handled and 12 resolved associations; do not repeat proposals. Local validation remains authoritative."

    static func tools(sourceAliases:Set<String>, evidenceAliases:Set<String>, nativeAliases:Set<String>, projectAliases:Set<String>, earlierAliases:Set<String>, confirmationAliases:Set<String>) -> [[String:Any]] {
        func text(_ limit:Int,nullable:Bool = false)->[String:Any] { ["type":nullable ? ["string","null"] : ["string"],"maxLength":limit] }
        func aliases(_ values:Set<String>,nullable:Bool = false)->[String:Any] {
            var choices:[Any]=values.sorted()
            if nullable { choices.append(NSNull()) }
            // Empty non-null alias sets cannot be selected; their containing array is bounded to zero.
            if choices.isEmpty { choices=[""] }
            return ["type":nullable ? ["string","null"] : ["string"],"enum":choices]
        }
        func object(_ fields:[String:[String:Any]])->[String:Any] {
            ["type":"object","properties":fields,"required":fields.keys.sorted(),"additionalProperties":false]
        }
        let suggestion=object([
            "mailID":aliases(sourceAliases),
            "kind":["type":"string","enum":["calendar","reminder","update","project","projectTask","change","remove","reply"]],
            "message":text(700,nullable:true),"evidence":text(500,nullable:true),"evidenceID":aliases(evidenceAliases,nullable:true),
            "title":text(300,nullable:true),"targetID":aliases(nativeAliases,nullable:true),"newDate":text(40,nullable:true),
            "hasTime":["type":["boolean","null"]],"connection":text(500,nullable:true),"draft":text(3000,nullable:true),
            "replaces":["type":["array","null"],"maxItems":earlierAliases.isEmpty ? 0 : 3,"items":aliases(earlierAliases)],
            "replacementReason":text(500,nullable:true),"scope":["type":["string","null"],"enum":["occurrence",NSNull()]],
            "endDate":text(40,nullable:true),"projectID":aliases(projectAliases,nullable:true)
        ])
        let mail=Set(sourceAliases.filter{$0.hasPrefix("mail_")})
        let primary=Set(evidenceAliases.filter{$0.hasSuffix(":primary")})
        let handled=object(["mailID":aliases(mail),"targetID":aliases(nativeAliases),"reason":text(500),"requestEvidenceID":aliases(primary),"allActionsAddressed":["type":"boolean","enum":[true]]])
        let resolved=object(["mailID":aliases(mail),"confirmationID":aliases(confirmationAliases),"requestEvidenceID":aliases(primary),"confirmationEvidenceID":aliases(Set(confirmationAliases.map{$0+":primary"})),"allActionsAddressed":["type":"boolean","enum":[true]],"reason":text(500)])
        let parameters=object([
            "suggestions":["type":"array","maxItems":sourceAliases.isEmpty ? 0 : 24,"items":suggestion],
            "handled":["type":"array","maxItems":mail.isEmpty || nativeAliases.isEmpty ? 0 : 12,"items":handled],
            "resolved":["type":"array","maxItems":mail.isEmpty || confirmationAliases.isEmpty ? 0 : 12,"items":resolved]
        ])
        return [["type":"namespace","name":"pa","description":"Return a source-grounded review preparation; no reads, saves or other actions.","tools":[["type":"function","name":toolName,"description":"Return separately reviewable suggestions and strictly supported existing-plan/completion associations.","strict":true,"parameters":parameters]]]]
    }

    /// Callers pass only the transport's completed calls, never partial argument deltas.
    static func completedJSON(_ calls:[(namespace:String?,name:String,arguments:String)]) throws -> String {
        guard !calls.isEmpty else {throw ReviewResultDiagnostic(section:.result,field:.tool,reason:.missingCompletedCall)}
        guard calls.count == 1 else {throw ReviewResultDiagnostic(section:.result,field:.tool,reason:.unexpectedCallCount)}
        let call=calls[0]
        guard (call.namespace == "pa" && call.name == toolName) || (call.namespace == nil && call.name == "pa."+toolName) else {throw ReviewResultDiagnostic(section:.result,field:.tool,reason:.unexpectedTool)}
        try validateEnvelope(call.arguments)
        return call.arguments
    }

    /// Structural checks diagnose association fields before their semantic validators run.
    /// Unknown keys and values never become diagnostic text or stored model fragments.
    static func validateEnvelope(_ text:String) throws {
        guard text.utf8.count <= maximumArgumentBytes else {throw ReviewResultDiagnostic(section:.result,field:.arguments,reason:.oversizedArguments)}
        let raw:Any
        do {raw=try JSONSerialization.jsonObject(with:Data(text.utf8))}
        catch {throw ReviewResultDiagnostic(section:.result,field:.envelope,reason:.malformedJSON)}
        guard let object=raw as? [String:Any] else {throw ReviewResultDiagnostic(section:.result,field:.envelope,reason:.wrongType)}
        guard Set(object.keys).isSubset(of:["suggestions","handled","resolved"]) else {throw ReviewResultDiagnostic(section:.result,field:.envelope,reason:.unsupportedField)}
        for section in [ReviewResultDiagnostic.Section.suggestions,.handled,.resolved] {
            guard let value=object[section.rawValue] else {throw ReviewResultDiagnostic(section:section,field:.envelope,reason:.missingField)}
            guard let rows=value as? [Any] else {throw ReviewResultDiagnostic(section:section,field:.envelope,reason:.wrongType)}
            guard rows.count <= (section == .suggestions ? 24 : 12) else {throw ReviewResultDiagnostic(section:section,field:.envelope,reason:.tooManyRows)}
            let required:Set<String>,allowed:Set<String>
            switch section {
            case .suggestions:
                required=["mailID","kind"]
                allowed=["mailID","kind","message","evidence","evidenceID","title","targetID","newDate","hasTime","connection","draft","replaces","replacementReason","scope","endDate","projectID"]
            case .handled:
                required=["mailID","targetID","reason","requestEvidenceID","allActionsAddressed"];allowed=required
            case .resolved:
                required=["mailID","confirmationID","requestEvidenceID","confirmationEvidenceID","allActionsAddressed","reason"];allowed=required
            case .result:preconditionFailure("Result is not a row section")
            }
            for (index,value) in rows.enumerated() {
                func issue(_ field:ReviewResultDiagnostic.Field,_ reason:ReviewResultDiagnostic.Reason)->ReviewResultDiagnostic {.init(section:section,row:index,field:field,reason:reason)}
                guard let row=value as? [String:Any] else {throw issue(.envelope,.wrongType)}
                guard Set(row.keys).isSubset(of:allowed) else {throw issue(.envelope,.unsupportedField)}
                for key in required.sorted() where row[key] == nil || row[key] is NSNull {throw issue(ReviewResultDiagnostic.Field(rawValue:key) ?? .envelope,.missingField)}
                for key in row.keys.sorted() {
                    let field=ReviewResultDiagnostic.Field(rawValue:key) ?? .envelope
                    let value=row[key]!
                    if value is NSNull {continue}
                    if key == "hasTime" || key == "allActionsAddressed" {
                        guard let number=value as? NSNumber,CFGetTypeID(number) == CFBooleanGetTypeID() else {throw issue(field,.wrongType)}
                    } else if key == "replaces" {
                        guard let strings=value as? [String] else {throw issue(field,.wrongType)}
                        guard strings.count <= 3 else {throw issue(field,.tooManyRows)}
                    } else {
                        guard value is String else {throw issue(field,.wrongType)}
                    }
                }
            }
        }
    }
}
