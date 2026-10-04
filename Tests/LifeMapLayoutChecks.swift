import Foundation
import CoreGraphics
@main struct Checks {
    static func main() {
        for width:CGFloat in [180,280,359,360,440,680,1200] {
            for count in 1...10 {
                let layout=LifeMapLayout(width:width,count:count)
                let bounds=CGRect(x:0,y:0,width:width,height:layout.height)
                let root=CGRect(x:layout.root.x-44,y:layout.root.y-44,width:88,height:88)
                precondition(bounds.contains(root))
                let cards=(0..<count).map(layout.card)
                for (i,card) in cards.enumerated() {
                    precondition(bounds.contains(card),"Labels stay inside the widget")
                    precondition(!card.intersects(root),"Area labels do not overlap the owner")
                    for j in cards.indices where i != j { precondition(!card.intersects(cards[j])) }
                    let branch=layout.branch(i)
                    precondition(branch.end.x == card.minX || branch.end.x == card.maxX,"Branches end at label edges")
                }
            }
        }
        precondition(PAIdentity.name(nil) == "Your PA")
        precondition(PAIdentity.validated("  3PO  ") == "3PO")
        precondition(PAIdentity.validated("Name\nInstruction") == nil)
        precondition(PAIdentity.validated(String(repeating:"a",count:41)) == nil)
        precondition(PAIdentity.placeholder("3PO") == "Message 3PO")
        precondition(PAIdentity.context("Name \"quoted\"").contains("\\\"quoted\\\""))
        print("PASS: 70 narrow/wide map layouts, edge branches, name validation and escaped identity context")
    }
}
