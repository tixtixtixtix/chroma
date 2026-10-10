import AppKit
import Combine
import SwiftUI
import DroppyKit
import UniformTypeIdentifiers

private struct ChromaSymbol:View {
    let name:String
    var body:some View {
        Image(systemName:name).symbolRenderingMode(.monochrome)
            .contentTransition(.symbolEffect(.replace))
            .animation(DroppyAnimation.hoverQuick,value:name)
    }
}

extension HexColor {
    var swiftColor:Color { let c=components; return Color(.sRGB,red:c.0,green:c.1,blue:c.2,opacity:c.3) }
    var nsColor:NSColor { let c=components; return NSColor(srgbRed:c.0,green:c.1,blue:c.2,alpha:c.3) }
    init?(_ color:NSColor) {
        guard let rgb=color.usingColorSpace(.sRGB) else { return nil }
        self.init(red:rgb.redComponent,green:rgb.greenComponent,blue:rgb.blueComponent,alpha:rgb.alphaComponent)
    }
}

/// Color surfaces keep their opacity when pressed; copying remains explicit.
private struct ColorSurfaceButtonStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View { configuration.label }
}

struct ColorTile:View {
    let color:HexColor
    var radius:CGFloat = DroppyRadius.small
    var body:some View {
        RoundedRectangle(cornerRadius:radius,style:.continuous)
            .fill(color.swiftColor)
            .background {
                if color.components.3<1 {
                    RoundedRectangle(cornerRadius:radius,style:.continuous).fill(.gray.opacity(0.3))
                }
            }
            .animation(DroppyAnimation.hoverQuick,value:color)
    }
}

struct CaptureButton:View {
    @ObservedObject var model:ChromaDroplet
    var size:CGFloat=28
    var body:some View {
        if model.captureCommand != nil {
        Button { model.pickAndCopy() } label: { ChromaSymbol(name:"eyedropper") }
            .buttonStyle(DroppyCircleButtonStyle(size:size))
            .disabled(model.captureCommand == nil)
            .help(model.captureCommand == nil ? "Enable Droppy’s capture color picker. Not available in Playground." : "Pick & copy with Droppy’s capture eyedropper")
            .accessibilityLabel("Pick and copy with Droppy’s eyedropper")
        }
    }
}

