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
        XCTAssertFalse(scroll.autohidesScrollers)
        capture(root,name:"saved-colors-top")
        scroll.contentView.scroll(to:NSPoint(x:0,y:scroll.documentView!.frame.height-scroll.contentView.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertFalse(scroll.hasContentBelow)
        RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        capture(root,name:"saved-colors-bottom")
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
    func testShortContentFits() {
        let scroll=SavedColorsNativeScrollView(content:AnyView(Text("Recent colors").frame(height:32).fixedSize(horizontal:false,vertical:true)))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:180),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        window.contentView=scroll
        scroll.layoutSubtreeIfNeeded()
        XCTAssertFalse(scroll.hasContentBelow)
        window.close()
    }
}
