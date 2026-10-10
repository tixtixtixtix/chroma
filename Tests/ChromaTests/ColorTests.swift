import XCTest
@testable import Chroma

final class ColorTests:XCTestCase {
    func testInputFormatsAndNormalization() {
        XCTAssertEqual(HexColor("#abc")?.hex,"#AABBCC")
        XCTAssertEqual(HexColor("aabbcc")?.hex,"#AABBCC")
        XCTAssertEqual(HexColor("  #aBcDef\n")?.hex,"#ABCDEF")
        XCTAssertEqual(HexColor("#12abcd80")?.hex,"#12ABCD80")
        XCTAssertEqual(HexColor("#12abcdFF"),HexColor("#12ABCD"))
        XCTAssertEqual(HexColor("#00000000")?.components.3,0)
        for invalid in ["","#","12","#1234","#12345","#1234567","#123456789","#GG0000","##123456","#12 3456","rgb(1,2,3)","１２３"] { XCTAssertNil(HexColor(invalid),invalid) }
    }
    func testOnlyHexCopyFormats() {
        let color=HexColor("#ff001180")!
        XCTAssertEqual(color.copyText(prefix:true),"#FF001180")
        XCTAssertEqual(color.copyText(prefix:false),"FF001180")
    }
    func testHistoryDeduplicatesAndMovesToFront() {
        var library=ColorLibrary()
        for value in 0..<40 { library.select(HexColor(red:Double(value)/255,green:0,blue:0)) }
        XCTAssertEqual(library.recent.count,27)
        let reused=library.recent[20]; library.select(reused)
        XCTAssertEqual(library.recent.first,reused)
        XCTAssertEqual(library.recent.filter { $0==reused }.count,1)
        library.settings.maximumRecent=4; library.trim(); XCTAssertEqual(library.recent.count,4)
    }
    func testClearAndPreferenceResetKeepPinsAndPalettes() {
        var library=ColorLibrary(); let color=HexColor("#ABC")!
        library.select(color); library.pin(color); library.pin(HexColor("#AABBCCFF")!)
        XCTAssertEqual(library.pinned.count,1)
        library.palettes=[Palette(name:"Brand")]; library.add(color,to:library.palettes[0].id)
        library.recent=[]; library.settings=Preferences()
        XCTAssertEqual(library.pinned[0].color,color)
        XCTAssertEqual(library.palettes[0].colors,[color])
    }
    func testPinAndPaletteReordering() {
        var library=ColorLibrary(); let a=HexColor("#F00")!, b=HexColor("#0F0")!, c=HexColor("#00F")!
        [a,b,c].forEach { library.pin($0) }; library.movePin(c,to:a)
        XCTAssertEqual(library.pinned.map(\.color),[c,a,b])
        library.palettes=[Palette(name:"Brand")]; let id=library.palettes[0].id
        [a,b,c,a].forEach { library.add($0,to:id) }
        library.movePaletteColor(c,to:a,palette:id)
        XCTAssertEqual(library.palettes[0].colors,[c,a,b])
        library.unpin(a); XCTAssertFalse(library.palettes[0].colors.contains(a))
    }
    func testPersistentRoundTrip() throws {
        var library=ColorLibrary(); let color=HexColor("#8a42f180")!
        library.select(color); library.pin(color); library.pinned[0].name="Accent"
        library.palettes=[Palette(name:"Interface")]; library.add(color,to:library.palettes[0].id)
        library.settings.includePrefix=false
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        try JSONEncoder().encode(library).write(to:file,options:.atomic)
        XCTAssertEqual(try JSONDecoder().decode(ColorLibrary.self,from:Data(contentsOf:file)),library)
    }
    func testSuggestionsPreserveAlpha() {
        XCTAssertEqual(HexColor("#FF000080")!.rotatedHue(0.5),HexColor("#00FFFF80"))
        XCTAssertEqual(HexColor("#FF0000")!.rotatedHue(-1/12),HexColor("#FF0080"))
        XCTAssertEqual(HexColor("#777777")!.rotatedHue(0.5),HexColor("#777777"))
    }
}

extension ColorTests {
    func testInlinePickerConversionAndClamping() {
        XCTAssertEqual(HexColor.hsv(hue:0,saturation:1,brightness:1,alpha:0.5),HexColor("#FF000080"))
        XCTAssertEqual(HexColor.hsv(hue:0.5,saturation:1,brightness:1,alpha:1),HexColor("#00FFFF"))
        XCTAssertEqual(HexColor.hsv(hue:0.8,saturation:-1,brightness:2,alpha:1),HexColor("#FFFFFF"))
        for text in ["#FF0000","#00FF00","#0000FF","#ABCDEF80","#000000","#888888"] {
            let color=HexColor(text)!, h=color.hsv
            XCTAssertEqual(HexColor.hsv(hue:h.hue,saturation:h.saturation,brightness:h.brightness,alpha:h.alpha),color)
        }
    }
}
