import AVFoundation
import CoreGraphics
import Speech
import Translation

enum Diagnostics {
    @MainActor static func run(arguments: [String]) async throws {
        if arguments.contains("--prepare-speech") {
            let language = arguments.contains("--english") ? SourceLanguage.english : .japanese
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.rawValue)) else {
                throw LiveError.message("语言不受支持。")
            }
            let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            _ = try await AssetInventory.reserve(locale: locale)
            do {
                if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    print("Downloading \(language.rawValue) speech model…")
                    try await installation.downloadAndInstall()
                }
                print("Speech model ready: \(language.rawValue)")
                await AssetInventory.release(reservedLocale: locale)
            } catch { await AssetInventory.release(reservedLocale: locale); throw error }
            return
        }
        if let i = arguments.firstIndex(of: "--transcribe-file"), arguments.count > i + 1 {
            let language = arguments.contains("--english") ? SourceLanguage.english : .japanese
            try await transcribe(path: arguments[i + 1], language: language)
            return
        }
        if let i = arguments.firstIndex(of: "--translate-text"), arguments.count > i + 1 {
            let source = Locale.Language(identifier: arguments.contains("--english") ? "en" : "ja")
            let target = Locale.Language(identifier: "zh-Hans")
            guard await LanguageAvailability().status(from: source, to: target) == .installed else {
                throw LiveError.message("翻译语言模型未安装；请通过应用的开始字幕完成系统模型下载。")
            }
            let session: TranslationSession
            if #available(macOS 26.4, *) {
                session = TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
            } else { session = TranslationSession(installedSource: source, target: target) }
            let profile = arguments.firstIndex(of: "--game").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            var glossary: GameGlossary?
            if let profile {
                let url: URL
                if let j = arguments.firstIndex(of: "--glossary-file"), arguments.count > j + 1 { url = URL(fileURLWithPath: arguments[j + 1]) }
                else { url = try GameGlossary.bundledURL() }
                glossary = try GameGlossary(data: Data(contentsOf: url))
                guard glossary!.profiles.contains(where: { $0.id == profile }) else { throw GlossaryError("词典中没有该游戏分类。") }
            }
            let result = try await GlossaryTranslator.translate(arguments[i + 1],
                language: arguments.contains("--english") ? .english : .japanese,
                glossary: glossary, profileID: profile ?? "", session: session)
            if arguments.contains("--glossary-report") {
                let report: [String: Any] = ["source": arguments[i + 1], "text": result.text,
                    "usedFallback": result.usedFallback, "terms": result.notes.map { ["source": $0.source, "target": $0.target, "applied": $0.applied] as [String: Any] }]
                print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
            } else { print(result.text) }
            return
        }
        var result: [String: Any] = [
            "appVersion": "0.3.0",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "onDeviceSpeechAvailable": SpeechTranscriber.isAvailable,
            "screenAudioPermission": CGPreflightScreenCaptureAccess(),
            "captureMicrophone": false,
            "defaultLanguage": "ja-JP"
        ]
        for language in SourceLanguage.allCases {
            if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.rawValue)) {
                let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
                result["speech_\(language.code)"] = String(describing: await AssetInventory.status(forModules: [module]))
                result["speechLocale_\(language.code)"] = locale.identifier
            } else { result["speech_\(language.code)"] = "unsupported" }
            result["translation_\(language.code)_zh"] = String(describing: await LanguageAvailability().status(
                from: Locale.Language(identifier: language.code), to: Locale.Language(identifier: "zh-Hans")))
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    @MainActor private static func transcribe(path: String, language: SourceLanguage) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.rawValue)) else {
            throw LiveError.message("语言不受支持。")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        _ = try await AssetInventory.reserve(locale: locale)
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let results = Task {
            for try await result in transcriber.results {
                if result.isFinal { print(String(result.text.characters)) }
            }
        }
        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installation.downloadAndInstall()
            }
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            try await results.value
            await AssetInventory.release(reservedLocale: locale)
        } catch {
            results.cancel(); await analyzer.cancelAndFinishNow()
            await AssetInventory.release(reservedLocale: locale)
            throw error
        }
    }
}
