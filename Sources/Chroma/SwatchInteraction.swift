import AppKit
import SwiftUI
import DroppyKit

/// Internal mouse tracking stays independent of the host's pasteboard drop routing.
struct NativeSwatchInteraction:NSViewRepresentable {
    let model:ChromaDroplet
    let color:HexColor?
    let dropEnabled:Bool
    let target:HexColor?
    let onTarget:(Bool)->Void
    var makeMenu:(()->NSMenu)?=nil
    var section:SwatchKind = .pinned
    var vertical=false
    var togglesPin=false
    func makeNSView(context:Context)->NativeSwatchView { NativeSwatchView(frame:.zero) }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:NativeSwatchView,context:Context)->CGSize? {
        CGSize(width:proposal.width ?? 0,height:proposal.height ?? 0)
    }
    func updateNSView(_ view:NativeSwatchView,context:Context) {
        view.model=model; view.color=color; view.targetColor=target
        view.onTarget=onTarget; view.makeMenu=makeMenu; view.section=section; view.vertical=vertical; view.togglesPin=togglesPin
        if dropEnabled {
            if view.registeredDraggedTypes != [.string] { view.registerForDraggedTypes([.string]) }
        } else if !view.registeredDraggedTypes.isEmpty { view.unregisterDraggedTypes() }
    }
}

