import Foundation
import CryptoKit

/// Exact supplied input receipts; store revisions and newly collected unrelated
/// rows are not dependencies of an already running Review inference.
enum ReviewInferenceGuard {
    static func fingerprint<T:Encodable>(_ value:T)->String {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return SHA256.hash(data:(try? encoder.encode(value)) ?? Data()).map{String(format:"%02x",$0)}.joined()
    }
    static func available(_ captured:[String:String],current:[String:String])->Bool {
        captured.allSatisfy{current[$0.key] == $0.value}
    }
    /// Native absence/duplicate reasoning uses the whole admitted bounded set:
    /// a newly admitted row matters, whereas an excluded or after-cap row does not.
    static func nativeAvailable(_ captured:[String:String],current:[String:String])->Bool {captured == current}
    /// Read/unread, flags, account display labels and mailbox placement do not
    /// change fetched source text or its ownership. Reply state remains relevant.
    static func mailSource(_ message:MailMessage)->String {
        fingerprint([message.id,message.accountID,String(message.messageID),message.internetMessageID,message.sender,message.subject,message.received.ISO8601Format(),String(message.replied)] + (message.recipients ?? []))
    }
    static func nativeRows(calendar:CalendarSnapshot,reminders:ReminderSnapshot,completed:[CompletedReminder],excludedCalendars:Set<String>,excludedLists:Set<String>)->[String:String] {
        var result:[String:String]=[:]
        for item in calendar.events where !excludedCalendars.contains(item.calendarID) {
            result["event:"+item.id]=fingerprint([fingerprint(item),String(calendar.sources.first{$0.id == item.calendarID}?.writable == true)])
        }
        for item in reminders.reminders where !excludedLists.contains(item.listID) {result["reminder:"+item.id]=fingerprint(item)}
        for item in completed where !excludedLists.contains(item.item.listID) {result["completed:"+item.item.id]=fingerprint(item)}
        return result
    }
}
