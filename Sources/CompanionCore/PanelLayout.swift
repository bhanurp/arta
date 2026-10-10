import Foundation
import CoreGraphics
public struct PanelLayout {
 public var pet:CGRect;public var cards:[CGRect]
 public init(screen:CGRect,petOrigin:CGPoint,count:Int){
 let capacity=max(0,Int((screen.height-155)/86));let actual=min(max(0,count),capacity);let total=CGFloat(actual)*86
 let x=min(max(petOrigin.x,screen.minX),screen.maxX-130);let y=min(max(petOrigin.y,screen.minY),screen.maxY-130-total-8)
 pet=CGRect(x:x,y:max(screen.minY,y),width:130,height:130)
 let width=min(430,screen.width);let cardX=min(max(pet.maxX-width,screen.minX),screen.maxX-width)
 cards=[];cards=(0..<actual).map{CGRect(x:cardX,y:pet.maxY+8+CGFloat(actual-1-$0)*86,width:width,height:76)}
 }
}
