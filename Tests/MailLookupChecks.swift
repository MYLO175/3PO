import Foundation
@main struct Checks {
    static func main() throws {
        assert(MailLookupRules.requested("Find Alice's email from September"))
        assert(MailLookupRules.requested("What did the old email about the course say?"))
        assert(MailLookupRules.requested("Continue the email search."))
        assert(!MailLookupRules.requested("What is going on today?"))
        let plan = MailLookupPlan(message:"",terms:["Alice","Course"],start:"2026-09-01",end:"2026-10-01")
        let terms = try MailLookupRules.terms(plan,request:"Find Alice's Course email from September")
        assert(terms == ["Alice","Course"])
        let raw = #"{"id":"test:1","accountID":"test","account":"Test","messageID":1,"internetMessageID":"fake@example.invalid","sender":"ALICE@example.invalid","subject":"Private invitation","received":"2026-09-15T12:00:00Z","unread":true,"replied":false,"flagged":false}"#
        let message = try JSONDecoder().decode(MailMessage.self,from:Data(raw.utf8))
        assert(MailLookupRules.matches(message,terms:terms))
        assert(!MailLookupRules.matches(message,terms:["Unrelated"]))
        for bad in [MailLookupPlan(message:"",terms:["invented"],start:nil,end:nil),MailLookupPlan(message:"",terms:["email"],start:nil,end:nil),MailLookupPlan(message:"",terms:[],start:nil,end:nil)] {
            var failed = false
            do { _ = try MailLookupRules.terms(bad,request:"Find Alice's email") } catch { failed = true }
            assert(failed)
        }
        print("PASS: mail-specific request routing, literal meaningful terms, case-insensitive sender/subject matches, unknown/generic terms rejected")
    }
}