struct CompactPicker:View {
    @ObservedObject var model:ChromaDroplet
    let context:ShelfWidgetContext
    @State private var previewHovered=false
    @State private var pinDropHovered=false
    private var copied:Bool { model.notice.hasPrefix("Copied") }
    private var contentHeight:CGFloat { context.availableSize.height-context.contentInsets.top-context.contentInsets.bottom }
    private var previewHeight:CGFloat { max(24,contentHeight-24) }
    var body:some View {
            HStack(alignment:.top,spacing:DroppySpacing.sm) {
                Button { model.copyHex() } label: {
                    VStack(spacing:4) {
                        ColorTile(color:model.selected).frame(height:previewHeight)
                            .overlay {
                                ChromaSymbol(name:copied ? "checkmark":"doc.on.doc").font(.system(size:18,weight:.semibold))
                                    .foregroundStyle(copied ? Color.green:Color.white)
                                    .frame(width:20,height:20,alignment:.center)
                                    .frame(width:34,height:34,alignment:.center)
                                    .background(.black.opacity(0.35),in:Circle())
                                    .opacity(previewHovered || copied ? 1:0)
                                    .scaleEffect(previewHovered || copied ? 1:0.9)
                                    .animation(DroppyAnimation.hoverQuick,value:previewHovered || copied)
                            }
                        Text(model.selected.hex).font(.system(size:context.isPaired ? 12:14,weight:.medium))
                            .contentTransition(.numericText()).animation(DroppyAnimation.hoverQuick,value:model.selected)
                            .lineLimit(1).minimumScaleFactor(0.7).frame(height:20)
                    }.frame(width:previewHeight)
                }.buttonStyle(ColorSurfaceButtonStyle()).focusEffectDisabled().disabled(!model.canCopy)
                    .onHover { previewHovered=$0 }
                    .help(model.notice.hasPrefix("Copied") ? model.notice:"Click the preview to copy \(model.selected.hex)")
                    .accessibilityLabel("Copy selected HEX \(model.selected.hex)")
                InlineColorPicker(model:model,planeHeight:previewHeight)
                    .frame(maxWidth:.infinity)
                if !model.quickColors.isEmpty {
                    VStack(spacing:DroppySpacing.xs) {
                        ForEach(Array(model.quickColors.prefix(4))) { color in
                            Swatch(model:model,color:color,kind:model.displayedLibrary.pinned.contains(where:{$0.color==color}) ? .pinned:.recent,tileHeight:(contentHeight-3*DroppySpacing.xs)/4,vertical:true)
                                .frame(width:22).transition(.scale(scale:0.92).combined(with:.opacity))
                        }
                        Spacer(minLength:0)
                    }.frame(width:22,height:contentHeight,alignment:.top)
                        .animation(DroppyAnimation.listChange,value:model.quickColors)
                }
                VStack(spacing:DroppySpacing.xsm) {
                    Button { model.openPicker() } label: { ChromaSymbol(name:"arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(DroppyCircleButtonStyle(size:20)).help("Open color picker").accessibilityLabel("Open color picker")
                    Button { model.toggleSelectedPin() } label: { ChromaSymbol(name:model.selectedIsPinned ? "pin.slash":"pin") }
                        .buttonStyle(DroppyCircleButtonStyle(size:20))
                        .help(model.selectedIsPinned ? "Unpin selected color":"Pin selected color")
                        .accessibilityLabel(model.selectedIsPinned ? "Unpin selected color":"Pin selected color")
                        .background {
                            NativeSwatchInteraction(model:model,color:nil,dropEnabled:true,target:nil,onTarget:{ pinDropHovered=$0 },section:.pinned,togglesPin:true)
                        }
                        .background(Circle().fill(.white.opacity(pinDropHovered ? 0.12:0)))
                        .help("Click to pin or unpin. Drop a swatch here to pin or unpin it.")
                    CaptureButton(model:model,size:20)
                }.font(.system(size:12,weight:.semibold)).frame(width:20)
            }.padding(context.contentInsets).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(CopyShortcut(action:{ model.copyHex() }))
            .overlay { NativeSwatchCanvas(model:model).allowsHitTesting(false) }
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            .onAppear { if !context.isPreview { model.consumeCapture(); model.checkClipboard() } }
            .onHover { if $0 && !context.isPreview { model.consumeCapture(); model.checkClipboard() } }
    }
}

struct ExpandedPicker:View {
    @ObservedObject var model:ChromaDroplet
    let isPreview:Bool
    var availableHeight:CGFloat?=nil
    private var savedViewportHeight:CGFloat {
        min(model.savedColorsHeight,max(0,(availableHeight ?? model.pickerHeight)-(model.measuredPickerHeaderHeight ?? 230)-36))
    }
    @FocusState private var hexFocused:Bool
    @State private var hexHovered=false
    var body:some View {
        VStack(alignment:.leading,spacing:DroppySpacing.md) {
            VStack(alignment:.leading,spacing:DroppySpacing.md) {
            HStack {
                Text("Color picker").font(.system(size:12,weight:.semibold))
                Spacer()
                Text(model.notice.hasPrefix("Copied") ? "":model.notice).font(.system(size:11)).lineLimit(1).foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                Button { model.closePicker() } label: { ChromaSymbol(name:"arrow.down.right.and.arrow.up.left") }.buttonStyle(DroppyCircleButtonStyle(size:24)).help("Return to small view").accessibilityLabel("Collapse color picker")
            }
            InlineColorPicker(model:model)
            HStack(spacing:DroppySpacing.sm) {
                ColorTile(color:model.selected).frame(width:28,height:28).accessibilityLabel("Selected color preview")
                TextField("#RRGGBB",text:Binding(get:{model.input},set:{model.editHex($0)}))
                    .font(.system(size:18,weight:.medium)).textFieldStyle(.plain)
                    .focused($hexFocused).onSubmit { model.confirmHex() }.accessibilityLabel("HEX color")
                    .foregroundStyle(hexFocused ? AdaptiveColors.notchSurfacePrimaryText : Color.clear)
                    .overlay(alignment:.leading) {
                        if !hexFocused {
                            Text(model.input).font(.system(size:18,weight:.medium))
                                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                                .contentTransition(.numericText())
                                .animation(DroppyAnimation.hoverQuick,value:model.input)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal,DroppySpacing.md).padding(.vertical,DroppySpacing.sm)
                    .droppyGlassControlChrome(shape:AnyShape(Capsule(style:.continuous)),fill:.veil,isHovering:hexHovered || hexFocused)
                    .onHover { hexHovered=$0 }
                CaptureButton(model:model)
                Button { model.confirmHex(); if HexColor(model.input) != nil { model.copyHex() } } label: {
                    HStack(spacing:6) {
                        ChromaSymbol(name:model.notice.hasPrefix("Copied") ? "checkmark":"doc.on.doc")
                        Text(model.notice.hasPrefix("Copied") ? model.notice:"Copy HEX")
                            .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.8)
                    }.frame(width:130)
                }
                    .buttonStyle(DroppyAccentButtonStyle(color:model.notice.hasPrefix("Copied") ? .green:AdaptiveColors.selectionBlueAuto,size:.small))
                    .animation(DroppyAnimation.hoverQuick,value:model.notice.hasPrefix("Copied"))
                    .disabled(!model.canCopy || HexColor(model.input)==nil)
                    .help("Copy only the HEX code")
                Button { model.toggleSelectedPin() } label: { ChromaSymbol(name:model.selectedIsPinned ? "pin.slash":"pin") }
                    .buttonStyle(DroppyCircleButtonStyle(size:28))
                    .help(model.selectedIsPinned ? "Unpin selected color":"Pin selected color")
                    .accessibilityLabel(model.selectedIsPinned ? "Unpin selected color":"Pin selected color")
            }
            if HexColor(model.input)==nil {
                Text("Use 3, 6 or 8 HEX digits").font(.system(size:10)).foregroundStyle(.orange)
            }
            }.fixedSize(horizontal:false,vertical:true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { model.measuredPickerHeader(geometry.size.height) }
                            .onChange(of:geometry.size.height) { _,height in model.measuredPickerHeader(height) }
                    }
                }
            SavedColorsScrollView(onHeightChange:model.measuredSavedColors) {
                VStack(alignment:.leading,spacing:DroppySpacing.md) {
                    if let clipboard=model.clipboardColor,clipboard != model.selected {
                        HStack {
                            Button { model.select(clipboard); model.clipboardColor=nil } label: {
                                HStack { ColorTile(color:clipboard).frame(width:18,height:18); Text("Use \(clipboard.hex) from clipboard").font(.system(size:11)) }
                            }.buttonStyle(DroppyQuietButtonStyle(size:.small))
                            Spacer()
                        }
                    }
                    SwatchSection(title:"Pinned",colors:model.displayedLibrary.pinned.map(\.color),model:model,kind:.pinned)
                    SwatchSection(title:"Recent",colors:model.displayedLibrary.recent,model:model,kind:.recent)
                    ColorSuggestions(model:model).padding(.top,DroppySpacing.xs)
                }
            }.frame(height:savedViewportHeight)
        }.padding(DroppySpacing.md).frame(maxWidth:.infinity,alignment:.topLeading)
            .fixedSize(horizontal:false,vertical:true)
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            .onAppear { if !isPreview { model.consumeCapture(); model.checkClipboard() } }
            .onHover { if $0 && !isPreview { model.consumeCapture(); model.checkClipboard() } }
            .onChange(of:hexFocused) { _, focused in if !focused { model.flushEdit() } }
            .background(CopyShortcut(action:{ model.copyHex() }))
            .overlay { NativeSwatchCanvas(model:model).allowsHitTesting(false) }
    }
}

/// Own the selection state within the stable saved-content host, including while the popover is open.
struct ColorSuggestions:View {
    @ObservedObject var model:ChromaDroplet
    @State private var kind=0
    @State private var choosing=false
    @State private var hovered=false
    private var title:String { kind==0 ? "Complementary":"Analogous" }
    private var width:CGFloat { (title as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:11)]).width+18 }
    private var colors:[HexColor] { kind==0 ? [model.selected.rotatedHue(0.5)]:[model.selected.rotatedHue(-1/12),model.selected.rotatedHue(1/12)] }
    var body:some View {
        HStack {
            Button { choosing.toggle() } label: {
                HStack(spacing:5) {
                    Text(title).font(.system(size:11)).contentTransition(.opacity)
                    ChromaSymbol(name:"chevron.down").font(.system(size:8,weight:.semibold))
                }.frame(width:width,height:14)
                    .padding(.horizontal,DroppySpacing.sm).padding(.vertical,DroppySpacing.xsm)
                    .droppyGlassControlChrome(shape:AnyShape(Capsule(style:.continuous)),fill:.veil,isHovering:hovered || choosing)
            }.buttonStyle(ColorSurfaceButtonStyle()).onHover { hovered=$0 }
                .help("Choose complementary or analogous color suggestions")
                .accessibilityLabel("Color suggestions: \(title)")
                .popover(isPresented:$choosing,arrowEdge:.bottom) {
                    VStack(alignment:.leading,spacing:4) {
                        option("Complementary",value:0)
                        option("Analogous",value:1)
                    }.padding(8)
                }
            Spacer(minLength:4)
            ForEach(colors) { color in Swatch(model:model,color:color,kind:.suggestion).transition(.opacity) }
        }.animation(DroppyAnimation.hover,value:kind)
    }
    private func option(_ title:String,value:Int)->some View {
        Button {
            withAnimation(DroppyAnimation.hover) { kind=value }
            choosing=false
        } label: {
            HStack {
                ChromaSymbol(name:"checkmark").frame(width:12).opacity(kind==value ? 1:0)
                Text(title)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.buttonStyle(DroppyQuietButtonStyle(size:.small))
    }
}

private struct SavedColorsScrollView<Content:View>:View {
    let onHeightChange:(CGFloat)->Void
    @ViewBuilder let content:Content
    var body:some View {
        NativeSavedColorsScrollView(content:content,onHeightChange:onHeightChange)
    }
}

private struct NativeSavedColorsScrollView<Content:View>:NSViewRepresentable {
    let content:Content
    let onHeightChange:(CGFloat)->Void
    func makeCoordinator()->SavedColorsScrollCoordinator { SavedColorsScrollCoordinator() }
    func makeNSView(context:Context)->NSScrollView {
        let store=SavedColorsContentStore(content:hostedContent)
        context.coordinator.contentStore=store
        let scroll=SavedColorsNativeScrollView(content:AnyView(SavedColorsHostedContent(store:store)))
        context.coordinator.install(scroll:scroll,update:{ _,height in onHeightChange(height) })
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        context.coordinator.setContent(hostedContent,transaction:context.transaction)
        context.coordinator.update={ _,height in onHeightChange(height) }
        context.coordinator.measureLater()
    }
    static func dismantleNSView(_ scroll:NSScrollView,coordinator:SavedColorsScrollCoordinator) { coordinator.stop() }
    private var hostedContent:AnyView {
        AnyView(content.padding(.trailing,DroppySpacing.sm)
            .frame(maxWidth:.infinity,alignment:.topLeading)
            .fixedSize(horizontal:false,vertical:true))
    }
}

/// Keep the hosting root mounted so SwiftUI retains swatch identities and transactions.
@MainActor
final class SavedColorsContentStore:ObservableObject {
    @Published var content:AnyView
    init(content:AnyView) { self.content=content }
}
struct SavedColorsHostedContent:View {
    @ObservedObject var store:SavedColorsContentStore
    var body:some View { store.content }
}

@MainActor
final class SavedColorsNativeScrollView:NSScrollView {
    init(content:AnyView) {
        super.init(frame:.zero)
        drawsBackground=false
        contentView.drawsBackground=false
        hasVerticalScroller=false
        hasHorizontalScroller=false
        verticalScrollElasticity = .none
        horizontalScrollElasticity = .none
        autohidesScrollers=false
        scrollerStyle = .legacy
        verticalScroller?.knobStyle = .light
        let document=NSHostingView(rootView:content)
        document.translatesAutoresizingMaskIntoConstraints=false
        documentView=document
        document.widthAnchor.constraint(equalTo:contentView.widthAnchor).isActive=true
    }
    required init?(coder:NSCoder) { nil }
    var isScrollable:Bool { (documentView?.frame.height ?? 0)>contentView.bounds.height+1 }
    override func layout() {
        super.layout()
        updateScrollingAvailability()
    }
    func updateScrollingAvailability() {
        let enabled=isScrollable
        if hasVerticalScroller != enabled { hasVerticalScroller=enabled; verticalScroller?.knobStyle = .light }
        if !enabled && contentView.bounds.origin != .zero {
            contentView.scroll(to:.zero); reflectScrolledClipView(contentView)
        }
    }
    override func scrollWheel(with event:NSEvent) {
        guard isScrollable else { return }
        super.scrollWheel(with:event)
    }
    var remainingContent:CGFloat { max(0,(documentView?.frame.height ?? 0)-contentView.bounds.maxY) }
    var hasContentBelow:Bool { remainingContent>1 }

}

@MainActor
private final class SavedColorsScrollCoordinator {
    weak var scroll:NSScrollView?
    var contentStore:SavedColorsContentStore?
    private var contentRevision=0
    func setContent(_ content:AnyView,transaction:Transaction) {
        contentRevision += 1
        let revision=contentRevision
        DispatchQueue.main.async { [weak self] in
            guard let self,self.contentRevision==revision,let store=self.contentStore else { return }
            withTransaction(transaction) { store.content=content }
            self.measureLater()
        }
    }
    var update:((Bool,CGFloat)->Void)?
    private var subscriptions:Set<AnyCancellable>=[]
    func install(scroll:NSScrollView,update:@escaping(Bool,CGFloat)->Void) {
        self.scroll=scroll; self.update=update
        scroll.contentView.postsBoundsChangedNotifications=true
        scroll.documentView?.postsFrameChangedNotifications=true
        for (name,object) in [(NSView.boundsDidChangeNotification,scroll.contentView),(NSView.frameDidChangeNotification,scroll.documentView!)] {
            NotificationCenter.default.publisher(for:name,object:object)
                .sink { [weak self] _ in self?.measureLater() }.store(in:&subscriptions)
        }
        measureLater()
    }
    func measureLater() {
        DispatchQueue.main.async { [weak self] in
            guard let self,let scroll=self.scroll as? SavedColorsNativeScrollView else { return }
            scroll.updateScrollingAvailability()
            self.update?(scroll.hasContentBelow,scroll.documentView?.frame.height ?? 0)
        }
    }
    func stop() { subscriptions.removeAll(); update=nil; scroll=nil; contentStore=nil; contentRevision += 1 }
}

enum SwatchKind:Equatable { case pinned,recent,suggestion }
/// One stable child per color, including when it moves between rows.
private struct ColorSwatchGrid:Layout {
    private let columns=9
    private let spacing:CGFloat=8
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout Void)->CGSize {
        let rows=CGFloat((subviews.count+columns-1)/columns)
        return CGSize(width:proposal.width ?? 352,height:rows*32+max(0,rows-1)*spacing)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout Void) {
        let width=max(0,(bounds.width-CGFloat(columns-1)*spacing)/CGFloat(columns))
        for (index,subview) in subviews.enumerated() {
            subview.place(at:CGPoint(x:bounds.minX+CGFloat(index%columns)*(width+spacing),y:bounds.minY+CGFloat(index/columns)*(32+spacing)),anchor:.topLeading,proposal:ProposedViewSize(width:width,height:32))
        }
    }
}

