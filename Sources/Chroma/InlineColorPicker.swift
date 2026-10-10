import SwiftUI
import DroppyKit

struct InlineColorPicker:View {
    @ObservedObject var model:ChromaDroplet
    var planeHeight:CGFloat=120
    @State private var hue=0.0
    @State private var tracking=false
    private var hsv:(hue:Double,saturation:Double,brightness:Double,alpha:Double) { model.selected.hsv }
    private var hueColor:Color { HexColor.hsv(hue:hue,saturation:1,brightness:1,alpha:1).swiftColor }
    var body:some View {
        VStack(spacing:DroppySpacing.sm) {
            GeometryReader { geometry in
                ZStack(alignment:.topLeading) {
                    LinearGradient(colors:[.white,hueColor],startPoint:.leading,endPoint:.trailing)
                        .animation(DroppyAnimation.hoverQuick,value:hue)
                    LinearGradient(colors:[.clear,.black],startPoint:.top,endPoint:.bottom)
                    Circle().fill(model.selected.swiftColor).frame(width:14,height:14)
                        .overlay(Circle().stroke(.white,lineWidth:2))
                        .shadow(color:.black.opacity(0.5),radius:2)
                        .position(x:CGFloat(hsv.saturation)*geometry.size.width,y:CGFloat(1-hsv.brightness)*geometry.size.height)
                        .animation(DroppyAnimation.state, value:model.selected)
                        .allowsHitTesting(false)
                }.clipShape(RoundedRectangle(cornerRadius:DroppyRadius.medium,style:.continuous))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0)
                        .onChanged { value in
                            tracking=true
                            let s=min(1,max(0,value.location.x/max(1,geometry.size.width)))
                            let v=1-min(1,max(0,value.location.y/max(1,geometry.size.height)))
                            model.previewVisual(.hsv(hue:hue,saturation:s,brightness:v,alpha:hsv.alpha))
                        }
                        .onEnded { _ in tracking=false; model.select(model.selected) })
                    .focusable().focusEffectDisabled()
                    .onKeyPress(.leftArrow) { adjust(s:-0.01,v:0); return .handled }
                    .onKeyPress(.rightArrow) { adjust(s:0.01,v:0); return .handled }
                    .onKeyPress(.upArrow) { adjust(s:0,v:0.01); return .handled }
                    .onKeyPress(.downArrow) { adjust(s:0,v:-0.01); return .handled }
                    .accessibilityElement().accessibilityLabel("Color picker")
                    .accessibilityValue(model.selected.hex)
                    .accessibilityHint("Click or drag to select saturation and brightness. Arrow keys adjust the color.")
                    .help("Click or drag to choose a color")
            }.frame(height:planeHeight)
            GeometryReader { geometry in
                ZStack(alignment:.leading) {
                    LinearGradient(colors:(0...6).map { Color(hue:Double($0)/6,saturation:1,brightness:1) },startPoint:.leading,endPoint:.trailing)
                        .frame(height:10).clipShape(Capsule())
                    Circle().fill(hueColor).frame(width:16,height:16).overlay(Circle().stroke(.white,lineWidth:2))
                        .shadow(color:.black.opacity(0.4),radius:1)
                        .offset(x:CGFloat(hue)*max(0,geometry.size.width-16))
                        .animation(DroppyAnimation.state, value:hue)
                        .allowsHitTesting(false)
                }.frame(height:16).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0)
                        .onChanged { value in
                            tracking=true; hue=min(1,max(0,value.location.x/max(1,geometry.size.width)))
                            model.previewVisual(.hsv(hue:hue,saturation:hsv.saturation,brightness:hsv.brightness,alpha:hsv.alpha))
                        }
                        .onEnded { _ in tracking=false; model.select(model.selected) })
                    .accessibilityElement().accessibilityLabel("Hue")
                    .accessibilityValue("\(Int(hue*360)) degrees")
                    .accessibilityAdjustableAction { direction in
                        hue=min(1,max(0,hue+(direction == .increment ? 1/360 : -1/360)))
                        model.select(.hsv(hue:hue,saturation:hsv.saturation,brightness:hsv.brightness,alpha:hsv.alpha))
                    }
                    .help("Drag to change the hue")
            }.frame(height:16)
        }
        .onAppear { hue=hsv.hue }
        .onChange(of:model.selected) { _,_ in if !tracking && hsv.saturation>0 && hsv.brightness>0 { hue=hsv.hue } }
    }
    private func adjust(s:Double,v:Double) { model.select(.hsv(hue:hue,saturation:hsv.saturation+s,brightness:hsv.brightness+v,alpha:hsv.alpha)) }
}
