import AppKit
import Combine
import DroppyKit
import SwiftUI

@objc(ChromaPrincipal)
public final class ChromaPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }
    @MainActor public func makeDroplet() -> AnyObject { ChromaDroplet() }
}

@MainActor
public final class ChromaDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "chroma"
    @Published var library = ColorLibrary()
    @Published var input = "#7C6FF0"
    @Published var notice = ""
    @Published var clipboardColor: HexColor?
    @Published var captureCommand: DropletLauncherItem?
    var host: DropletHost?
    private var subscriptions = Set<AnyCancellable>()
    private var captureObserver: AnyCancellable?
    private var noticeTask: Task<Void,Never>?
    private var editTask: Task<Void,Never>?
    private var pendingCapture: (count:Int, expires:Date)?
    private var lastClipboardCount = -1
    private var editDirty = false
    var canCopy: Bool { host?.isGranted(.clipboardWrite) == true }
    var selected: HexColor { library.selected }
    @Published var measuredSavedColorsHeight:CGFloat?
    @Published var measuredPickerHeaderHeight:CGFloat?
    var compactHeight:CGFloat { (captureCommand == nil ? 20:28)+8+112+16 }
    func measuredPickerHeader(_ height:CGFloat) {
        if height>0 && abs((measuredPickerHeaderHeight ?? 0)-height)>0.5 { measuredPickerHeaderHeight=height }
    }
    var selectedIsPinned:Bool { library.pinned.contains { $0.color==selected } }
    func toggleSelectedPin() { if selectedIsPinned { unpin(selected) } else { pin(selected) } }
    var savedColorsHeight:CGFloat {
        if let measuredSavedColorsHeight { return measuredSavedColorsHeight }
        func section(_ count:Int)->CGFloat {
            let rows=CGFloat((count+8)/9)
            return 19+(count==0 ? 14:rows*32+max(0,rows-1)*8)
        }
        let clipboardHeight:CGFloat=(clipboardColor != nil && clipboardColor != selected) ? 40:0
        return section(library.pinned.count)+section(library.recent.count)+24+36+4+clipboardHeight
    }
    var pickerHeight:CGFloat { min(560,(measuredPickerHeaderHeight ?? (230+(HexColor(input)==nil ? 24:0)))+36+savedColorsHeight) }
    func measuredSavedColors(_ height:CGFloat) {
        if height>0 && abs((measuredSavedColorsHeight ?? 0)-height)>0.5 { measuredSavedColorsHeight=height }
    }
    var quickColors: [HexColor] {
        var result = library.pinned.map(\.color)
        result += library.recent.filter { !result.contains($0) }
        return Array(result.prefix(8))
    }
    public func activate(host: DropletHost) throws {
        self.host = host
        library = host.preferences.value(forKey:"library.v1", default:ColorLibrary())
        if !host.preferences.value(forKey:"default27.v1",default:false) {
            if library.settings.maximumRecent==30 { library.settings.maximumRecent=27 }
            host.preferences.setValue(true,forKey:"default27.v1")
        }
        library.sanitize(); input=selected.hex
        save()
        refreshCommand()
        host.launcher.catalogDidChange.sink { [weak self] in self?.refreshCommand(); self?.consumeCapture() }.store(in:&subscriptions)
        NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification).sink { [weak self] _ in self?.checkClipboard(); self?.consumeCapture() }.store(in:&subscriptions)
        host.shelf.didChange.sink { [weak self] _ in self?.consumeCapture() }.store(in:&subscriptions)
    }
    public func deactivate() {
        flushEdit(); subscriptions.removeAll(); captureObserver=nil; pendingCapture=nil
        noticeTask?.cancel(); noticeTask=nil; host=nil; clipboardColor=nil; captureCommand=nil
    }
    func save() { host?.preferences.setValue(library,forKey:"library.v1") }
    func mutate(_ change:(inout ColorLibrary)->Void) {
        let previousHeight=compactHeight
        var updated=library
        change(&updated); updated.trim()
        withAnimation(DroppyAnimation.listChange) { library=updated }
        if compactHeight != previousHeight { host?.shelf.invalidateLayout(for:"chroma") }
        save()
    }
    func select(_ color:HexColor) {
        editTask?.cancel(); editTask=nil
        editDirty=false
        mutate { $0.select(color) }; input=color.hex
    }
    func previewVisual(_ color:HexColor) {
        editTask?.cancel(); editTask=nil; editDirty=false
        library.selected=color; input=color.hex
    }
    func editHex(_ text:String) {
        input=text; editDirty=true; editTask?.cancel()
        guard let color=HexColor(text) else { editTask=nil; return }
        library.selected=color
        // Do not rewrite a six-digit prefix while the user is typing alpha.
        // Uppercase immediately; expand shorthand when Return or focus commits it.
        input=text.uppercased()
        editTask=Task { [weak self] in
            try? await Task.sleep(for:.milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            self.mutate { $0.select(color) }
            self.editTask=nil
        }
    }
    func flushEdit() {
        editTask?.cancel(); editTask=nil
        guard editDirty else { return }
        if let color=HexColor(input) { mutate { $0.select(color) }; input=color.hex; editDirty=false }
    }
    func confirmHex() {
        guard HexColor(input) != nil else { showNotice("Enter 3, 6 or 8 HEX digits"); return }
        flushEdit()
    }
    func copyHex(_ color:HexColor?=nil) {
        guard let host, host.isGranted(.clipboardWrite) else { showNotice("Clipboard permission is unavailable"); return }
        let color=color ?? selected
        guard host.workspace.copyToPasteboard(color.copyText(prefix:library.settings.includePrefix)) else { showNotice("Couldn’t copy this color"); return }
        select(color); lastClipboardCount=NSPasteboard.general.changeCount; clipboardColor=nil
        if library.settings.showConfirmation { showNotice("Copied \(color.copyText(prefix:library.settings.includePrefix))") }
    }
    func showNotice(_ text:String) {
        noticeTask?.cancel(); notice=text
        noticeTask=Task { [weak self] in
            try? await Task.sleep(for:.milliseconds(1200))
            guard !Task.isCancelled else { return }; self?.notice=""
        }
    }
    func checkClipboard() {
        guard let host, !host.environment.isHarness, host.isGranted(.clipboardRead), library.settings.detectClipboard else { clipboardColor=nil; return }
        let board=NSPasteboard.general
        guard board.changeCount != lastClipboardCount else { return }
        lastClipboardCount=board.changeCount
        clipboardColor=board.string(forType:.string).flatMap(HexColor.init)
    }
    private func refreshCommand() {
        // Resolve the live catalog, never an invented command ID or private selector.
        captureCommand=host?.launcher.catalog.first { item in
            guard item.kind == .command else { return false }
            let words=([item.id,item.title,item.subtitle ?? ""]+item.keywords).joined(separator:" ").lowercased()
            return words.contains("color") && (words.contains("picker") || words.contains("eyedropper"))
        }
    }
    func pickAndCopy() {
        guard let host, let command=captureCommand else { showNotice("Enable Droppy’s capture color picker first"); return }
        flushEdit()
        pendingCapture=(NSPasteboard.general.changeCount,Date().addingTimeInterval(120))
        // Event-driven and scoped only to this capture session. No timer or background polling.
        captureObserver=NotificationCenter.default.publisher(for:NSApplication.didUpdateNotification).sink { [weak self] _ in self?.consumeCapture() }
        let outcome=host.launcher.perform(itemID:command.id,actionID:nil,query:"")
        switch outcome {
        case .dismiss: host.notchSurface.dismissExpandedSurface("picker"); host.shelf.close()
        case .failed(let message): pendingCapture=nil; captureObserver=nil; showNotice(message)
        case .presentDetail: pendingCapture=nil; captureObserver=nil; showNotice("This host command needs its own capture interface")
        default: break
        }
    }
    func consumeCapture() {
        guard let pending=pendingCapture else { return }
        guard Date() < pending.expires else { pendingCapture=nil; captureObserver=nil; return }
        let board=NSPasteboard.general
        guard board.changeCount != pending.count else { return }
        pendingCapture=nil; captureObserver=nil
        guard let text=board.string(forType:.string), let color=HexColor(text) else { return }
        select(color)
        // The capture button explicitly requests a copy. Normalize only this capture result.
        _ = host?.workspace.copyToPasteboard(color.copyText(prefix:library.settings.includePrefix))
        lastClipboardCount=board.changeCount
        if library.settings.showConfirmation { showNotice("Picked \(color.hex)") }
    }
    func openPicker() {
        guard host?.notchSurface.presentExpandedSurface(.init(surfaceID:"picker")) != nil else { showNotice("Expanded picker is unavailable"); return }
        _ = host?.shelf.requestKeyboardFocus()
    }
    func closePicker() { flushEdit(); host?.notchSurface.dismissExpandedSurface("picker") }
    func pin(_ color:HexColor) { mutate { $0.pin(color) } }
    func unpin(_ color:HexColor) { mutate { $0.unpin(color) } }
    func updateSetting(_ change:(inout Preferences)->Void) { mutate { change(&$0.settings) }; checkClipboard() }
}

