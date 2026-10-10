import XCTest
import DroppyKit
import DroppyKitHarness
import Combine
@testable import Chroma

@MainActor private final class DiskPreferences:DropletPreferencesService {
    let file:URL
    let changes=PassthroughSubject<String,Never>()
    init(_ file:URL) { self.file=file }
    func value<Value:Codable>(forKey key:String,as type:Value.Type)->Value? {
        guard let data=try? Data(contentsOf:file) else { return nil }
        return try? JSONDecoder().decode(type,from:data)
    }
    func setValue<Value:Codable>(_ value:Value?,forKey key:String) {
        if let value, let data=try? JSONEncoder().encode(value) { try? data.write(to:file,options:.atomic) }
        changes.send(key)
    }
    func hasValue(forKey key:String)->Bool { FileManager.default.fileExists(atPath:file.path) }
    func removeAll() { try? FileManager.default.removeItem(at:file) }
    var didChange:AnyPublisher<String,Never> { changes.eraseToAnyPublisher() }
}
final class ModelTests:XCTestCase {
    @MainActor func testCompactHeightFitsVerticalSwatchesWithoutGrowing() {
        let model=ChromaDroplet()
        XCTAssertEqual(model.compactHeight,156)
        model.select(HexColor("#09AA83")!)
        XCTAssertEqual(model.compactHeight,156)
        model.mutate { $0.recent=[] }
        XCTAssertEqual(model.compactHeight,156)
        model.pin(model.selected)
        XCTAssertEqual(model.compactHeight,156)
        model.mutate { $0.recent=[] }
        XCTAssertEqual(model.compactHeight,156,"Pins share the selector height in the vertical column")
    }
    @MainActor func testSelectionPublishesOneCoherentSavedState() {
        let model=ChromaDroplet()
        var states:[ColorLibrary]=[]
        let subscription=model.$library.dropFirst().sink { states.append($0) }
        let color=HexColor("#09AA83")!
        model.select(color)
        XCTAssertEqual(states.count,1,"A selection must not publish intermediate library states that restart swatch animations")
        XCTAssertEqual(states.first?.selected,color)
        XCTAssertEqual(states.first?.recent.first,color)
        withExtendedLifetime(subscription) {}
    }

