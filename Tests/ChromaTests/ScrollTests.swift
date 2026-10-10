import XCTest
import AppKit
import SwiftUI
import DroppyKit
@testable import Chroma

@MainActor
final class ScrollTests:XCTestCase {
    func testCompactSoloAndPairedRenderWithVerticalSwatches() {
        let model=ChromaDroplet()
        for code in ["#09AA83","#F19F38","#725BD6","#C34163"] { model.select(HexColor(code)!) }
        model.pin(model.library.recent[1])
        for paired in [false,true] {
            let descriptor=model.widgetDescriptors[0]
            let width=(paired ? descriptor.layoutTraits.preferredPairedWidth:descriptor.layoutTraits.preferredSoloWidth)!
            let height=model.compactHeight
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.borderless],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false
            let context=ShelfWidgetContext(availableSize:CGSize(width:width,height:height),isPaired:paired,isPreview:true)
            let root=NSHostingView(rootView:CompactPicker(model:model,context:context))
            window.contentView=root
            root.layoutSubtreeIfNeeded()
            RunLoop.main.run(until:Date().addingTimeInterval(0.15))
            XCTAssertLessThanOrEqual(root.fittingSize.height,height+0.5,"Vertical swatches must fit without adding a footer")
            XCTAssertEqual(swatchViews(root).filter { $0.color != nil }.count,4,"Both compact layouts must show four saved swatches")
            capture(root,name:paired ? "compact-paired":"compact-solo")
            window.close()
        }
    }

    func testShortPickerFitsSuggestionsAtItsPreferredHeight() {
        let model=ChromaDroplet()
        let height=model.pickerHeight
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:height),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let root=NSHostingView(rootView:ExpandedPicker(model:model,isPreview:true).frame(width:440,height:height))
        window.contentView=root
        root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.3))
        func findScroll(_ view:NSView)->SavedColorsNativeScrollView? {
            if let scroll=view as? SavedColorsNativeScrollView { return scroll }
            return view.subviews.compactMap(findScroll).first
        }
        guard let scroll=findScroll(root) else { XCTFail("Missing saved-color scroller"); return }
        XCTAssertFalse(scroll.hasContentBelow,"Short lists must fit the suggestions")
        capture(root,name:"short-picker")
        window.close()
    }
    func testExpandedPickerActuallyOverflowsWithSavedColors() {
        let model=ChromaDroplet()
        model.library.pinned=(1...60).map { SavedColor(color:HexColor(String(format:"#%06X",$0*123457))!) }
        model.library.recent=Array(model.library.pinned.prefix(27).map(\.color))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:480),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let root=NSHostingView(rootView:ExpandedPicker(model:model,isPreview:true).frame(width:440,height:480))
        window.contentView=root
        root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        func findScroll(_ view:NSView)->SavedColorsNativeScrollView? {
            if let scroll=view as? SavedColorsNativeScrollView { return scroll }
            return view.subviews.compactMap(findScroll).first
        }
        guard let scroll=findScroll(root) else { XCTFail("Expanded picker must contain the native saved-color scroller"); return }
        XCTAssertTrue(scroll.hasContentBelow)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertFalse(scroll.autohidesScrollers)
        capture(root,name:"saved-colors-top")
        scroll.contentView.scroll(to:NSPoint(x:0,y:scroll.documentView!.frame.height-scroll.contentView.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertFalse(scroll.hasContentBelow)
        RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        capture(root,name:"saved-colors-bottom")
        window.close()
    }
    func testExpandedContentHasNoReservedBottomHeight() {
        let model=ChromaDroplet()
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:560),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let root=NSHostingView(rootView:ExpandedPicker(model:model,isPreview:true,availableHeight:560))
        window.contentView=root
        root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        XCTAssertEqual(root.fittingSize.height,model.pickerHeight,accuracy:1)
        XCTAssertLessThan(root.fittingSize.height,560)
        window.close()
    }
    private func capture(_ view:NSView,name:String) {
        guard let directory=ProcessInfo.processInfo.environment["CHROMA_SCROLL_SHOTS"],
              let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        if let data=bitmap.representation(using:.png,properties:[:]) {
            try? FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
            try? data.write(to:URL(fileURLWithPath:directory).appendingPathComponent(name+".png"))
        }
    }
    func testOverflowAndBottomPosition() {
        let content=AnyView(VStack(spacing:8) {
            ForEach(0..<40) { i in Text("Saved color \(i)").frame(height:32) }
        }.fixedSize(horizontal:false,vertical:true))
        let scroll=SavedColorsNativeScrollView(content:content)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:180),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        window.contentView=scroll
        window.contentView?.layoutSubtreeIfNeeded()
        scroll.layoutSubtreeIfNeeded()
        XCTAssertFalse(scroll.autohidesScrollers)
        XCTAssertEqual(scroll.scrollerStyle,.legacy)
        XCTAssertGreaterThan(scroll.documentView!.frame.height,scroll.contentView.bounds.height)
        XCTAssertTrue(scroll.hasContentBelow)
        XCTAssertNil(scroll.contentView.layer?.mask,"Saved colors should have no fade mask")
        XCTAssertFalse(scroll.contentView.drawsBackground)
        let bottom=scroll.documentView!.frame.height-scroll.contentView.bounds.height
        scroll.contentView.scroll(to:NSPoint(x:0,y:bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertFalse(scroll.hasContentBelow)
        window.close()
    }
    func testSavedContentUpdatesWithoutReplacingHostingRoot() {
        func rows(_ count:Int)->AnyView {
            AnyView(VStack(spacing:8) {
                ForEach(0..<count,id:\.self) { i in Text("Saved color \(i)").frame(height:32) }
            }.fixedSize(horizontal:false,vertical:true))
        }
        let store=SavedColorsContentStore(content:rows(1))
        let scroll=SavedColorsNativeScrollView(content:AnyView(SavedColorsHostedContent(store:store)))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:180),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        window.contentView=scroll
        scroll.layoutSubtreeIfNeeded()
        let original=scroll.documentView!
        XCTAssertFalse(scroll.hasContentBelow)
        withAnimation(DroppyAnimation.listChange) { store.content=rows(12) }
        RunLoop.main.run(until:Date().addingTimeInterval(0.5))
        scroll.layoutSubtreeIfNeeded()
        XCTAssertTrue(scroll.documentView === original)
        XCTAssertTrue(scroll.hasContentBelow,"Added rows must update the stable hosting view")
        window.close()
    }
    func testNativeSwatchDropUsesActualPasteboardPayload() {
        let model=ChromaDroplet()
        let a=HexColor("#112233")!,b=HexColor("#445566")!
        model.select(a); model.pin(b)
        let view=NativeSwatchView(frame:NSRect(x:0,y:0,width:32,height:32))
        XCTAssertFalse(view.mouseDownCanMoveWindow,"Dragging a swatch must never drag the host panel")
        view.model=model; view.targetColor=b
        view.registerForDraggedTypes([.string])
        XCTAssertTrue(view.registeredDraggedTypes.contains(.string))
        let board=NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(a.hex,forType:.string)
        XCTAssertTrue(view.receive(board))
        XCTAssertEqual(model.library.pinned.map(\.color),[a,b])
        XCTAssertEqual(model.selected,a)
        board.clearContents(); board.setString("not a color",forType:.string)
        XCTAssertFalse(view.receive(board))
    }
    func testInternalDragFindsPinnedTargetsInRealPicker() {
        let model=ChromaDroplet()
        let a=HexColor("#112233")!,b=HexColor("#445566")!,c=HexColor("#778899")!
        model.select(a); model.pin(b); model.pin(c)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:480),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let root=NSHostingView(rootView:ExpandedPicker(model:model,isPreview:true,availableHeight:480))
        window.contentView=root
        root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.3))
        func swatches(_ view:NSView)->[NativeSwatchView] {
            view.subviews.flatMap(swatches) + ((view as? NativeSwatchView).map { [$0] } ?? [])
        }
        let views=swatches(root)
        guard let source=views.first(where:{$0.color==a && $0.section == .recent}),
              let target=views.first(where:{$0.color==b && $0.section == .pinned}) else {
            XCTFail("The actual picker must contain recent and pinned hit areas"); window.close(); return
        }
        XCTAssertGreaterThan(source.bounds.width,20)
        XCTAssertGreaterThan(target.bounds.height,20)
        let center=target.convert(NSPoint(x:target.bounds.midX,y:target.bounds.midY),to:nil)
        source.updateInternalDrag(at:center)
        XCTAssertTrue(source.finishInternalDrag(),"A recent swatch must find a pinned destination through nested hosting views")
        XCTAssertEqual(model.library.pinned.map(\.color),[a,b,c])
        XCTAssertEqual(model.library.recent,[a])
        let pinSource=views.first(where:{$0.color==c && $0.section == .pinned})!
        pinSource.updateInternalDrag(at:center)
        XCTAssertTrue(pinSource.finishInternalDrag())
        XCTAssertEqual(model.library.pinned.map(\.color),[a,c,b])
        source.updateInternalDrag(at:NSPoint(x:-100,y:-100))
        XCTAssertFalse(source.finishInternalDrag(),"Dropping outside Pinned must leave the library unchanged")
        window.close()
    }
    func testInternalDragIntoEmptyPinnedSection() {
        let model=ChromaDroplet(); let color=HexColor("#112233")!; model.select(color)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:480),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let root=NSHostingView(rootView:ExpandedPicker(model:model,isPreview:true,availableHeight:480))
        window.contentView=root; root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.3))
        func swatches(_ view:NSView)->[NativeSwatchView] {
            view.subviews.flatMap(swatches) + ((view as? NativeSwatchView).map { [$0] } ?? [])
        }
        let views=swatches(root)
        guard let source=views.first(where:{$0.color==color}),let empty=views.first(where:{$0.color==nil && $0.section == .pinned && !$0.registeredDraggedTypes.isEmpty}) else { XCTFail("Missing empty Pinned drop area"); window.close(); return }
        XCTAssertGreaterThan(empty.bounds.height,20)
        source.updateInternalDrag(at:empty.convert(NSPoint(x:empty.bounds.midX,y:empty.bounds.midY),to:nil))
        XCTAssertTrue(source.finishInternalDrag())
        XCTAssertEqual(model.library.pinned.map(\.color),[color])
        window.close()
    }
    func testContinuousDragProjectsOrderAndCancelsWithoutSaving() {
        let model=ChromaDroplet()
        let colors=["#112233","#445566","#778899"].map { HexColor($0)! }
        model.library.recent=colors
        withPicker(model:model) { root in
            let tiles=swatchViews(root).filter { $0.section == .recent && $0.color != nil }
            let source=tiles.first(where:{$0.color==colors[0]})!
            let last=tiles.first(where:{$0.color==colors[2]})!
            source.beginInternalDrag()
            let firstPoint=last.convert(NSPoint(x:last.bounds.maxX-2,y:last.bounds.midY),to:nil)
            source.updateInternalDrag(at:firstPoint)
            XCTAssertEqual(model.dragLibrary?.recent,[colors[1],colors[2],colors[0]])
            XCTAssertEqual(model.library.recent,colors,"Hover rearrangement must remain temporary")
            RunLoop.main.run(until:Date().addingTimeInterval(0.25))
            capture(root,name:"drag-reorder-preview")
            let middle=tiles.first(where:{$0.color==colors[1]})!
            source.updateInternalDrag(at:middle.convert(NSPoint(x:2,y:middle.bounds.midY),to:nil))
            XCTAssertEqual(model.dragLibrary?.recent,colors,"Subsequent cursor movements must continue updating the destination")
            source.cancelInternalDrag()
            XCTAssertEqual(model.library.recent,colors)
            XCTAssertNil(model.dragLibrary); XCTAssertNil(model.draggedColor); XCTAssertNil(model.cancelSwatchDrag)
        }
    }
    func testPinnedDragToItsExistingRecentTileUnpinsWithoutSelecting() {
        let model=ChromaDroplet()
        let a=HexColor("#112233")!,b=HexColor("#445566")!
        model.select(a); model.select(b); model.pin(a)
        withPicker(model:model) { root in
            let views=swatchViews(root)
            let source=views.first(where:{$0.color==a && $0.section == .pinned})!
            let target=views.first(where:{$0.color==a && $0.section == .recent})!
            source.updateInternalDrag(at:target.convert(NSPoint(x:target.bounds.midX,y:target.bounds.midY),to:nil))
            XCTAssertEqual(model.dragLibrary?.pinned.count,0)
            XCTAssertEqual(model.library.pinned.count,1)
            XCTAssertTrue(source.finishInternalDrag())
            XCTAssertTrue(model.library.pinned.isEmpty)
            XCTAssertEqual(model.library.recent,[b,a]); XCTAssertEqual(model.selected,b)
        }
    }
    func testCompactDragHasPrecisePreviewAndPinDropZone() {
        let model=ChromaDroplet(); let a=HexColor("#112233")!,b=HexColor("#445566")!
        model.select(a); model.select(b); model.pin(a)
        let descriptor=model.widgetDescriptors[0]
        let width=descriptor.layoutTraits.preferredSoloWidth!
        let context=ShelfWidgetContext(availableSize:CGSize(width:width,height:model.compactHeight),isPaired:false,isPreview:true)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:model.compactHeight),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let root=NSHostingView(rootView:CompactPicker(model:model,context:context))
        window.contentView=root; root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        let views=swatchViews(root)
        let source=views.first(where:{$0.color==a})!
        let toggle=views.first(where:{$0.togglesPin})!
        source.beginInternalDrag()
        @MainActor func canvas(_ view:NSView)->SwatchDragCanvas? {
            (view as? SwatchDragCanvas) ?? view.subviews.compactMap(canvas).first
        }
        let overlay=canvas(root)!,preview=overlay.subviews.last!
        XCTAssertEqual(preview.frame.size,source.bounds.size,"The preview must retain the swatch's original dimensions")
        let artwork=preview.subviews.compactMap { $0 as? NSImageView }.first
        XCTAssertEqual(artwork?.layer?.cornerRadius,DroppyRadius.small)
        XCTAssertEqual(artwork?.layer?.masksToBounds,true,"Clip the captured background to the actual rounded swatch")
        XCTAssertNotNil(preview.layer?.shadowPath,"The outside shadow must follow the rounded shape")
        let image=artwork?.image
        XCTAssertNotNil(image,"Preserve the actual swatch artwork")
        if let bitmap=image?.representations.first as? NSBitmapImageRep,let center=bitmap.colorAt(x:bitmap.pixelsWide/2,y:bitmap.pixelsHigh/2)?.usingColorSpace(.sRGB) {
            XCTAssertGreaterThan(center.alphaComponent,0.95,"A drag preview must contain the color, not a transparent native overlay")
            XCTAssertLessThan(center.redComponent,0.4,"Capture the dark dragged swatch, not the main picker preview")
            XCTAssertLessThan(center.blueComponent,0.45)
        } else { XCTFail("Missing drag preview pixels") }
        let target=toggle.convert(NSPoint(x:toggle.bounds.midX,y:toggle.bounds.midY),to:nil)
        source.updateInternalDrag(at:target)
        XCTAssertEqual(overlay.convert(preview.frame.origin,to:nil).x,target.x-source.bounds.midX,accuracy:0.5)
        XCTAssertEqual(model.dragLibrary?.pinned.count,0,"The compact pin control also accepts drag-to-unpin")
        capture(root,name:"compact-drag-preview")
        XCTAssertTrue(source.finishInternalDrag()); XCTAssertTrue(model.library.pinned.isEmpty)
        XCTAssertEqual(model.selected,b)
        window.close()
    }
    func testDragDestinationTracksScrollingInExpandedView() {
        let model=ChromaDroplet()
        model.library.pinned=(1...60).map { SavedColor(color:HexColor(String(format:"#%06X",$0*123457))!) }
        let first=model.library.pinned.first!.color,last=model.library.pinned.last!.color
        withPicker(model:model) { root in
            let tiles=swatchViews(root)
            let source=tiles.first(where:{$0.color==first && $0.section == .pinned})!
            let target=tiles.first(where:{$0.color==last && $0.section == .pinned})!
            @MainActor func scroll(_ view:NSView)->SavedColorsNativeScrollView? {
                (view as? SavedColorsNativeScrollView) ?? view.subviews.compactMap(scroll).first
            }
            let scroller=scroll(root)!
            source.beginInternalDrag()
            scroller.contentView.scroll(to:NSPoint(x:0,y:scroller.documentView!.frame.height-scroller.contentView.bounds.height))
            scroller.reflectScrolledClipView(scroller.contentView)
            source.updateInternalDrag(at:target.convert(NSPoint(x:target.bounds.maxX-2,y:target.bounds.midY),to:nil))
            XCTAssertTrue(source.finishInternalDrag())
            XCTAssertEqual(model.library.pinned.last?.color,first,"Scrolling during a drag must preserve accurate insertion coordinates")
        }
    }
    func testComplementaryAndAnalogousSwatchesCanBeDraggedWithoutSelecting() {
        for offset in [0.5,-1.0/12,1.0/12] {
            let model=ChromaDroplet(),selected=ChromaDroplet().selected
            let suggestion=selected.rotatedHue(offset)
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:240),styleMask:[.borderless],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false
            let root=NSHostingView(rootView:VStack {
                Swatch(model:model,color:suggestion,kind:.suggestion)
                SwatchSection(title:"Pinned",colors:[],model:model,kind:.pinned)
                SwatchSection(title:"Recent",colors:[],model:model,kind:.recent)
            }.overlay { NativeSwatchCanvas(model:model) })
            window.contentView=root; root.layoutSubtreeIfNeeded()
            RunLoop.main.run(until:Date().addingTimeInterval(0.1))
            let views=swatchViews(root),source=views.first(where:{$0.section == .suggestion})!
            for section in [SwatchKind.pinned,.recent] {
                let target=views.first(where:{$0.section==section && $0.color==nil})!
                source.updateInternalDrag(at:target.convert(NSPoint(x:target.bounds.midX,y:target.bounds.midY),to:nil))
                XCTAssertTrue(source.finishInternalDrag())
                XCTAssertEqual(model.selected,selected)
            }
            XCTAssertEqual(model.library.pinned.map(\.color),[suggestion])
            XCTAssertEqual(model.library.recent,[suggestion])
            window.close()
        }
    }
    private func swatchViews(_ view:NSView)->[NativeSwatchView] {
        view.subviews.flatMap(swatchViews) + ((view as? NativeSwatchView).map { [$0] } ?? [])
    }
    private func withPicker(model:ChromaDroplet,_ verify:(NSView)->Void) {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:480),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let root=NSHostingView(rootView:ExpandedPicker(model:model,isPreview:true,availableHeight:480))
        window.contentView=root; root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        verify(root); model.cancelSwatchDrag?(); window.close()
    }
    func testShortContentFits() {
        let scroll=SavedColorsNativeScrollView(content:AnyView(Text("Recent colors").frame(height:32).fixedSize(horizontal:false,vertical:true)))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:180),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        window.contentView=scroll
        scroll.layoutSubtreeIfNeeded()
        XCTAssertFalse(scroll.hasContentBelow)
        XCTAssertFalse(scroll.hasVerticalScroller)
        XCTAssertFalse(scroll.isScrollable)
        window.close()
    }
}
