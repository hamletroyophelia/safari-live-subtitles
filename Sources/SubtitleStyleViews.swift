import SwiftUI

/// Shared by the live panel and the settings preview; dictionary diagnostics never enter this view.
struct SubtitleTextView: View {
    let caption: Caption
    let style: SubtitleStyle
    let targetSize: Double
    let width: Double
    let height: Double
    let automatic: Bool

    private var source: some View {
        Text(CaptionDisplay.source(caption, width: width, fontSize: style.sourceFontSize))
            .font(.system(size: style.sourceFontSize, weight: style.sourceWeight.weight, design: style.fontDesign.design))
            .foregroundStyle(SubtitleColor.color(style.sourceColor))
            .lineLimit(style.lineLimit(source: true, height: height, targetSize: targetSize, automatic: automatic))
            .truncationMode(.head).frame(maxWidth: .infinity, alignment: style.alignment.alignment)
    }
    private var target: some View {
        Text(caption.translation.isEmpty ? "正在翻译…" : CaptionDisplay.target(caption, width: width, fontSize: targetSize))
            .font(.system(size: targetSize, weight: style.targetWeight.weight, design: style.fontDesign.design))
            .foregroundStyle(SubtitleColor.color(style.targetColor).opacity(caption.translation.isEmpty ? 0.45 : 1))
            .lineLimit(style.lineLimit(source: false, height: height, targetSize: targetSize, automatic: automatic))
            .truncationMode(.head).frame(maxWidth: .infinity, alignment: style.alignment.alignment)
    }
    var body: some View {
        VStack(alignment: style.alignment.horizontal, spacing: style.spacing) {
            if style.showSource && !style.translationFirst { source }
            target
            if style.showSource && style.translationFirst { source }
        }
        .multilineTextAlignment(style.alignment.textAlignment)
        .shadow(color: .black.opacity(style.textShadow > 0 ? 0.9 : 0), radius: style.textShadow, y: style.textShadow > 0 ? 1 : 0)
    }
}

struct SubtitleStyleEditor: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private func color(_ key: WritableKeyPath<SubtitleStyle, String>) -> Binding<Color> {
        Binding(get: { SubtitleColor.color(model.subtitleStyle[keyPath: key]) },
                set: { model.subtitleStyle[keyPath: key] = SubtitleColor.hex($0) })
    }
    private var sample: Caption {
        Caption(id: UUID(), start: 0, end: 1,
                source: model.language == .japanese ? "戦灰を変えて、次のボスに挑もう。" : "Change the Ash of War and challenge the next boss.",
                translation: "换上战灰，挑战下一个首领。", isFinal: true)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("字幕样式").font(.title2.bold())
                Spacer()
                Text("实时生效 · 自动保存").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 7) {
                HStack { Text("样式预览 · 演示文字").font(.caption).foregroundStyle(.secondary); Spacer() }
                SubtitleTextView(caption: sample, style: model.subtitleStyle, targetSize: model.fontSize,
                                 width: 580, height: 180, automatic: true)
                    .padding(18).frame(maxWidth: .infinity, minHeight: 115)
                    .background(SubtitleColor.color(model.subtitleStyle.backgroundColor).opacity(model.backgroundOpacity),
                                in: RoundedRectangle(cornerRadius: model.subtitleStyle.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: model.subtitleStyle.cornerRadius)
                        .stroke(.white.opacity(model.subtitleStyle.showsBorder ? 0.1 : 0), lineWidth: 1))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("预设").font(.headline)
                        ForEach(SubtitlePreset.allCases) { preset in
                            Button(preset.title) { model.applySubtitlePreset(preset) }
                        }
                    }
                    GroupBox("文字") {
                        VStack(spacing: 12) {
                            HStack {
                                Picker("字体", selection: $model.subtitleStyle.fontDesign) {
                                    ForEach(SubtitleFontDesign.allCases) { Text($0.title).tag($0) }
                                }
                                Picker("对齐", selection: $model.subtitleStyle.alignment) {
                                    ForEach(SubtitleAlignment.allCases) { Text($0.title).tag($0) }
                                }
                            }
                            HStack(alignment: .top, spacing: 22) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("原文").font(.headline)
                                    sizeControl("原文字号", value: $model.subtitleStyle.sourceFontSize, range: 12...36)
                                    ColorPicker("原文颜色", selection: color(\.sourceColor), supportsOpacity: false)
                                    Picker("原文粗细", selection: $model.subtitleStyle.sourceWeight) {
                                        ForEach(SubtitleWeight.allCases) { Text($0.title).tag($0) }
                                    }
                                }.frame(maxWidth: .infinity)
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("中文").font(.headline)
                                    sizeControl("中文字号", value: $model.fontSize, range: 16...48)
                                    ColorPicker("中文颜色", selection: color(\.targetColor), supportsOpacity: false)
                                    Picker("中文粗细", selection: $model.subtitleStyle.targetWeight) {
                                        ForEach(SubtitleWeight.allCases) { Text($0.title).tag($0) }
                                    }
                                }.frame(maxWidth: .infinity)
                            }
                            HStack {
                                Toggle("显示原文", isOn: $model.subtitleStyle.showSource).toggleStyle(.checkbox)
                                Spacer()
                                Picker("显示顺序", selection: $model.subtitleStyle.translationFirst) {
                                    Text("原文在上").tag(false)
                                    Text("中文在上").tag(true)
                                }.disabled(!model.subtitleStyle.showSource).frame(width: 230)
                            }
                            sizeControl("两行间距", value: $model.subtitleStyle.spacing, range: 0...20)
                            sizeControl("文字阴影", value: $model.subtitleStyle.textShadow, range: 0...4)
                        }.padding(10)
                    }
                    GroupBox("背景") {
                        VStack(spacing: 12) {
                            HStack {
                                ColorPicker("背景颜色", selection: color(\.backgroundColor), supportsOpacity: false)
                                Spacer()
                                Toggle("细边框", isOn: $model.subtitleStyle.showsBorder).toggleStyle(.checkbox)
                            }
                            HStack {
                                Text("背景不透明度")
                                Slider(value: $model.backgroundOpacity, in: 0...1)
                                Text("\(Int((model.backgroundOpacity * 100).rounded()))%").monospacedDigit().frame(width: 40)
                            }
                            sizeControl("圆角", value: $model.subtitleStyle.cornerRadius, range: 0...28)
                        }.padding(10)
                    }
                    Text("样式只影响悬浮字幕；识别原文、词典译名和 SRT 内容保持不变。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.trailing, 6)
            }
            HStack {
                Button("恢复默认样式") { model.applySubtitlePreset(.dark) }
                Spacer()
                Button("完成") { model.savePreferences(); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 640, height: 650).preferredColorScheme(.dark)
        .onChange(of: model.subtitleStyle) { _, _ in model.savePreferences() }
        .onChange(of: model.fontSize) { _, _ in model.savePreferences() }
        .onChange(of: model.backgroundOpacity) { _, _ in model.savePreferences() }
    }
    private func sizeControl(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range, step: 1).accessibilityLabel(title)
            Text("\(Int(value.wrappedValue.rounded()))").monospacedDigit().frame(width: 28)
        }
    }
}
