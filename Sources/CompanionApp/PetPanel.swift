import AppKit
import CompanionCore
final class FloatingPanel:NSPanel {
 override var canBecomeKey:Bool {true}
 override var canBecomeMain:Bool {false}
}
final class PetView:NSView {
 var clicked:(()->Void)?;var moved:(()->Void)?;var row=0;var frameIndex=0;var dragged=false;var badge=""
 let sheet:NSImage? = NSImage(contentsOf:(Bundle.main.url(forResource:"sprites",withExtension:"png",subdirectory:"Pet") ?? Bundle.module.url(forResource:"sprites",withExtension:"png",subdirectory:"Resources/Pet"))!)
 override func draw(_ dirtyRect:NSRect) {
 guard let sheet,let cg=sheet.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return}
 let w=cg.width/4,h=cg.height/4
 if let crop=cg.cropping(to:CGRect(x:frameIndex*w,y:row*h,width:w,height:h)) {
 NSGraphicsContext.current?.imageInterpolation = .none
 NSImage(cgImage:crop,size:NSSize(width:w,height:h)).draw(in:NSRect(x:7,y:17,width:116,height:116))
 let badgeRect=NSRect(x:0,y:0,width:130,height:19);NSColor.black.withAlphaComponent(0.75).setFill();NSBezierPath(roundedRect:badgeRect,xRadius:9,yRadius:9).fill()
 let style=NSMutableParagraphStyle();style.alignment = .center
 (badge as NSString).draw(in:NSRect(x:2,y:2,width:126,height:15),withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.medium),.foregroundColor:NSColor.white,.paragraphStyle:style])
 }
 }
 override func mouseDown(with event:NSEvent) {dragged=false}
 override func mouseDragged(with event:NSEvent) {guard let window else{return};dragged=true;window.setFrameOrigin(NSPoint(x:window.frame.minX+event.deltaX,y:window.frame.minY-event.deltaY));moved?()}
 override func mouseUp(with event:NSEvent) {if !dragged {clicked?()}}
}
final class NotificationCard:NSVisualEffectView {
 var open:(()->Void)?;var dismiss:(()->Void)?
 init(notice:Notice,frame:NSRect) {
 super.init(frame:frame);material = .hudWindow;blendingMode = .behindWindow;state = .active;wantsLayer=true;layer?.cornerRadius=35;layer?.borderWidth=1;layer?.borderColor=NSColor.white.withAlphaComponent(0.14).cgColor;appearance=NSAppearance(named:.darkAqua)
 let icon=NSTextField(labelWithString:notice.needsInput ? "●" : "✓");icon.textColor=notice.needsInput ? .systemOrange:.systemGreen;icon.font = .boldSystemFont(ofSize:20);icon.frame=NSRect(x:18,y:35,width:22,height:26);addSubview(icon)
 let title=NSTextField(labelWithString:notice.title);title.font = .boldSystemFont(ofSize:15);title.textColor = .white;title.lineBreakMode = .byTruncatingTail;title.frame=NSRect(x:43,y:38,width:frame.width-88,height:22);addSubview(title)
 let preview=NSTextField(labelWithString:notice.message.replacingOccurrences(of:"\n",with:" "));preview.font = .systemFont(ofSize:14);preview.textColor = .secondaryLabelColor;preview.lineBreakMode = .byTruncatingTail;preview.frame=NSRect(x:20,y:15,width:frame.width-45,height:22);addSubview(preview)
 let close=NSButton(title:"×",target:self,action:#selector(closeCard));close.isBordered=false;close.font = .systemFont(ofSize:20);close.contentTintColor = .secondaryLabelColor;close.frame=NSRect(x:frame.width-35,y:36,width:25,height:25);close.toolTip="Dismiss notification";close.setAccessibilityLabel("Dismiss notification");addSubview(close)
 }
 required init?(coder:NSCoder){fatalError()}
 override func mouseUp(with event:NSEvent){open?()}
 @objc func closeCard(){dismiss?()}
}
final class PetPanel {
 let petPanel:FloatingPanel;let pet=PetView(frame:NSRect(x:0,y:0,width:130,height:130));var cards:[FloatingPanel]=[];var signature=""
 var onOpen:((Notice)->Void)?;var onDismiss:((UUID)->Void)?
 init() {
 petPanel=FloatingPanel(contentRect:pet.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
 configure(petPanel);petPanel.contentView=pet
 let defaults=UserDefaults.standard;let screen=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1200,height:800)
 let point=defaults.object(forKey:"petX") != nil ? NSPoint(x:defaults.double(forKey:"petX"),y:defaults.double(forKey:"petY")):NSPoint(x:screen.maxX-160,y:screen.minY+45)
 petPanel.setFrameOrigin(point);clamp();petPanel.orderFrontRegardless()
 pet.moved={[weak self] in self?.clamp();self?.positionCards();guard let self else{return};defaults.set(self.petPanel.frame.minX,forKey:"petX");defaults.set(self.petPanel.frame.minY,forKey:"petY")}
 }
 func configure(_ p:NSPanel){p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.level = .floating;p.hidesOnDeactivate=false;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];p.isReleasedWhenClosed=false}
 var availableCount:Int {let s=petPanel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame;return max(1,Int((s.height-155)/86))}
 func clamp(){let s=petPanel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame;let f=petPanel.frame;petPanel.setFrameOrigin(NSPoint(x:min(max(f.minX,s.minX),s.maxX-f.width),y:min(max(f.minY,s.minY),s.maxY-f.height)))}
 func positionCards(){let screen=petPanel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
 let layout=PanelLayout(screen:screen,petOrigin:petPanel.frame.origin,count:cards.count)
 petPanel.setFrame(layout.pet,display:true)
 for (p,rect) in zip(cards,layout.cards) {p.setFrame(rect,display:true)}
 }
 func render(_ notices:[Notice],state:Int){pet.row=state
 let key=notices.map{$0.id.uuidString}.joined();guard key != signature else{return};signature=key
 cards.forEach{$0.close()};cards=[]
 for n in notices {
 let panel=FloatingPanel(contentRect:NSRect(x:0,y:0,width:430,height:76),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false);configure(panel)
 let card=NotificationCard(notice:n,frame:NSRect(x:0,y:0,width:430,height:76));card.open={[weak self] in self?.onOpen?(n)};card.dismiss={[weak self] in self?.onDismiss?(n.id)};panel.contentView=card;cards.append(panel)
 };positionCards();if petPanel.isVisible {cards.forEach{$0.orderFrontRegardless()}}
 }
 func animate(){pet.frameIndex=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0:(pet.frameIndex+1)%4;pet.needsDisplay=true}
 func setVisible(_ show:Bool){if show {petPanel.orderFrontRegardless();cards.forEach{$0.orderFrontRegardless()}} else {petPanel.orderOut(nil);cards.forEach{$0.orderOut(nil)}}}
}
