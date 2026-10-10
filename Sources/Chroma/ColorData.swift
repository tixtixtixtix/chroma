import Foundation

public struct HexColor: Codable, Hashable, Sendable, Identifiable {
    public let hex: String
    public var id: String { hex }
    public init?(_ text: String) {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard [3, 6, 8].contains(raw.count), raw.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        if raw.count == 3 { raw = raw.map { "\($0)\($0)" }.joined() }
        raw = raw.uppercased()
        // Opaque alpha is the same color as its six-digit form.
        if raw.count == 8, raw.hasSuffix("FF") { raw = String(raw.prefix(6)) }
        hex = "#" + raw
    }
    public var components: (Double, Double, Double, Double) {
        let n = UInt64(hex.dropFirst(), radix: 16) ?? 0
        let alpha = hex.count == 9
        let rgb = alpha ? n >> 8 : n
        return (Double((rgb >> 16) & 255)/255, Double((rgb >> 8) & 255)/255, Double(rgb & 255)/255, alpha ? Double(n & 255)/255 : 1)
    }
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v.isFinite ? v : 0)) * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        self = HexColor(rgb + (byte(alpha) == 255 ? "" : String(format: "%02X", byte(alpha))))!
    }
    public func copyText(prefix: Bool) -> String { prefix ? hex : String(hex.dropFirst()) }
    public func rotatedHue(_ offset: Double) -> HexColor {
        let (r,g,b,a) = components
        let maxV = max(r,g,b), minV = min(r,g,b), d = maxV-minV
        var h = 0.0
        if d > 0 {
            if maxV == r { h = (g-b)/d }
            else if maxV == g { h = (b-r)/d+2 }
            else { h = (r-g)/d+4 }
            h /= 6
        }
        h = (h + offset).truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        let s = maxV == 0 ? 0 : d/maxV
        let i = Int(h*6), f = h*6-Double(i), p = maxV*(1-s), q = maxV*(1-f*s), t = maxV*(1-(1-f)*s)
        let c: (Double,Double,Double)
        switch i % 6 { case 0: c=(maxV,t,p); case 1: c=(q,maxV,p); case 2: c=(p,maxV,t); case 3: c=(p,q,maxV); case 4: c=(t,p,maxV); default: c=(maxV,p,q) }
        return HexColor(red:c.0,green:c.1,blue:c.2,alpha:a)
    }
}

public struct SavedColor: Codable, Identifiable, Equatable, Sendable {
    public var color: HexColor
    public var name: String = ""
    public var id: String { color.hex }
}
public struct Palette: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var colors: [HexColor] = []
}
public struct Preferences: Codable, Equatable, Sendable {
    public var maximumRecent = 27
    public var includePrefix = true
    public var detectClipboard = true
    public var showConfirmation = true
}
public struct ColorLibrary: Codable, Equatable, Sendable {
    public var selected = HexColor("#7C6FF0")!
    public var recent: [HexColor] = []
    public var pinned: [SavedColor] = []
    public var palettes: [Palette] = []
    public var settings = Preferences()
    public init() {}
    public mutating func select(_ color: HexColor) {
        selected = color
        recent.removeAll { $0 == color }
        recent.insert(color, at:0)
        trim()
    }
    public mutating func trim() {
        settings.maximumRecent = min(300, max(1,settings.maximumRecent))
        recent = Array(recent.prefix(settings.maximumRecent))
    }
    public mutating func pin(_ color: HexColor) {
        guard !pinned.contains(where: { $0.color == color }) else { return }
        pinned.append(SavedColor(color:color))
    }
    public mutating func unpin(_ color: HexColor) {
        pinned.removeAll { $0.color == color }
        for i in palettes.indices { palettes[i].colors.removeAll { $0 == color } }
    }
    public mutating func add(_ color: HexColor, to palette: UUID) {
        guard let i = palettes.firstIndex(where: { $0.id == palette }) else { return }
        pin(color)
        if !palettes[i].colors.contains(color) { palettes[i].colors.append(color) }
    }
    public mutating func movePin(_ color: HexColor, to target: HexColor) {
        guard let from = pinned.firstIndex(where:{$0.color==color}), let to=pinned.firstIndex(where:{$0.color==target}), from != to else { return }
        let item = pinned.remove(at:from); pinned.insert(item,at:to)
    }
    public mutating func movePaletteColor(_ color: HexColor, to target: HexColor, palette: UUID) {
        guard let i = palettes.firstIndex(where:{$0.id==palette}), let from=palettes[i].colors.firstIndex(of:color), let to=palettes[i].colors.firstIndex(of:target), from != to else { return }
        let item=palettes[i].colors.remove(at:from); palettes[i].colors.insert(item,at:to)
    }
    public mutating func sanitize() {
        func unique(_ colors:[HexColor]) -> [HexColor] { var seen=Set<HexColor>(); return colors.filter { seen.insert($0).inserted } }
        recent=unique(recent)
        var seen=Set<HexColor>(); pinned=pinned.filter { seen.insert($0.color).inserted }
        for i in palettes.indices { palettes[i].colors=unique(palettes[i].colors); for color in palettes[i].colors { pin(color) } }
        trim()
    }
}

extension HexColor {
    var hsv:(hue:Double,saturation:Double,brightness:Double,alpha:Double) {
        let (r,g,b,a)=components
        let high=max(r,g,b),low=min(r,g,b),delta=high-low
        var h=0.0
        if delta>0 {
            if high==r { h=(g-b)/delta }
            else if high==g { h=(b-r)/delta+2 }
            else { h=(r-g)/delta+4 }
            h=(h/6+1).truncatingRemainder(dividingBy:1)
        }
        return (h,high==0 ? 0:delta/high,high,a)
    }
    static func hsv(hue:Double,saturation:Double,brightness:Double,alpha:Double)->HexColor {
        let h=min(1,max(0,hue)),s=min(1,max(0,saturation)),v=min(1,max(0,brightness))
        let sector=Int(h*6),f=h*6-Double(sector),p=v*(1-s),q=v*(1-f*s),t=v*(1-(1-f)*s)
        let c:(Double,Double,Double)
        switch sector%6 { case 0:c=(v,t,p); case 1:c=(q,v,p); case 2:c=(p,v,t); case 3:c=(p,q,v); case 4:c=(t,p,v); default:c=(v,p,q) }
        return HexColor(red:c.0,green:c.1,blue:c.2,alpha:alpha)
    }
}