struct SwatchSection:View {
    let title:String
    let colors:[HexColor]
    @ObservedObject var model:ChromaDroplet
    let kind:SwatchKind
    @State private var dropTargeted=false
    var body:some View {
        VStack(alignment:.leading,spacing:DroppySpacing.xsm) {
            Text(title).font(.system(size:11,weight:.semibold)).foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            ColorSwatchGrid {
                    ForEach(colors) { color in
                        Swatch(model:model,color:color,kind:kind)
                            .transition(.scale(scale:0.92).combined(with:.opacity))
                    }
                }.frame(minHeight:colors.isEmpty ? 14:0)
                    .overlay(alignment:.topLeading) {
                        if colors.isEmpty {
                            Text(kind == .pinned ? "Drag a color here or use Pin.":"Your selected colors appear here.")
                                .font(.system(size:11)).foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        }
                    }
        }.contentShape(Rectangle())
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius:DroppyRadius.small).fill(.white.opacity(0.035)).allowsHitTesting(false)
                }
            }
            .background {
                if kind != .suggestion {
                    NativeSwatchInteraction(model:model,color:nil,dropEnabled:true,target:nil,onTarget:{ dropTargeted=$0 },section:kind)
                }
            }
            .animation(DroppyAnimation.listChange,value:colors)
    }
}
struct Swatch:View {
    @ObservedObject var model:ChromaDroplet
    let color:HexColor
    let kind:SwatchKind
    var tileHeight:CGFloat=32
    var vertical:Bool=false
    @State private var dropTargeted=false
    @State private var rename=false
    @State private var name=""
    var isPinned:Bool { model.library.pinned.contains(where:{$0.color==color}) }
    var isSelected:Bool { model.selected==color }
    var colorName:String { model.library.pinned.first(where:{$0.color==color})?.name ?? "" }
    var body:some View {
        Button { model.select(color) } label: {
            ColorTile(color:color).frame(height:tileHeight)
                .overlay(alignment:.bottom) {
                    Circle().fill(.white).frame(width:5,height:5)
                        .shadow(color:.black.opacity(0.65),radius:1)
                        .padding(.bottom,4)
                        .opacity(isSelected ? 1:0).scaleEffect(isSelected ? 1:0.7)
                        .allowsHitTesting(false)
                }
                .scaleEffect(isSelected ? 1:0.96)
                .animation(DroppyAnimation.hoverQuick,value:isSelected)
        }.opacity(model.draggedColor==color ? 0.18:1)
            .buttonStyle(ColorSurfaceButtonStyle()).focusEffectDisabled().frame(width:kind == .suggestion ? 34:nil)
            .help((colorName.isEmpty ? "":colorName+" · ")+color.hex+" · Click to select; drag to organize; right-click to manage")
            .accessibilityLabel("Select \(colorName.isEmpty ? color.hex:colorName+", "+color.hex)")
            .overlay {
                NativeSwatchInteraction(model:model,color:color,dropEnabled:kind != .suggestion,target:color,onTarget:{ dropTargeted=$0 },makeMenu:makeNativeMenu,section:kind,vertical:vertical)
            }
            .contextMenu {
                Button("Copy HEX") { model.copyHex(color) }
                Button("Select color") { model.select(color) }
                if isPinned {
                    Button("Unpin") { model.unpin(color) }
                    Button("Rename…") { name=colorName; rename=true }
                    if kind == .pinned {
                        Button("Move left") { move(-1) }.disabled(model.library.pinned.first?.color==color)
                        Button("Move right") { move(1) }.disabled(model.library.pinned.last?.color==color)
                    }
                } else { Button("Pin") { model.pin(color) } }
                if kind == .recent { Button("Remove from recent",role:.destructive) { model.mutate { $0.recent.removeAll { $0==color } } } }
            }
            .alert("Name this color",isPresented:$rename) {
                TextField("Optional name",text:$name)
                Button("Cancel",role:.cancel) {}
                Button("Save") { model.mutate { if let i=$0.pinned.firstIndex(where:{$0.color==color}) { $0.pinned[i].name=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(60)) } } }
            }
    }
    private func makeNativeMenu()->NSMenu {
        let menu=NSMenu(); menu.autoenablesItems=false
        func item(_ title:String,enabled:Bool=true,_ action:@escaping()->Void) {
            let entry=SwatchMenuItem(title:title,perform:action); entry.isEnabled=enabled; menu.addItem(entry)
        }
        item("Copy HEX") { model.copyHex(color) }
        item("Select color") { model.select(color) }
        if isPinned {
            item("Unpin") { model.unpin(color) }
            item("Rename…") { name=colorName; rename=true }
            if kind == .pinned {
                item("Move left",enabled:model.library.pinned.first?.color != color) { move(-1) }
                item("Move right",enabled:model.library.pinned.last?.color != color) { move(1) }
            }
        } else { item("Pin") { model.pin(color) } }
        if kind == .recent { item("Remove from recent") { model.mutate { $0.recent.removeAll { $0==color } } } }
        return menu
    }
    func move(_ offset:Int) {
        let pins=model.library.pinned
        guard let i=pins.firstIndex(where:{$0.color==color}),pins.indices.contains(i+offset) else { return }
        model.mutate { $0.movePin(color,to:pins[i+offset].color) }
    }

}