@MainActor
final class NativeSwatchView:NSView {
    var model:ChromaDroplet?
    var color:HexColor?
    var targetColor:HexColor?
    var section:SwatchKind = .pinned
    var vertical=false
    var togglesPin=false
    var onTarget:((Bool)->Void)?
    var makeMenu:(()->NSMenu)?
    private var pressPoint:NSPoint?
    private var dragging=false
    private weak var dragWindow:NSWindow?
    private weak var canvas:SwatchDragCanvas?
    private var baseline:ColorLibrary?
    private var dragPreview:SwatchDragPreview?
    private var monitor:Any?
    private var observers:[NSObjectProtocol]=[]
    private var cursorPushed=false
    private weak var priorResponder:NSResponder?
    private var pickupOffset=NSPoint.zero
    private var originFrame=NSRect.zero
    private var sourceSection:SwatchKind = .pinned
    private struct Destination:Equatable {
        let section:SwatchKind
        let color:HexColor?
        let after:Bool
    }
    private var destination:Destination?
    @MainActor private struct Anchor {
        let view:NativeSwatchView
        let frame:NSRect
        let section:SwatchKind
        let color:HexColor?
        let vertical:Bool
        let clip:NSClipView?
        let clipOrigin:NSPoint
        var currentFrame:NSRect {
            guard let clip else { return frame }
            let point=clip.convert(NSPoint.zero,to:nil)
            return frame.offsetBy(dx:point.x-clipOrigin.x,dy:point.y-clipOrigin.y)
        }
        func contains(_ point:NSPoint)->Bool {
            currentFrame.contains(point) && (clip.map { $0.convert($0.bounds,to:nil).contains(point) } ?? true)
        }
    }
    private var anchors:[Anchor]=[]
    override var mouseDownCanMoveWindow:Bool { false }
    override var acceptsFirstResponder:Bool { true }
    override func cancelOperation(_ sender:Any?) { cancelInternalDrag() }
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }
    override func mouseDown(with event:NSEvent) {
        pressPoint=convert(event.locationInWindow,from:nil)
    }
    override func mouseDragged(with event:NSEvent) {
        guard let pressPoint else { return }
        let point=convert(event.locationInWindow,from:nil)
        if !dragging {
            guard hypot(point.x-pressPoint.x,point.y-pressPoint.y)>=4 else { return }
            beginInternalDrag(trackEvents:true)
        }
        updateInternalDrag(at:event.locationInWindow)
    }
    private func views(in view:NSView)->[NativeSwatchView] {
        view.subviews.flatMap { views(in:$0) } + ((view as? NativeSwatchView).map { [$0] } ?? [])
    }
    func beginInternalDrag(trackEvents:Bool=false) {
        guard !dragging,let color,let model,let window,let container=window.contentView else { return }
        model.cancelSwatchDrag?()
        dragging=true; dragWindow=window; baseline=model.library; sourceSection=section
        pickupOffset=pressPoint ?? NSPoint(x:bounds.midX,y:bounds.midY)
        func canvases(_ view:NSView)->[SwatchDragCanvas] {
            view.subviews.flatMap(canvases) + ((view as? SwatchDragCanvas).map { [$0] } ?? [])
        }
        guard let canvas=canvases(container).first(where:{$0.model === model && $0.bounds.contains($0.convert(NSPoint(x:bounds.midX,y:bounds.midY),from:self))}) else {
            dragging=false; return
        }
        self.canvas=canvas
        originFrame=canvas.convert(bounds,from:self)
        // Keep stable insertion anchors while the displayed grid shifts under the pointer.
        anchors=views(in:container).filter {
            $0.model === model && !$0.registeredDraggedTypes.isEmpty && !$0.isHiddenOrHasHiddenAncestor
        }.map { view in
            var ancestor=view.superview
            while ancestor != nil && !(ancestor is NSClipView) { ancestor=ancestor?.superview }
            let clip=ancestor as? NSClipView
            return Anchor(view:view,frame:view.convert(view.bounds,to:nil),section:view.togglesPin ? (sourceSection == .pinned ? .recent:.pinned):view.section,color:view.targetColor,vertical:view.vertical,clip:clip,clipOrigin:clip?.convert(NSPoint.zero,to:nil) ?? .zero)
        }
        let preview=SwatchDragPreview(frame:originFrame)
        preview.imageScaling = .scaleAxesIndependently
        do {
            let rect=container.convert(bounds,from:self)
            if let bitmap=container.bitmapImageRepForCachingDisplay(in:rect) {
                container.cacheDisplay(in:rect,to:bitmap)
                let image=NSImage(size:bounds.size); image.addRepresentation(bitmap); preview.image=image
            }
        }
        preview.wantsLayer=true
        preview.layer?.shadowColor=NSColor.black.cgColor
        preview.layer?.shadowOpacity=0.3
        preview.layer?.shadowRadius=5
        preview.layer?.shadowOffset=CGSize(width:0,height:-2)
        canvas.addSubview(preview,positioned:.above,relativeTo:nil)
        dragPreview=preview
        springScale(preview,from:1,to:1.035)
        model.draggedColor=color
        model.draggedFrom=sourceSection
        model.host?.shelf.setHoldsOpen(true)
        model.cancelSwatchDrag={ [weak self] in self?.cancelInternalDrag() }
        if trackEvents {
            NSCursor.closedHand.push(); cursorPushed=true
            priorResponder=window.firstResponder
            window.makeFirstResponder(self)
            // The source can change sections while dragging. Track the gesture until release
            // even when SwiftUI remounts its original swatch view.
            monitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDragged,.leftMouseUp,.keyDown]) { [self] event in
                if event.type == .keyDown {
                    if event.keyCode==53 { cancelInternalDrag(); return nil }
                    return event
                }
                let point=dragWindow?.convertPoint(fromScreen:NSEvent.mouseLocation) ?? event.locationInWindow
                updateInternalDrag(at:point)
                if event.type == .leftMouseUp { finishInternalDrag() }
                return nil
            }
            for name in [NSApplication.didResignActiveNotification,NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName:name,object:name == NSWindow.willCloseNotification ? window:nil,queue:.main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelInternalDrag() }
                })
            }
        }
    }
    /// Cursor motion is immediate; only pickup, grid changes and settling are animated.
    func updateInternalDrag(at point:NSPoint) {
        if !dragging { beginInternalDrag() }
        guard dragging,let canvas else { return }
        if let preview=dragPreview {
            let local=canvas.convert(point,from:nil)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            preview.setFrameOrigin(NSPoint(x:local.x-pickupOffset.x,y:local.y-pickupOffset.y))
            CATransaction.commit()
        }
        let candidates=anchors.filter { $0.contains(point) }
        var next:Destination?
        var hit=candidates.first(where:{$0.color != nil}) ?? candidates.first
        if let section=hit,section.color==nil {
            let tiles=anchors.filter { $0.section==section.section && $0.color != nil }
            let grid=tiles.reduce(NSRect.null) { $0.union($1.currentFrame) }.insetBy(dx:-6,dy:-6)
            if grid.contains(point) {
                hit=tiles.min { a,b in
                    hypot(a.currentFrame.midX-point.x,a.currentFrame.midY-point.y)<hypot(b.currentFrame.midX-point.x,b.currentFrame.midY-point.y)
                }
            }
        }
        if let hit {
            let after=hit.vertical ? point.y<hit.currentFrame.midY:point.x>hit.currentFrame.midX
            next=Destination(section:hit.section,color:hit.color,after:after)
        }
        guard next != destination else { return }
        anchors.forEach { $0.view.onTarget?(false) }
        destination=next
        if let next,let baseline,let color,let model {
            // Dropping on the dragged color itself is a stable no-op.
            var projected=baseline
            if next.color != color || next.section != sourceSection {
                projected.moveSwatch(color,from:sourceSection,to:next.section,relativeTo:next.color,after:next.after)
            }
            withAnimation(DroppyAnimation.listChange) { model.dragLibrary=projected }
            anchors.first(where:{$0.section==next.section && $0.color==nil})?.view.onTarget?(true)
        } else if let model {
            withAnimation(DroppyAnimation.listChange) { model.dragLibrary=nil }
        }
    }
    @discardableResult func finishInternalDrag()->Bool {
        guard dragging else { return false }
        let accepted=destination != nil
        if let color,let destination,let model, (destination.color != color || destination.section != sourceSection) {
            model.mutate { $0.moveSwatch(color,from:sourceSection,to:destination.section,relativeTo:destination.color,after:destination.after) }
        }
        settle(accepted:accepted)
        return accepted
    }
    func cancelInternalDrag() { guard dragging else { return }; settle(accepted:false) }
    private func settle(accepted:Bool) {
        let window=dragWindow
        let canvas=canvas
        let endSection=destination?.section
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor=nil
        observers.forEach(NotificationCenter.default.removeObserver); observers=[]
        anchors.forEach { $0.view.onTarget?(false) }; anchors=[]
        if cursorPushed { NSCursor.pop(); cursorPushed=false }
        if window?.firstResponder === self { window?.makeFirstResponder(priorResponder) }
        priorResponder=nil
        if let model {
            withAnimation(DroppyAnimation.listChange) { model.dragLibrary=nil; model.draggedColor=nil; model.draggedFrom=nil }
            model.cancelSwatchDrag=nil; model.host?.shelf.setHoldsOpen(false)
        }
        if let preview=dragPreview {
            var target=accepted ? preview.frame:originFrame
            if accepted,let container=window?.contentView,
               let tile=views(in:container).first(where:{$0.color==color && $0.section==endSection}) {
                target=canvas?.convert(tile.bounds,from:tile) ?? originFrame
            }
            springScale(preview,from:1.035,to:1)
            NSAnimationContext.runAnimationGroup { context in
                context.duration=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08:0.18; context.timingFunction=CAMediaTimingFunction(name:.easeOut)
                preview.animator().frame=target
                preview.animator().alphaValue=0
            } completionHandler: { Task { @MainActor in preview.removeFromSuperview() } }
        }
        dragPreview=nil; destination=nil; baseline=nil; dragWindow=nil; self.canvas=nil
        pressPoint=nil; dragging=false
    }
    private func springScale(_ view:NSView,from:CGFloat,to:CGFloat) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let animation=CASpringAnimation(keyPath:"transform.scale")
        animation.fromValue=from; animation.toValue=to
        animation.mass=1; animation.stiffness=320; animation.damping=32
        animation.duration=0.22
        view.layer?.setAffineTransform(CGAffineTransform(scaleX:to,y:to))
        view.layer?.add(animation,forKey:"pickup")
    }
    override func mouseUp(with event:NSEvent) {
        if dragging { updateInternalDrag(at:event.locationInWindow); finishInternalDrag() }
        else if pressPoint != nil,let color,bounds.contains(convert(event.locationInWindow,from:nil)) { model?.select(color) }
        pressPoint=nil
    }
    override func menu(for event:NSEvent)->NSMenu? { makeMenu?() }
    override func draggingEntered(_ sender:any NSDraggingInfo)->NSDragOperation {
        guard sender.draggingPasteboard.string(forType:.string).flatMap(HexColor.init) != nil else { return [] }
        onTarget?(true); return .copy
    }
    override func draggingUpdated(_ sender:any NSDraggingInfo)->NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender:(any NSDraggingInfo)?) { onTarget?(false) }
    override func prepareForDragOperation(_ sender:any NSDraggingInfo)->Bool {
        sender.draggingPasteboard.string(forType:.string).flatMap(HexColor.init) != nil
    }
    override func performDragOperation(_ sender:any NSDraggingInfo)->Bool { onTarget?(false); return receive(sender.draggingPasteboard) }
    @discardableResult func receive(_ pasteboard:NSPasteboard)->Bool {
        guard let value=pasteboard.string(forType:.string),let color=HexColor(value),let model else { return false }
        model.mutate { $0.moveSwatch(color,from:.recent,to:section,relativeTo:targetColor) }; return true
    }
}

