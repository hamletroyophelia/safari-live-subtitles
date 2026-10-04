import AppKit
import Combine
import CoreGraphics
import Speech
import Translation
import UniformTypeIdentifiers

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
    @Published var errorMessage: String?
    @Published var downloadProgress: Double?
    @Published var audioLevel: Double = 0
    @Published var translationSeconds: Double?
    @Published var captions: [Caption] = []
    @Published var overlayVisible = false
    @Published var overlayLocked = false
    @Published var fontSize = 25.0
    @Published var backgroundOpacity = 0.82
    @Published var overlayWidth = 760.0
    @Published var overlayHeight = 130.0
    @Published var overlayAutoHeight = true
    var overlayOrigin: NSPoint?
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published var screenPermission = CGPreflightScreenCaptureAccess()

    var onShowOverlay: (() -> Void)?
    var onHideOverlay: (() -> Void)?
    var onLockOverlay: ((Bool) -> Void)?
    var onResetOverlay: (() -> Void)?
    private let speech = SpeechEngine()
    private let capture = AudioCapture()
    private var store = CaptionStore()
    private var generation = UUID()
    private var translationInput: AsyncStream<TranslationJob>.Continuation?
    private var translationStream: AsyncStream<TranslationJob>?
    private var debounceTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var lastAudioTime = Date.distantPast
    private var lastPartialTranslationTime = Date.distantPast
    private var pendingPartial: Caption?
    private var modelsOnly = false
    private var lastTranslationConfiguration: TranslationSession.Configuration?

    var busy: Bool { isPreparing || isRunning || isStopping }
    var current: Caption? { captions.last }

    init() {
        let saved = UserDefaults.standard
        language = SourceLanguage(rawValue: saved.string(forKey: "sourceLanguage") ?? "") ?? .japanese
        fontSize = saved.object(forKey: "fontSize") == nil ? 25 : saved.double(forKey: "fontSize")
        backgroundOpacity = saved.object(forKey: "backgroundOpacity") == nil ? 0.82 : saved.double(forKey: "backgroundOpacity")
        fontSize = min(42, max(16, fontSize))
        backgroundOpacity = min(1, max(0.25, backgroundOpacity))
        overlayWidth = min(1600, max(440, saved.object(forKey: "overlayWidth") == nil ? 760 : saved.double(forKey: "overlayWidth")))
        overlayHeight = min(900, max(105, saved.object(forKey: "overlayHeight") == nil ? 130 : saved.double(forKey: "overlayHeight")))
        overlayAutoHeight = saved.object(forKey: "overlayAutoHeight") == nil ? true : saved.bool(forKey: "overlayAutoHeight")
        if saved.object(forKey: "overlayX") != nil, saved.object(forKey: "overlayY") != nil {
            overlayOrigin = NSPoint(x: saved.double(forKey: "overlayX"), y: saved.double(forKey: "overlayY"))
        }
    }

    func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: "sourceLanguage")
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(backgroundOpacity, forKey: "backgroundOpacity")
        defaults.set(overlayWidth, forKey: "overlayWidth")
        defaults.set(overlayHeight, forKey: "overlayHeight")
        defaults.set(overlayAutoHeight, forKey: "overlayAutoHeight")
        if let overlayOrigin {
            defaults.set(overlayOrigin.x, forKey: "overlayX")
            defaults.set(overlayOrigin.y, forKey: "overlayY")
        }
    }

    func start() {
        guard !busy else { return }
        endDemo()
        savePreferences()
        screenPermission = CGPreflightScreenCaptureAccess()
        errorMessage = nil
        modelsOnly = false
        store = CaptionStore()
        captions = []
        generation = UUID()
        isPreparing = true
        phase = "准备语言模型…"
        detail = "识别与翻译在本机运行；首次下载可能需要几分钟。"
        translationSeconds = nil
        let (stream, continuation) = AsyncStream<TranslationJob>.makeStream(bufferingPolicy: .bufferingNewest(4))
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
        isPreparing = true
        phase = "准备语言模型…"
        detail = "仅下载和加载模型，不读取 Safari 声音。"
        let (stream, continuation) = AsyncStream<TranslationJob>.makeStream(bufferingPolicy: .bufferingNewest(4))
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
        do {
            phase = "准备中文翻译模型…"
            try await session.prepareTranslation()
            try Task.checkCancellation()
            guard run == generation else { return }
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
                    self.audioLevel = level
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
            for await job in jobs {
                try Task.checkCancellation()
                guard run == generation, job.generation == run else { continue }
                // Skip outdated partial revisions before spending translation time on them.
                guard store.isApplicable(job) else { continue }
                let begun = Date()
                let response = try await session.translate(job.text)
                guard run == generation else { return }
                if store.applyTranslation(response.targetText, for: job) {
                    captions = store.items
                    translationSeconds = Date().timeIntervalSince(begun)
                    detail = "\(language.title)原文与中文译文同步显示"
                }
            }
        } catch {
            if run == generation, !Task.isCancelled { fail(error) }
        }
    }

    private func receive(text: String, start: Double, end: Double, final: Bool) {
        guard let caption = store.ingest(text: text, start: start, end: end, isFinal: final) else { return }
        captions = store.items
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
        translationInput?.yield(TranslationJob(id: caption.id, revision: caption.revision,
                                               text: caption.source, generation: generation))
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
        translationConfiguration = nil
        debounceTask?.cancel(); debounceTask = nil
        pendingPartial = nil
        meterTask?.cancel(); meterTask = nil
        endDemo()
        Task {
            await capture.stop()
            await speech.stop()
            isPreparing = false
            isRunning = false
            isStopping = false
            modelsOnly = false
            audioLevel = 0
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
