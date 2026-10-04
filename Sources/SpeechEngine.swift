import AVFoundation
import Speech

@MainActor
final class SpeechEngine {
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var reservedLocale: Locale?
    private var preparationTask: Task<(AVAudioFormat, AsyncStream<AnalyzerInput>.Continuation), Error>?
    var onResult: ((String, Double, Double, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    var onStatus: ((String) -> Void)?
    var onDownload: ((Double?) -> Void)?

    func prepare(language: SourceLanguage) async throws -> (AVAudioFormat, AsyncStream<AnalyzerInput>.Continuation) {
        let task = Task { @MainActor in try await self.prepareSession(language: language) }
        preparationTask = task
        return try await withTaskCancellationHandler {
            let result = try await task.value
            preparationTask = nil
            return result
        } onCancel: { task.cancel() }
    }

    private func prepareSession(language: SourceLanguage) async throws -> (AVAudioFormat, AsyncStream<AnalyzerInput>.Continuation) {
        guard SpeechTranscriber.isAvailable else { throw LiveError.message("这台 Mac 暂不支持本地流式语音识别。") }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.rawValue)) else {
            throw LiveError.message("系统尚不支持\(language.title)识别。")
        }
        try Task.checkCancellation()
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                           reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        _ = try await AssetInventory.reserve(locale: locale)
        reservedLocale = locale
        try Task.checkCancellation()
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onStatus?("正在下载\(language.title)识别模型…")
            let progress = installation.progress
            let progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.onDownload?(progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { progressTask.cancel(); onDownload?(nil) }
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw LiveError.message("无法取得语音识别音频格式。")
        }
        onStatus?("正在准备本地识别…")
        try await analyzer.prepareToAnalyze(in: format)
        try Task.checkCancellation()
        let (input, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(256))
        self.continuation = continuation
        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { break }
                    self?.onResult?(String(result.text.characters), result.range.start.seconds,
                                    result.range.end.seconds, result.isFinal)
                }
            } catch {
                if !Task.isCancelled { self?.onError?(error) }
            }
        }
        try await analyzer.start(inputSequence: input)
        return (format, continuation)
    }

    func stop() async {
        let pending = preparationTask
        pending?.cancel()
        if let pending { _ = await pending.result }
        preparationTask = nil
        continuation?.finish()
        continuation = nil
        resultTask?.cancel()
        resultTask = nil
        if let analyzer { await analyzer.cancelAndFinishNow() }
        analyzer = nil
        if let reservedLocale { await AssetInventory.release(reservedLocale: reservedLocale) }
        reservedLocale = nil
        onDownload?(nil)
    }
}
