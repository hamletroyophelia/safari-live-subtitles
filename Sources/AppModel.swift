import AppKit
import Combine
import CoreGraphics
import Speech
import Translation
import UniformTypeIdentifiers

@MainActor final class AudioMeter: ObservableObject {
    @Published private(set) var level = 0.0
    func update(_ value: Double) {
        let next = ceil(min(1, max(0, value)) * 26) / 26
        if next != level { level = next }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var language: SourceLanguage = .japanese
    @Published var captureSource: CaptureSource = .safari
    @Published var phase = "准备就绪"
    @Published var detail = "在 Safari 播放直播，然后开始字幕。首次使用会下载语言模型。"
    @Published var isPreparing = false
    @Published var isRunning = false
    @Published var isStopping = false
    @Published var isDemo = false
    @Published var isTextTrial = false
    @Published var errorMessage: String?
    @Published var downloadProgress: Double?
    let audioMeter = AudioMeter()
    @Published var translationSeconds: Double?
    @Published var captions: [Caption] = []
    @Published private(set) var historyCount = 0
    @Published var overlayVisible = false
    @Published var overlayLocked = false
    @Published var fontSize = 25.0
    @Published var backgroundOpacity = 0.82
    @Published var subtitleStyle = SubtitleStyle()
    @Published var showingSubtitleStyle = false
    @Published var overlayWidth = 760.0
    @Published var overlayHeight = 130.0
    @Published var overlayAutoHeight = true
    var overlayOrigin: NSPoint?
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published var screenPermission = CGPreflightScreenCaptureAccess()
    @Published var glossaryEnabled = true
    @Published var glossaryProfileID = "all_games"
    @Published private(set) var glossaryProfiles: [GameProfile] = []
    @Published private(set) var glossaryStatus = ""
    @Published private(set) var glossaryLabel = "内置词典"
    private var glossary: GameGlossary?

    var onShowOverlay: (() -> Void)?
    var onHideOverlay: (() -> Void)?
    var onLockOverlay: ((Bool) -> Void)?
    var onResetOverlay: (() -> Void)?
    private let speech = SpeechEngine()
    private let capture = AudioCapture()
    private var store = CaptionStore()
    private var generation = UUID()
    private var translationInput: AsyncStream<Void>.Continuation?
    private var translationStream: AsyncStream<Void>?
    private var translationBacklog = TranslationBacklog()
    private var lastEnqueuedJob: TranslationJob?
    private var debounceTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var lastAudioTime = Date.distantPast
    private var lastPartialTranslationTime = Date.distantPast
    private var pendingPartial: Caption?
    private var modelsOnly = false
    private var trialText: String?
    private var lastTranslationConfiguration: TranslationSession.Configuration?

    var busy: Bool { isPreparing || isRunning || isStopping }
    var current: Caption? { captions.last }

    init() {
        let saved = UserDefaults.standard
        language = SourceLanguage(rawValue: saved.string(forKey: "sourceLanguage") ?? "") ?? .japanese
        fontSize = saved.object(forKey: "fontSize") == nil ? 25 : saved.double(forKey: "fontSize")
        backgroundOpacity = saved.object(forKey: "backgroundOpacity") == nil ? 0.82 : saved.double(forKey: "backgroundOpacity")
        fontSize = min(48, max(16, fontSize))
        backgroundOpacity = min(1, max(0, backgroundOpacity))
        subtitleStyle = saved.data(forKey: "subtitleStyle").flatMap { try? JSONDecoder().decode(SubtitleStyle.self, from: $0) }?.normalized()
            ?? .initial(targetSize: fontSize)
        overlayWidth = min(1600, max(440, saved.object(forKey: "overlayWidth") == nil ? 760 : saved.double(forKey: "overlayWidth")))
        overlayHeight = min(900, max(105, saved.object(forKey: "overlayHeight") == nil ? 130 : saved.double(forKey: "overlayHeight")))
        overlayAutoHeight = saved.object(forKey: "overlayAutoHeight") == nil ? true : saved.bool(forKey: "overlayAutoHeight")
        if saved.object(forKey: "overlayX") != nil, saved.object(forKey: "overlayY") != nil {
            overlayOrigin = NSPoint(x: saved.double(forKey: "overlayX"), y: saved.double(forKey: "overlayY"))
        }
        glossaryEnabled = saved.object(forKey: "glossaryEnabled") == nil ? true : saved.bool(forKey: "glossaryEnabled")
        glossaryProfileID = saved.string(forKey: "glossaryProfileID") ?? "all_games"
        do {
            let custom = try customGlossaryURL()
            if FileManager.default.fileExists(atPath: custom.path) {
                do {
                    try loadGlossary(from: custom, label: "自定义词典")
                } catch {
                    try loadGlossary(from: GameGlossary.bundledURL(), label: "内置词典")
                    glossaryStatus = "自定义词典无效，已使用内置词典。"
                }
            } else { try loadGlossary(from: GameGlossary.bundledURL(), label: "内置词典") }
        } catch {
            glossaryEnabled = false
            glossaryStatus = error.localizedDescription
        }
    }

    func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: "sourceLanguage")
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(backgroundOpacity, forKey: "backgroundOpacity")
        if let data = try? JSONEncoder().encode(subtitleStyle.normalized()) { defaults.set(data, forKey: "subtitleStyle") }
        defaults.set(overlayWidth, forKey: "overlayWidth")
        defaults.set(overlayHeight, forKey: "overlayHeight")
        defaults.set(overlayAutoHeight, forKey: "overlayAutoHeight")
        defaults.set(glossaryEnabled, forKey: "glossaryEnabled")
        defaults.set(glossaryProfileID, forKey: "glossaryProfileID")
        if let overlayOrigin {
            defaults.set(overlayOrigin.x, forKey: "overlayX")
            defaults.set(overlayOrigin.y, forKey: "overlayY")
        }
    }

    func applySubtitlePreset(_ preset: SubtitlePreset) {
        var style = SubtitleStyle()
        switch preset {
        case .dark:
            fontSize = 25
            backgroundOpacity = 0.82
        case .transparent:
            fontSize = 28
            backgroundOpacity = 0
            style.sourceFontSize = 20
            style.textShadow = 3
            style.showsBorder = false
        case .chinese:
            fontSize = 30
            backgroundOpacity = 0.72
            style.sourceFontSize = 16
            style.targetColor = "#FFE28A"
            style.targetWeight = .bold
            style.translationFirst = true
            style.textShadow = 1
        }
        subtitleStyle = style
        savePreferences()
    }

    private func customGlossaryURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "LiveLingo")
            .appendingPathComponent("game-glossary.json")
    }

    private func loadGlossary(from url: URL, label: String) throws {
        let loaded = try GameGlossary(data: Data(contentsOf: url))
        glossary = loaded
        glossaryProfiles = loaded.profiles
        if !loaded.profiles.contains(where: { $0.id == glossaryProfileID }) { glossaryProfileID = loaded.profiles[0].id }
        glossaryLabel = label
        glossaryStatus = "\(loaded.profiles.count) 个配置 · \(loaded.profiles.reduce(0) { $0 + $1.terms.count }) 条术语"
    }

    func importGlossary() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "导入游戏术语 JSON；有效后替换当前词典。格式见项目 examples/game-glossary.json。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 2_000_000 else { throw GlossaryError("词典不能超过 2 MB。") }
            let data = try Data(contentsOf: url)
            _ = try GameGlossary(data: data)
            let destination = try customGlossaryURL()
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            try loadGlossary(from: destination, label: "自定义词典")
            savePreferences()
        } catch { glossaryStatus = "导入失败：\(error.localizedDescription)" }
    }

    func resetGlossary() {
        guard !busy else { return }
        do {
            let bundled = try GameGlossary.bundledURL()
            let data = try Data(contentsOf: bundled)
            _ = try GameGlossary(data: data)
            let custom = try customGlossaryURL()
            if FileManager.default.fileExists(atPath: custom.path) { try FileManager.default.removeItem(at: custom) }
            try loadGlossary(from: bundled, label: "内置词典")
            savePreferences()
        } catch { glossaryStatus = "恢复失败：\(error.localizedDescription)" }
    }

    func tryGlossaryText() {
        guard !busy else { return }
        let prompt = NSAlert()
        prompt.messageText = "词典文字试译"
        prompt.informativeText = "输入\(language.title)原文，检查当前游戏词典的译名；不读取直播声音。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 410, height: 60))
        let profile = glossaryProfiles.first { $0.id == glossaryProfileID }
        let term = profile?.terms.first { $0.mode == "protect" } ?? profile?.terms.first
        field.stringValue = (language == .japanese ? term?.ja.first : term?.en.first) ?? ""
        prompt.accessoryView = field
        prompt.addButton(withTitle: "试译")
        prompt.addButton(withTitle: "取消")
        prompt.window.initialFirstResponder = field
        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        endDemo()
        savePreferences()
        errorMessage = nil
        generation = UUID()
        trialText = text
        modelsOnly = false
        isPreparing = true
        phase = "正在文字试译…"
        detail = "仅处理输入文字，不读取 Safari 声音。"
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        translationBacklog = TranslationBacklog()
        lastEnqueuedJob = nil
        translationStream = stream
        translationInput = continuation
        translationConfiguration = makeTranslationConfiguration()
    }

    func start() {
        guard !busy else { return }
        endDemo()
        savePreferences()
        screenPermission = CGPreflightScreenCaptureAccess()
        errorMessage = nil
        modelsOnly = false
        trialText = nil
        store = CaptionStore()
        captions = []
        historyCount = 0
        generation = UUID()
        isPreparing = true
        phase = "准备语言模型…"
        detail = "识别与翻译在本机运行；首次下载可能需要几分钟。"
        translationSeconds = nil
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        translationBacklog = TranslationBacklog()
        lastEnqueuedJob = nil
        translationStream = stream
        translationInput = continuation
        translationConfiguration = makeTranslationConfiguration()
    }

    func prepareModels() {
        guard !busy else { return }
        endDemo()
        savePreferences()
        errorMessage = nil
        generation = UUID()
        modelsOnly = true
        trialText = nil
        isPreparing = true
        phase = "准备语言模型…"
        detail = "仅下载和加载模型，不读取 Safari 声音。"
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        translationBacklog = TranslationBacklog()
        lastEnqueuedJob = nil
        translationStream = stream
        translationInput = continuation
        translationConfiguration = makeTranslationConfiguration()
    }

    private func makeTranslationConfiguration() -> TranslationSession.Configuration {
        let source = Locale.Language(identifier: language.code)
        let target = Locale.Language(identifier: "zh-Hans")
        // A new session with the same language pair must have a new task version.
        if var previous = lastTranslationConfiguration, previous.source == source, previous.target == target {
            previous.invalidate()
            lastTranslationConfiguration = previous
            return previous
        }
        let configuration: TranslationSession.Configuration
        if #available(macOS 26.4, *) {
            configuration = .init(source: source, target: target, preferredStrategy: .lowLatency)
        } else {
            configuration = .init(source: source, target: target)
        }
        lastTranslationConfiguration = configuration
        return configuration
    }

    /// Keep the TranslationSession inside its SwiftUI translationTask lifetime.
    func runTranslation(session: TranslationSession) async {
        let run = generation
        guard isPreparing, let jobs = translationStream else { return }
        let activeGlossary = glossaryEnabled ? glossary : nil
        let activeProfile = glossaryProfileID
        let activeLanguage = language
        do {
            phase = "准备中文翻译模型…"
            try await session.prepareTranslation()
            try Task.checkCancellation()
            guard run == generation else { return }
            if let text = trialText {
                let result = try await GlossaryTranslator.translate(text, language: activeLanguage,
                    glossary: activeGlossary, profileID: activeProfile, session: session)
                try Task.checkCancellation()
                guard run == generation else { return }
                store = CaptionStore()
                let caption = store.ingest(text: text, start: 0, end: 1, isFinal: true)!
                let job = TranslationJob(id: caption.id, revision: 0, text: text, generation: run)
                _ = store.applyTranslation(result.text, for: job, notes: result.notes, usedFallback: result.usedFallback)
                publishCaptions()
                trialText = nil
                translationInput?.finish()
                translationInput = nil
                translationStream = nil
                isPreparing = false
                isDemo = true
                isTextTrial = true
                phase = "词典文字试译完成"
                detail = "这是输入文字的真实本机译文，没有读取直播声音。"
                translationConfiguration = nil
                setOverlay(visible: true)
                return
            }
            speech.onStatus = { [weak self] text in
                guard let self, self.generation == run else { return }; self.phase = text
            }
            speech.onDownload = { [weak self] progress in
                guard let self, self.generation == run else { return }; self.downloadProgress = progress
            }
            speech.onResult = { [weak self] text, start, end, final in
                guard let self, self.generation == run else { return }
                self.receive(text: text, start: start, end: end, final: final)
            }
            speech.onError = { [weak self] error in
                guard let self, self.generation == run else { return }; self.fail(error)
            }
            let (format, input) = try await speech.prepare(language: language)
            try Task.checkCancellation()
            guard run == generation else { return }
            if modelsOnly {
                await speech.stop()
                translationInput?.finish()
                translationInput = nil
                translationStream = nil
                isPreparing = false
                modelsOnly = false
                phase = "\(language.title)模型已就绪"
                detail = "可以在 Safari 播放直播，然后开始字幕。"
                translationConfiguration = nil
                return
            }
            if !CGPreflightScreenCaptureAccess() {
                phase = "请选择\(captureSource.title)声音"
                detail = "在系统选择器中选择\(captureSource == .safari ? "Safari 应用" : "显示器")并确认。本应用仅接收音频。"
            }
            try await capture.start(source: captureSource, format: format, onBuffer: { [weak self] buffer in
                let result = input.yield(AnalyzerInput(buffer: buffer))
                if case .dropped = result {
                    Task { @MainActor in
                        guard let self, self.generation == run else { return }
                        self.fail(LiveError.message("识别处理速度落后于直播。请停止后重试，或关闭其他占用资源的应用。"))
                    }
                }
            }, onLevel: { [weak self] level in
                Task { @MainActor in
                    guard let self, self.generation == run else { return }
                    self.audioMeter.update(level)
                    if level > 0.15 { self.lastAudioTime = Date() }
                }
            }, onError: { [weak self] error in
                Task { @MainActor in
                    guard let self, self.generation == run else { return }; self.fail(error)
                }
            })
            guard run == generation else { await capture.stop(); return }
            isPreparing = false
            isRunning = true
            phase = "正在听\(captureSource.title)"
            detail = "等待语音 · \(language.title) → 简体中文"
            lastAudioTime = Date()
            setOverlay(visible: true)
            startMeterMonitor(run: run)
            for await _ in jobs {
              while run == generation, let job = translationBacklog.pop() {
                try Task.checkCancellation()
                guard run == generation, job.generation == run else { continue }
                // Skip outdated partial revisions before spending translation time on them.
                guard store.isApplicable(job) else { continue }
                let begun = Date()
                let response = try await GlossaryTranslator.translate(job.text, language: activeLanguage,
                    glossary: activeGlossary, profileID: activeProfile, session: session)
                guard run == generation else { return }
                if store.applyTranslation(response.text, for: job, notes: response.notes, usedFallback: response.usedFallback) {
                    publishCaptions()
                    translationSeconds = Date().timeIntervalSince(begun)
                    let nextDetail = "\(language.title)原文与中文译文同步显示"
                    if detail != nextDetail { detail = nextDetail }
                }
              }
            }
        } catch {
            if run == generation, !Task.isCancelled { fail(error) }
        }
    }

    private func receive(text: String, start: Double, end: Double, final: Bool) {
        guard let caption = store.ingest(text: text, start: start, end: end, isFinal: final) else { return }
        publishCaptions()
        if caption.translatedSource == caption.source { return }
        if final {
            if pendingPartial?.id == caption.id { debounceTask?.cancel(); debounceTask = nil; pendingPartial = nil }
            enqueue(caption)
        } else {
            pendingPartial = caption
            // Throttle rather than debounce: continuous speech must not starve translation.
            guard debounceTask == nil else { return }
            let run = generation
            let delay = max(0.02, 0.3 - Date().timeIntervalSince(lastPartialTranslationTime))
            debounceTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, self.generation == run else { return }
                if let pending = self.pendingPartial { self.enqueue(pending) }
                self.pendingPartial = nil
                self.lastPartialTranslationTime = Date()
                self.debounceTask = nil
            }
        }
    }

    private func enqueue(_ caption: Caption) {
        let job = TranslationJob(id: caption.id, revision: caption.revision, text: caption.source, generation: generation)
        if let last = lastEnqueuedJob, last.id == job.id, last.text == job.text, last.generation == job.generation { return }
        lastEnqueuedJob = job
        translationBacklog.enqueue(job)
        translationInput?.yield(())
    }

    private func publishCaptions() {
        let visible = store.visibleItems()
        if captions != visible { captions = visible }
        if historyCount != store.items.count { historyCount = store.items.count }
    }

    private func startMeterMonitor(run: UUID) {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.generation == run else { return }
                if Date().timeIntervalSince(self.lastAudioTime) > 10 {
                    self.detail = self.captureSource == .safari
                        ? "未检测到 Safari 声音。确认直播有声；仍无输入可停止后改选“全部系统声音”。"
                        : "未检测到声音。请检查直播播放和音量。"
                }
            }
        }
    }

    func stop() {
        guard !isStopping else { return }
        isStopping = true
        generation = UUID()
        translationInput?.finish()
        translationInput = nil
        translationStream = nil
        translationBacklog = TranslationBacklog()
        lastEnqueuedJob = nil
        translationConfiguration = nil
        debounceTask?.cancel(); debounceTask = nil
        pendingPartial = nil
        meterTask?.cancel(); meterTask = nil
        endDemo()
        trialText = nil
        Task {
            await capture.stop()
            await speech.stop()
            isPreparing = false
            isRunning = false
            isStopping = false
            modelsOnly = false
            audioMeter.update(0)
            downloadProgress = nil
            phase = errorMessage == nil ? "已停止" : "需要处理"
            if errorMessage == nil { detail = "字幕已保留，可以导出或重新开始。" }
        }
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        stop()
    }

    func setOverlay(visible: Bool) {
        overlayVisible = visible
        if visible { onShowOverlay?() } else { onHideOverlay?() }
    }
    func setLocked(_ locked: Bool) { overlayLocked = locked; onLockOverlay?(locked) }
    func toggleLock() { setLocked(!overlayLocked) }
    func refreshPermission() { screenPermission = CGPreflightScreenCaptureAccess() }
    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func preview() {
        guard !busy else { return }
        endDemo()
        isDemo = true
        phase = "字幕外观预览"
        detail = "以下是演示文字；没有读取音频。开始直播字幕后会替换。"
        let examples = language == .japanese ? [
            ("皆さん、こんにちは。今日のライブ配信へようこそ。", "大家好，欢迎来到今天的直播。"),
            ("字幕がなくても、音声からリアルタイムで翻訳します。", "即使没有字幕，也能从声音实时翻译。"),
            ("日本語の原文と中国語の訳を、同時に表示します。", "日语原文和中文翻译会同时显示。")
        ] : [
            ("Hello everyone, welcome to today's live stream.", "大家好，欢迎来到今天的直播。"),
            ("You can watch in Safari with bilingual subtitles.", "你可以在 Safari 中观看并显示双语字幕。")
        ]
        store = CaptionStore()
        captions = []
        demoTask = Task { [weak self] in
            var i = 0
            while !Task.isCancelled {
                guard let self else { return }
                let example = examples[i % examples.count]
                var demo = Caption(id: UUID(), start: Double(i * 5), end: Double(i * 5 + 4),
                                   source: example.0, translation: example.1, translatedSource: example.0, isFinal: true)
                demo.revision = 0
                self.captions = [demo]
                i += 1
                try? await Task.sleep(for: .seconds(5))
            }
        }
        setOverlay(visible: true)
    }

    private func endDemo() {
        demoTask?.cancel(); demoTask = nil
        if isDemo { captions = [] }
        isDemo = false
        isTextTrial = false
    }

    func exportSRT() {
        guard !isDemo, !store.items.isEmpty else { return }
        let save = NSSavePanel()
        save.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        save.nameFieldStringValue = "双语字幕-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-" )).srt"
        save.message = "导出当前保留的最近 \(store.items.count) 条双语字幕（最多 2000 条）。时间从本次捕获开始计时。"
        if save.runModal() == .OK, let url = save.url {
            do { try store.srt().write(to: url, atomically: true, encoding: .utf8) }
            catch { errorMessage = "导出失败：\(error.localizedDescription)" }
        }
    }
}
