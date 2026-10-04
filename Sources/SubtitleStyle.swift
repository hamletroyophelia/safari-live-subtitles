import AppKit
import SwiftUI

enum SubtitleFontDesign: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif
    var id: String { rawValue }
    var title: String { switch self { case .system: return "系统黑体"; case .rounded: return "圆角"; case .serif: return "衬线" } }
    var design: Font.Design { switch self { case .system: return .default; case .rounded: return .rounded; case .serif: return .serif } }
    func nativeFont(size: Double, weight: SubtitleWeight) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight.nativeWeight)
        let design: NSFontDescriptor.SystemDesign = self == .rounded ? .rounded : self == .serif ? .serif : .default
        return font.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? font
    }
}

enum SubtitleWeight: String, Codable, CaseIterable, Identifiable {
    case regular, medium, semibold, bold
    var id: String { rawValue }
    var title: String { switch self { case .regular: return "常规"; case .medium: return "中等"; case .semibold: return "半粗"; case .bold: return "粗体" } }
    var weight: Font.Weight { switch self { case .regular: return .regular; case .medium: return .medium; case .semibold: return .semibold; case .bold: return .bold } }
    var nativeWeight: NSFont.Weight { switch self { case .regular: return .regular; case .medium: return .medium; case .semibold: return .semibold; case .bold: return .bold } }
}

enum SubtitleAlignment: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing
    var id: String { rawValue }
    var title: String { switch self { case .leading: return "左对齐"; case .center: return "居中"; case .trailing: return "右对齐" } }
    var textAlignment: TextAlignment { switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing } }
    var alignment: Alignment { switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing } }
    var horizontal: HorizontalAlignment { switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing } }
}

enum SubtitleColor {
    static func validHex(_ hex: String) -> Bool { hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }
    static func color(_ hex: String) -> Color {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
        return Color(.sRGB, red: Double(value >> 16) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    static func hex(_ color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        func channel(_ component: CGFloat) -> Int { Int((min(1, max(0, component)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(rgb.redComponent), channel(rgb.greenComponent), channel(rgb.blueComponent))
    }
}

struct SubtitleStyle: Codable, Equatable {
    var sourceFontSize = 18.5
    var fontDesign: SubtitleFontDesign = .system
    var sourceWeight: SubtitleWeight = .medium
    var targetWeight: SubtitleWeight = .semibold
    var sourceColor = "#C2C2C2"
    var targetColor = "#FFFFFF"
    var backgroundColor = "#000000"
    var alignment: SubtitleAlignment = .center
    var showSource = true
    var translationFirst = false
    var spacing = 6.0
    var cornerRadius = 16.0
    var textShadow = 0.0
    var showsBorder = true

    static func initial(targetSize: Double) -> Self {
        var style = Self()
        style.sourceFontSize = targetSize * 0.74
        return style.normalized()
    }

    func normalized() -> Self {
        var copy = self
        func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        copy.sourceFontSize = clamp(sourceFontSize, 12...36, fallback: 18.5)
        copy.spacing = clamp(spacing, 0...20, fallback: 6)
        copy.cornerRadius = clamp(cornerRadius, 0...28, fallback: 16)
        copy.textShadow = clamp(textShadow, 0...4, fallback: 0)
        if !SubtitleColor.validHex(sourceColor) { copy.sourceColor = "#C2C2C2" }
        if !SubtitleColor.validHex(targetColor) { copy.targetColor = "#FFFFFF" }
        if !SubtitleColor.validHex(backgroundColor) { copy.backgroundColor = "#000000" }
        return copy
    }

    func minimumHeight(targetSize: Double) -> Double {
        max(105, ceil(62 + (showSource ? spacing + lineHeight(source: true, targetSize: targetSize) : 0)
            + lineHeight(source: false, targetSize: targetSize)))
    }

    private func lineHeight(source: Bool, targetSize: Double) -> Double {
        let font = fontDesign.nativeFont(size: source ? sourceFontSize : targetSize, weight: source ? sourceWeight : targetWeight)
        return ceil(NSLayoutManager().defaultLineHeight(for: font)) + 3
    }

    func lineLimit(source: Bool, height: Double, targetSize: Double, automatic: Bool) -> Int {
        if automatic { return 3 }
        let available = max(1, height - 62 - (showSource ? spacing : 0))
        let sourceHeight = lineHeight(source: true, targetSize: targetSize)
        let targetHeight = lineHeight(source: false, targetSize: targetSize)
        let rowHeight = source ? sourceHeight : targetHeight
        let share = showSource ? rowHeight / (sourceHeight + targetHeight) : 1
        return max(1, min(3, Int(available * share / rowHeight)))
    }
}

enum SubtitlePreset: String, CaseIterable, Identifiable {
    case dark, transparent, chinese
    var id: String { rawValue }
    var title: String { switch self { case .dark: return "深色默认"; case .transparent: return "透明字幕"; case .chinese: return "中文突出" } }
}