extension ChromaDroplet: ShelfWidgetProviding {
    public var widgetDescriptors:[ShelfWidgetDescriptor] {
        [.init(id:"chroma",title:"Chroma",systemImage:"paintpalette",layoutTraits:.init(preferredSoloWidth:440,preferredPairedWidth:280,contentHeight:.fixed(compactHeight)),focusPolicy:.keyboardFocusable)]
    }
    public func makeWidgetView(_ id:ShelfWidgetID,context:ShelfWidgetContext)->AnyView { AnyView(CompactPicker(model:self,context:context)) }
    public func makeWidgetSettingsPopover(_ id:ShelfWidgetID)->AnyView? { nil }
}
extension ChromaDroplet: ExpandedSurfaceHosting, ExpandedSurfaceProviding {
    public var expandedSurfaceProvider:(any ExpandedSurfaceProviding)? { self }
    public var expandedSurfaces:[ExpandedSurfaceDescriptor] { [.init(id:"picker",title:"Color picker",systemImage:"paintpalette",suppresses:[.shelfWidgets,.favoritesBar,.floatingNavLane,.autoCollapse])] }
    public func makeExpandedSurfaceView(_ id:ExpandedSurfaceID,context:ExpandedSurfaceContext)->AnyView { AnyView(ExpandedPicker(model:self,isPreview:context.isPreview)) }
    public func expandedSurfaceSize(_ id:ExpandedSurfaceID,fitting proposal:ExpandedSurfaceSizeProposal)->CGSize? { CGSize(width:min(440,proposal.maximumSize.width),height:min(pickerHeight,proposal.maximumSize.height)) }
    public func expandedSurfaceDidDismiss(_ id:ExpandedSurfaceID,presentation:ExpandedSurfacePresentation,reason:ExpandedSurfaceDismissalReason) { flushEdit() }
}
extension ChromaDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context:SettingsPaneContext)->AnyView { AnyView(ChromaSettings(model:self)) }
}