    @MainActor func testSelectedPinTogglesAndPickerFitsContent() {
        let model=ChromaDroplet()
        let initialHeight=model.pickerHeight
        XCTAssertFalse(model.selectedIsPinned)
        model.toggleSelectedPin()
        XCTAssertTrue(model.selectedIsPinned)
        model.toggleSelectedPin()
        XCTAssertFalse(model.selectedIsPinned)
        model.updateSetting { $0.maximumRecent=60 }
        for n in 0..<60 { model.select(HexColor(red:Double(n)/255,green:0,blue:0)) }
        XCTAssertEqual(model.library.recent.count,60)
        XCTAssertGreaterThan(model.pickerHeight,initialHeight)
        XCTAssertLessThanOrEqual(model.pickerHeight,560)
    }
    @MainActor func testManualEntryPreviewCommitAndInvalidInput() async throws {
        let model=ChromaDroplet(); let recorder=HarnessRecorder()
        try model.activate(host:.harness(dropletID:"chroma",recorder:recorder))
        defer { model.deactivate() }
        model.editHex("abc12380")
        XCTAssertEqual(model.selected.hex,"#ABC12380")
        XCTAssertEqual(model.input,"ABC12380")
        model.confirmHex(); XCTAssertEqual(model.library.recent.first,model.selected)
        model.editHex("#bad input"); XCTAssertEqual(model.selected.hex,"#ABC12380")
        model.confirmHex(); XCTAssertFalse(model.notice.isEmpty)
        model.editHex("#abc"); model.confirmHex(); XCTAssertEqual(model.input,"#AABBCC")
        model.deactivate(); XCTAssertNil(model.host)
    }
    @MainActor func testHostCopyFormatsAndRefusal() async throws {
        let recorder=HarnessRecorder(); recorder.grantedCapabilities=[.clipboardWrite]
        let model=ChromaDroplet(); try model.activate(host:.harness(dropletID:"chroma",recorder:recorder))
        defer { model.deactivate() }
        model.select(HexColor("#abc")!)
        model.copyHex() // The exact no-argument call the button uses; must not call NSObject.copy().
        model.copyHex(HexColor("#AABBCCFF")!)
        XCTAssertEqual(model.library.recent.count,1)
        XCTAssertTrue(recorder.effects.last(where: { $0.service == "workspace" })?.detail.contains("#AABBCC") == true)
        model.updateSetting { $0.includePrefix=false }
        model.copyHex(HexColor("#00112280")!)
        XCTAssertTrue(recorder.effects.last(where: { $0.service == "workspace" })?.detail.contains("00112280") == true)
        XCTAssertFalse(recorder.effects.last(where: { $0.service == "workspace" })?.detail.contains("#00112280") == true)
        recorder.grantedCapabilities=[]
        let before=model.library
        model.copyHex(HexColor("#00FF00")!)
        XCTAssertEqual(model.library,before)
        XCTAssertTrue(recorder.effects.last?.wasRefused == true)
    }
    @MainActor func testHostStorageAcrossNewInstances() async throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let recorder=HarnessRecorder(), base=DropletHost.harness(dropletID:"chroma",recorder:HarnessRecorder())
        func host()->DropletHost {
            DropletHost(grantedCapabilities:[],preferences:DiskPreferences(file),environment:base.environment,log:base.log,installState:base.installState,hud:base.hud,shelf:base.shelf,liveActivity:base.liveActivity,notchSurface:base.notchSurface,shortcuts:base.shortcuts,workspace:HarnessWorkspaceService(recorder:recorder),feedback:base.feedback,permissions:base.permissions)
        }
        let first=ChromaDroplet(); try first.activate(host:host())
        first.select(HexColor("#ABCDEF80")!); first.pin(first.selected)
        first.mutate { $0.palettes=[Palette(name:"Brand")]; $0.add($0.selected,to:$0.palettes[0].id); $0.pinned[0].name="Brand violet" }
        first.updateSetting { $0.includePrefix=false; $0.detectClipboard=false }
        let expected=first.library; first.deactivate()
        let second=ChromaDroplet(); try second.activate(host:host())
        XCTAssertEqual(second.library,expected)
        second.mutate { $0.recent=[] }; second.deactivate()
        let third=ChromaDroplet(); try third.activate(host:host())
        XCTAssertTrue(third.library.recent.isEmpty)
        XCTAssertEqual(third.library.pinned,expected.pinned)
        XCTAssertEqual(third.library.palettes,expected.palettes)
        third.deactivate()
    }
}

extension ModelTests {
    @MainActor func testVisualDraggingCommitsOnlyFinalColorAndKeepsClipboardUntouched() async throws {
        let recorder=HarnessRecorder(); recorder.grantedCapabilities=[.clipboardWrite]
        let model=ChromaDroplet(); try model.activate(host:.harness(dropletID:"chroma",recorder:recorder))
        defer { model.deactivate() }
        for n in 0..<80 { model.previewVisual(HexColor.hsv(hue:Double(n)/80,saturation:1,brightness:1,alpha:1)) }
        XCTAssertTrue(model.library.recent.isEmpty)
        model.select(model.selected)
        XCTAssertEqual(model.library.recent,[model.selected])
        XCTAssertFalse(recorder.effects.contains(where:{$0.service=="workspace"}))
        let other=HexColor("#ABCDEF")!; model.select(other)
        XCTAssertEqual(model.selected,other)
        XCTAssertFalse(recorder.effects.contains(where:{$0.service=="workspace"}))
    }
}
