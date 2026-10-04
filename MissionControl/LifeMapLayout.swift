import Foundation
import CoreGraphics

/// Stable bilateral hubs keep labels clear while the widget continuously resizes.
struct LifeMapLayout {
    let width:CGFloat
    let count:Int
    var compact:Bool { width < 360 }
    var cardWidth:CGFloat { compact ? max(80,width-46) : min(190,(width-112)/2) }
    var height:CGFloat { compact ? CGFloat(100+count*92) : CGFloat(max(280,((count+1)/2)*100+40)) }
    var root:CGPoint { CGPoint(x:width/2,y:compact ? 48 : height/2) }
    func card(_ index:Int)->CGRect {
        if compact { return CGRect(x:38,y:CGFloat(100+index*92),width:cardWidth,height:72) }
        let side=index%2,rows=(count+1-side)/2
        let y=(height-CGFloat(rows-1)*100)/2+CGFloat(index/2)*100
        return CGRect(x:side == 0 ? 4 : width-cardWidth-4,y:y-36,width:cardWidth,height:72)
    }
    func branch(_ index:Int)->(start:CGPoint,end:CGPoint,control1:CGPoint,control2:CGPoint) {
        let rect=card(index)
        if compact {
            let start=CGPoint(x:18,y:rect.midY),end=CGPoint(x:rect.minX,y:rect.midY)
            return (start,end,start,end)
        }
        let left=index%2 == 0
        let start=CGPoint(x:root.x+(left ? -44 : 44),y:root.y),end=CGPoint(x:left ? rect.maxX : rect.minX,y:rect.midY)
        let x=(start.x+end.x)/2
        return (start,end,CGPoint(x:x,y:start.y),CGPoint(x:x,y:end.y))
    }
}