@MainActor
final class SwatchMenuItem:NSMenuItem {
    private let perform:()->Void
    init(title:String,perform:@escaping()->Void) {
        self.perform=perform
        super.init(title:title,action:#selector(run),keyEquivalent:"")
        target=self
    }
    required init(coder:NSCoder) { fatalError("Not used") }
    @objc private func run() { perform() }
}

@MainActor
private final class SwatchDragPreview:NSView {
    private let artwork=NSImageView(frame:.zero)
    var image:NSImage? { get { artwork.image } set { artwork.image=newValue } }
    var imageScaling:NSImageScaling { get { artwork.imageScaling } set { artwork.imageScaling=newValue } }
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer=true
        artwork.frame=bounds
        artwork.autoresizingMask=[.width,.height]
        artwork.wantsLayer=true
        artwork.layer?.cornerRadius=DroppyRadius.small
        artwork.layer?.masksToBounds=true
        addSubview(artwork)
        updateShadowPath()
    }
    required init?(coder:NSCoder) { nil }
    override func layout() { super.layout(); updateShadowPath() }
    private func updateShadowPath() {
        layer?.shadowPath=CGPath(roundedRect:bounds,cornerWidth:DroppyRadius.small,cornerHeight:DroppyRadius.small,transform:nil)
    }
    override func hitTest(_ point:NSPoint)->NSView? { nil }
}

struct NativeSwatchCanvas:NSViewRepresentable {
    let model:ChromaDroplet
    func makeNSView(context:Context)->SwatchDragCanvas {
        let view=SwatchDragCanvas(frame:.zero); view.model=model; return view
    }
    func updateNSView(_ view:SwatchDragCanvas,context:Context) { view.model=model }
}
@MainActor
final class SwatchDragCanvas:NSView {
    weak var model:ChromaDroplet?
    override func hitTest(_ point:NSPoint)->NSView? { nil }
}
