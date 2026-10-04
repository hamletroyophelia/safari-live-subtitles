import SwiftUI
import Translation

private let ink = Color(red: 0.91, green: 0.92, blue: 0.95)
private let accent = Color(red: 0.70, green: 0.76, blue: 1)
private let canvas = Color(red: 0.075, green: 0.085, blue: 0.11)

struct MainView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            HStack(alignment: .top, spacing: 20) {
                controls.frame(width: 248)
                VStack(alignment: .leading, spacing: 14) {
                    monitor
                    transcript
                }
            }
            HStack {
                Label("本机识别与翻译", systemImage: "lock.shield")
                Text("·").foregroundStyle(.secondary)
                Text("无需 YouTube CC")
                Spacer()
                Text("LiveLingo 0.3").foregroundStyle(.secondary)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(28)
        .foregroundStyle(ink)
        .background(canvas)
        .preferredColorScheme(.dark)
        .frame(minWidth: 840, minHeight: 660)
        .translationTask(model.translationConfiguration) { session in
            await model.runTranslation(session: session)
        }
        .onChange(of: model.fontSize) { _, _ in model.savePreferences() }
        .onChange(of: model.backgroundOpacity) { _, _ in model.savePreferences() }
        .onChange(of: model.glossaryEnabled) { _, _ in model.savePreferences() }
        .onChange(of: model.glossaryProfileID) { _, _ in model.savePreferences() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("LIVE LINGO").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(3).foregroundStyle(accent)
                Text("听见直播，看懂每一句。")
                    .font(.system(size: 25, weight: .semibold))
                Text("Safari 实时双语字幕 · 日语 / 英语 → 简体中文")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: 33)).foregroundStyle(accent)
                .padding(15).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var controls: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("声音与语言")
            VStack(alignment: .leading, spacing: 5) {
                Text("听哪个应用").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("声音来源", selection: $model.captureSource) {
                    ForEach(CaptureSource.allCases) { source in Text(source.title).tag(source) }
                }.labelsHidden().disabled(model.busy)
                Text(model.captureSource == .safari ? "直接读取 Safari，不改变扬声器输出。" : "会识别其他应用的声音，请关闭无关音频。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("直播原语言").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("直播语言", selection: $model.language) {
                    ForEach(SourceLanguage.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().disabled(model.busy)
            }
            Button(action: { model.busy ? model.stop() : model.start() }) {
                HStack {
                    Image(systemName: model.busy ? "stop.fill" : "play.fill")
                    Text(model.isStopping ? "正在停止…" : model.busy ? "停止字幕" : "开始字幕")
                    Spacer()
                    if model.isPreparing { ProgressView().controlSize(.small) }
                }.font(.system(size: 13, weight: .semibold)).padding(.vertical, 9).padding(.horizontal, 11)
            }
            .buttonStyle(.plain)
            .background(model.busy ? Color.white.opacity(0.12) : accent.opacity(0.92), in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(model.busy ? ink : canvas)
            .disabled(model.isStopping)
            Button("准备语言模型") { model.prepareModels() }
                .controlSize(.small).disabled(model.busy)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Toggle("游戏术语词典", isOn: $model.glossaryEnabled)
                    .toggleStyle(.checkbox).font(.system(size: 11, weight: .semibold))
                    .disabled(model.busy || model.glossaryProfiles.isEmpty)
                Picker("游戏分类", selection: $model.glossaryProfileID) {
                    ForEach(model.glossaryProfiles) { Text($0.displayName).tag($0.id) }
                }.labelsHidden().disabled(model.busy || !model.glossaryEnabled)
                Text("\(model.glossaryLabel) · \(model.glossaryStatus)")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("导入 JSON") { model.importGlossary() }
                    Button("恢复内置") { model.resetGlossary() }
                    Button("试译") { model.tryGlossaryText() }
                }.controlSize(.mini).disabled(model.busy)
                Text("综合覆盖全部游戏；冲突仅提示。切换前先停止字幕。")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                if #unavailable(macOS 26.4) {
                    Text("当前系统仅显示术语对照；保护译名需 macOS 26.4。")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                sectionLabel("悬浮字幕")
                Spacer()
                Toggle("自动高度", isOn: $model.overlayAutoHeight).toggleStyle(.checkbox).controlSize(.mini)
                    .font(.system(size: 10)).help("手动拖动缩放后关闭，勾选可恢复随内容调整高度")
            }
            Toggle("显示字幕窗", isOn: Binding(get: { model.overlayVisible }, set: { model.setOverlay(visible: $0) }))
                .toggleStyle(.switch).controlSize(.small)
            Toggle("鼠标穿透", isOn: Binding(get: { model.overlayLocked }, set: { model.setLocked($0) }))
                .toggleStyle(.switch).controlSize(.small)
            Text(model.overlayLocked ? "字幕不挡点击，可从菜单栏解锁。" : "拖动顶部移动位置；右下角拖动调整宽高。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            VStack(spacing: 5) {
                HStack { Text("字号"); Spacer(); Text("\(Int(model.fontSize))") }
                Slider(value: $model.fontSize, in: 16...42, step: 1)
                HStack { Text("背景深度"); Spacer(); Text("\(Int(model.backgroundOpacity * 100))%") }
                Slider(value: $model.backgroundOpacity, in: 0.25...1)
            }.font(.system(size: 11)).tint(accent)
            HStack {
                Button("预览外观") { model.preview() }.disabled(model.busy)
                Button("重置位置") { model.onResetOverlay?() }
            }.controlSize(.small)
            Spacer(minLength: 0)
            Button { model.openPrivacySettings() } label: {
                Label("音频捕获权限设置", systemImage: "gearshape")
            }.buttonStyle(.link).font(.system(size: 11))
        }
        }
        .padding(17).frame(maxHeight: .infinity)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private var monitor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(model.isRunning ? Color.green : model.isDemo ? accent : Color.gray)
                    .frame(width: 7, height: 7)
                Text(model.phase).font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.isDemo { Text(model.isTextTrial ? "文字试译" : "演示").font(.system(size: 10, weight: .bold)).foregroundStyle(accent) }
            }
            Text(model.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = model.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(Color(red: 1, green: 0.64, blue: 0.58))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if let progress = model.downloadProgress { ProgressView(value: progress).tint(accent) }
            HStack(spacing: 4) {
                Text("输入").font(.system(size: 10)).foregroundStyle(.secondary).padding(.trailing, 4)
                ForEach(0..<26) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(model.audioLevel > Double(index) / 26 ? accent : Color.white.opacity(0.08))
                        .frame(width: 5, height: 13)
                }
                Spacer()
                if let seconds = model.translationSeconds {
                    Text(String(format: "译文 %.1fs", seconds)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }.padding(17).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("字幕记录")
                Spacer()
                Button { model.exportSRT() } label: { Label("导出 SRT", systemImage: "square.and.arrow.up") }
                    .controlSize(.small).disabled(model.captions.isEmpty || model.isDemo)
            }
            if model.captions.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "waveform").font(.system(size: 35)).foregroundStyle(accent.opacity(0.6))
                    Text("等一句声音，亮起两行字幕。")
                        .font(.system(size: 15, weight: .medium))
                    Text("先播放 YouTube 直播，再点击开始字幕。\n首次使用请完成系统权限与模型下载。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(model.captions.suffix(80).reversed()) { caption in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(CaptionStore.timestamp(caption.start).prefix(8)).font(.system(size: 9, design: .monospaced))
                                    if !caption.isFinal { Text("识别中").font(.system(size: 9)) }
                                }.foregroundStyle(.tertiary)
                                Text(caption.source).font(.system(size: 13)).foregroundStyle(.secondary)
                                Text(caption.translation.isEmpty ? "正在翻译…" : caption.translation)
                                    .font(.system(size: 15, weight: .medium)).foregroundStyle(caption.translation.isEmpty ? Color.gray : ink)
                                if !caption.termNotes.isEmpty {
                                    Text(CaptionDisplay.terms(caption)).font(.system(size: 10)).foregroundStyle(accent)
                                    if caption.glossaryFallback {
                                        Text("本句术语保护未通过，已回退为原文翻译；词典仅供对照。")
                                            .font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                }
                            }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            Divider().overlay(.white.opacity(0.03))
                        }
                    }
                }
                Text("最新在上 · 窗口显示最近 80 条 · 导出最多 2000 条")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }.padding(17).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
    }
}