struct ChromaSettings:View {
    @ObservedObject var model:ChromaDroplet
    @State private var clear=false
    @State private var reset=false
    var body:some View {
        DropletSettingsPane {
            DropletSettingsCard {
                DropletControlRow(title:"Recent colors",icon:"clock") {
                    Stepper("\(model.library.settings.maximumRecent)",value:Binding(get:{model.library.settings.maximumRecent},set:{value in model.updateSetting { $0.maximumRecent=value }}),in:1...300).fixedSize()
                }
                DropletToggleRow(title:"Include # prefix",icon:"number",isOn:Binding(get:{model.library.settings.includePrefix},set:{v in model.updateSetting { $0.includePrefix=v }}))
                DropletToggleRow(title:"Detect clipboard colors",icon:"doc.on.clipboard",subtitle:"Checks when the picker opens or becomes active. Never copies automatically.",isOn:Binding(get:{model.library.settings.detectClipboard},set:{v in model.updateSetting { $0.detectClipboard=v }}))
                DropletToggleRow(title:"Show copy confirmation",icon:"checkmark",isOn:Binding(get:{model.library.settings.showConfirmation},set:{v in model.updateSetting { $0.showConfirmation=v }}))
            }
            DropletSettingsCard {
                DropletControlRow(title:"Clear recent history",icon:"trash",infoTip:"Keeps all pinned colors and palettes.") { Button("Clear…",role:.destructive) { clear=true }.disabled(model.library.recent.isEmpty) }
                DropletControlRow(title:"Reset preferences",icon:"arrow.counterclockwise",infoTip:"Restores preferences. Keeps saved colors and palettes.") { Button("Reset…") { reset=true } }
            }
        }
        .alert("Clear recent colors?",isPresented:$clear) { Button("Cancel",role:.cancel) {}; Button("Clear",role:.destructive) { model.flushEdit(); model.mutate { $0.recent=[] } } } message:{ Text("Pinned colors and palettes will be kept.") }
        .alert("Reset preferences?",isPresented:$reset) { Button("Cancel",role:.cancel) {}; Button("Reset") { model.mutate { $0.settings=Preferences() }; model.checkClipboard() } } message:{ Text("Your colors and palettes will be kept.") }
    }
}


struct CopyShortcut:NSViewRepresentable {
    let action:@MainActor ()->Void
    @MainActor final class Coordinator {
        var monitor:Any?
        var action:@MainActor ()->Void
        init(action:@escaping @MainActor ()->Void) { self.action=action }
    }
    func makeCoordinator()->Coordinator { Coordinator(action:action) }
    func makeNSView(context:Context)->NSView {
        let view=NSView()
        context.coordinator.monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak view, weak coordinator=context.coordinator] event in
            guard let view,let window=view.window,event.window === window,window.isKeyWindow,
                  !(window.firstResponder is NSTextView),event.modifierFlags.intersection(.deviceIndependentFlagsMask)==[.command],event.charactersIgnoringModifiers?.lowercased()=="c" else { return event }
            coordinator?.action(); return nil
        }
        return view
    }
    func updateNSView(_ view:NSView,context:Context) { context.coordinator.action=action }
    static func dismantleNSView(_ view:NSView,coordinator:Coordinator) { if let monitor=coordinator.monitor { NSEvent.removeMonitor(monitor) }; coordinator.monitor=nil }
}
