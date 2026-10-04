import Foundation

enum SourceLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja-JP"
    case english = "en-US"
    var id: String { rawValue }
    var title: String { self == .japanese ? "日语" : "英语" }
    var code: String { self == .japanese ? "ja" : "en" }
}

enum CaptureSource: String, CaseIterable, Identifiable {
    case safari, system
    var id: String { rawValue }
    var title: String { self == .safari ? "Safari" : "全部系统声音" }
}

struct Caption: Identifiable, Codable, Equatable {
    let id: UUID
    var start: Double
    var end: Double
    var source: String
    var translation: String = ""
    var translatedSource: String = ""
    var isFinal: Bool
    var revision: Int = 0
}

struct TranslationJob: Sendable {
    let id: UUID
    let revision: Int
    let text: String
    let generation: UUID
}

/// SpeechTranscriber emits replacements over audio ranges, not an append-only transcript.
struct CaptionStore {
    private(set) var items: [Caption] = []
    let limit: Int
    init(limit: Int = 2000) { self.limit = max(1, limit) }

    @discardableResult
    mutating func ingest(text: String, start: Double, end: Double, isFinal: Bool) -> Caption? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
        let previous = items.first { abs($0.start - start) < 0.015 }
        // Remove superseded volatile ranges. Keep adjacent final utterances intact.
        items.removeAll {
            abs($0.start - start) < 0.015 ||
            (!$0.isFinal && $0.start < end - 0.001 && $0.end > start + 0.001)
        }
        var next = Caption(id: previous?.id ?? UUID(), start: start, end: end,
                           source: text, isFinal: isFinal)
        if let previous {
            next.revision = previous.revision + (previous.source == text ? 0 : 1)
            // Preserve a translation of a stable prefix as new spoken words arrive.
            if !previous.translatedSource.isEmpty, text.hasPrefix(previous.translatedSource) {
                next.translation = previous.translation
                next.translatedSource = previous.translatedSource
            }
        }
        items.append(next)
        items.sort { $0.start < $1.start }
        if items.count > limit { items.removeFirst(items.count - limit) }
        return next
    }

    mutating func applyTranslation(_ translated: String, for job: TranslationJob) -> Bool {
        guard isApplicable(job), !translated.isEmpty,
              let i = items.firstIndex(where: { $0.id == job.id }) else { return false }
        items[i].translation = translated
        items[i].translatedSource = job.text
        return true
    }

    func isApplicable(_ job: TranslationJob) -> Bool {
        guard let caption = items.first(where: { $0.id == job.id }) else { return false }
        return caption.source.hasPrefix(job.text) && job.text.count >= caption.translatedSource.count
    }

    static func timestamp(_ seconds: Double) -> String {
        let ms = max(0, Int((seconds * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000,
                      (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    func srt() -> String {
        items.enumerated().map { i, c in
            let translated = c.translation.isEmpty ? "[中文翻译尚未完成]"
                : c.translation + (c.translatedSource == c.source ? "" : "\n[中文翻译尚未完成]")
            return "\(i + 1)\n\(Self.timestamp(c.start)) --> \(Self.timestamp(max(c.end, c.start + 0.1)))\n\(c.source)\n\(translated)\n"
        }.joined(separator: "\n")
    }
}

enum CaptionDisplay {
    static func tail(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        var suffix = String(text.suffix(max(1, limit)))
        // Avoid showing a cut English word. CJK characters can wrap independently.
        if suffix.first?.isASCII == true, let space = suffix.firstIndex(of: " "),
           suffix.distance(from: suffix.startIndex, to: space) < 18 {
            suffix = String(suffix[suffix.index(after: space)...])
        }
        return "…" + suffix
    }

    static func source(_ caption: Caption, width: Double, fontSize: Double) -> String {
        tail(caption.source, limit: max(4, Int((width - 48) / (fontSize * 0.74) * 2.5)))
    }
    static func target(_ caption: Caption, width: Double, fontSize: Double) -> String {
        tail(caption.translation, limit: max(4, Int((width - 48) / fontSize * 2.5)))
    }
}
