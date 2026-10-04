import Foundation
import SwiftData
@main struct Checks {
    @MainActor static func main() throws {
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let queue=PARequestQueue(container:container),topic=UUID()
        precondition(queue.add(registration:"one",topicID:topic,prompt:"Move my reminder to Monday"))
        precondition(queue.add(registration:"two",topicID:nil,prompt:"Other account"))
        precondition(queue.add(registration:"one",topicID:nil,prompt:"Second task"))
        let first=queue.items[0]
        precondition(PAQueueRules.next(queue.items,registration:"one")?.id == first.id)
        precondition(queue.mark(first.id,.running))
        let reload=PARequestQueue(container:container)
        precondition(reload.items[0].state == .interrupted && reload.items[0].topicID == topic)
        precondition(PAQueueRules.next(reload.items,registration:"one")?.prompt == "Second task")
        precondition(PAQueueRules.next(reload.items,registration:"two")?.prompt == "Other account")
        precondition(reload.remove(first.id))
        precondition(PARequestQueue(container:container).items.count == 2)
        precondition(!PARequestQueue(container:nil).add(registration:"one",topicID:nil,prompt:"Keep my draft"))
        precondition(!reload.add(registration:"",topicID:nil,prompt:"invalid"))
        precondition(!reload.add(registration:"one",topicID:nil,prompt:"  "))
        for i in 0..<19 { precondition(reload.add(registration:"one",topicID:nil,prompt:"Task \(i)")) }
        precondition(!reload.add(registration:"one",topicID:nil,prompt:"over limit"))
        print("PASS: queue persistence, captured topic/account, FIFO, interrupted no-replay state, removal, unavailable storage and bounded admission")
    }
}