struct OverlayView: View {
    @ObservedObject var model: AppModel
    private var termHeight: Double { model.current?.termNotes.isEmpty == false ? 18 : 0 }
    private var sourceLines: Int { model.overlayAutoHeight ? 3 : max(1, min(3, Int((model.overlayHeight - 66 - termHeight) * 0.42 / (model.fontSize * 0.92)))) }
    private var targetLines: Int { model.overlayAutoHeight ? 3 : max(1, min(3, Int((model.overlayHeight - 66 - termHeight) * 0.58 / (model.fontSize * 1.24)))) }
    private var status: String {
        if model.isDemo { return model.isTextTrial ? "词典文字试译 · 未读取音频" : "字幕预览 · 演示文字" }
        if !model.busy { return "字幕已停止" }
        if model.isPreparing { return "正在准备" }
        guard let caption = model.current else { return "\(model.language.title) → 中文 · 等待语音" }
        if !caption.isFinal { return "\(model.language.title) → 中文 · 实时更新" }
        if caption.translatedSource != caption.source { return "\(model.language.title) → 中文 · 正在翻译" }
        return "\(model.language.title) → 中文"
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                PanelHandle(kind: .move)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal").font(.system(size: 11))
                            Circle().fill(model.isRunning ? Color.green : accent).frame(width: 5, height: 5)
                            Text(status).font(.system(size: 10, weight: .medium))
                        }.foregroundStyle(.white.opacity(0.50)).allowsHitTesting(false)
                    }.frame(maxWidth: .infinity).frame(height: 18)
                    .help("按住顶部拖动条移动字幕窗")
                if !model.overlayLocked {
                    Button { model.toggleLock() } label: { Image(systemName: "cursorarrow.slash").font(.system(size: 11)) }
                        .help("鼠标穿透；从主窗口或菜单栏解锁")
                    Button { model.setOverlay(visible: false) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                        .help("隐藏字幕窗")
                }
            }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.55))
            VStack(spacing: 6) {
                if let caption = model.current {
                    Text(CaptionDisplay.source(caption, width: model.overlayWidth, fontSize: model.fontSize))
                        .font(.system(size: model.fontSize * 0.74, weight: .medium))
                        .foregroundStyle(.white.opacity(0.76)).lineLimit(sourceLines).truncationMode(.head)
                    Text(caption.translation.isEmpty ? "正在翻译…" : CaptionDisplay.target(caption, width: model.overlayWidth, fontSize: model.fontSize))
                        .font(.system(size: model.fontSize, weight: .semibold))
                        .foregroundStyle(caption.translation.isEmpty ? .white.opacity(0.45) : .white)
                        .lineLimit(targetLines).truncationMode(.head)
                    if !caption.termNotes.isEmpty {
                        Text(CaptionDisplay.terms(caption)).font(.system(size: 10)).foregroundStyle(accent.opacity(0.8))
                            .lineLimit(1).truncationMode(.tail).help(CaptionDisplay.terms(caption))
                    }
                } else {
                    Text(model.isPreparing ? "正在准备语言模型…" : "等待直播语音…")
                        .font(.system(size: model.fontSize * 0.8)).foregroundStyle(.white.opacity(0.65))
                    Text("无需直播自带字幕").font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22).padding(.vertical, 13)
        .background(Color.black.opacity(model.backgroundOpacity), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            if !model.overlayLocked {
                PanelHandle(kind: .resize) { model.overlayAutoHeight = false }
                    .frame(width: 26, height: 26).padding(5)
                    .help("按住右下角拖动，调整字幕窗宽度和高度")
            }
        }
        .padding(2).preferredColorScheme(.dark)
    }
}
