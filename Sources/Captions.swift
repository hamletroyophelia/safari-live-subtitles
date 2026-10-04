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
    var termNotes: [TermNote] = []
    var glossaryFallback = false
}

struct TranslationJob: Sendable {
    let id: UUID
    let revision: Int
    let text: String
    let generation: UUID
}

/// Coalesce queued revisions of the same utterance without displacing other utterances.
struct TranslationBacklog {
    private(set) var jobs: [TranslationJob] = []
    let limit: Int
    init(limit: Int = 4) { self.limit = max(1, limit) }
    mutating func enqueue(_ job: TranslationJob) {
        if let i = jobs.firstIndex(where: { $0.id == job.id && $0.generation == job.generation }) {
            jobs[i] = job
        } else {
            jobs.append(job)
            if jobs.count > limit { jobs.removeFirst(jobs.count - limit) }
        }
    }
    mutating func pop() -> TranslationJob? { jobs.isEmpty ? nil : jobs.removeFirst() }
}

/// SpeechTranscriber emits replacements over audio ranges, not an append-only transcript.
struct CaptionStore {
    private(set) var items: [Caption] = []
    private var volatileCount = 0
    let limit: Int
    init(limit: Int = 2000) { self.limit = max(1, limit) }

    @discardableResult
    mutating func ingest(text: String, start: Double, end: Double, isFinal: Bool) -> Caption? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
        // Almost all streaming results replace the last utterance. Mutate it in place.
        if let last = items.last, abs(last.start - start) < 0.015,
           (items.count < 2 || items[items.count - 2].start <= start - 0.015),
           volatileCount == (last.isFinal ? 0 : 1) {
            let next = revised(last, text: text, start: start, end: end, isFinal: isFinal)
            items[items.count - 1] = next
            volatileCount = isFinal ? 0 : 1
            return next
        }
        if volatileCount == 0, let last = items.last, start >= last.end, start - last.start >= 0.015 {
            let next = revised(nil, text: text, start: start, end: end, isFinal: isFinal)
            items.append(next)
            volatileCount = isFinal ? 0 : 1
            trim()
            return next
        }
        let candidate = insertionIndex(start - 0.015)
        let previous = items[candidate...].prefix { $0.start < start + 0.015 }.first { abs($0.start - start) < 0.015 }
        // Remove superseded volatile ranges. Keep adjacent final utterances intact.
        var removedVolatile = 0
        items.removeAll {
            let remove = abs($0.start - start) < 0.015 ||
            (!$0.isFinal && $0.start < end - 0.001 && $0.end > start + 0.001)
            if remove && !$0.isFinal { removedVolatile += 1 }
            return remove
        }
        volatileCount -= removedVolatile
        let next = revised(previous, text: text, start: start, end: end, isFinal: isFinal)
        items.insert(next, at: insertionIndex(start))
        if !isFinal { volatileCount += 1 }
        trim()
        return next
    }

    private func revised(_ previous: Caption?, text: String, start: Double, end: Double, isFinal: Bool) -> Caption {
        var next = Caption(id: previous?.id ?? UUID(), start: start, end: end,
                           source: text, isFinal: isFinal)
        if let previous {
            next.revision = previous.revision + (previous.source == text ? 0 : 1)
            // Preserve a translation of a stable prefix as new spoken words arrive.
            if !previous.translatedSource.isEmpty, text.hasPrefix(previous.translatedSource) {
                next.translation = previous.translation
                next.translatedSource = previous.translatedSource
                next.termNotes = previous.termNotes
                next.glossaryFallback = previous.glossaryFallback
            }
        }
        return next
    }

    private func insertionIndex(_ start: Double) -> Int {
        var low = 0, high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].start < start { low = middle + 1 } else { high = middle }
        }
        return low
    }

    private mutating func trim() {
        guard items.count > limit else { return }
        let overflow = items.count - limit
        volatileCount -= items.prefix(overflow).reduce(0) { $0 + ($1.isFinal ? 0 : 1) }
        items.removeFirst(overflow)
    }

    func visibleItems(limit: Int = 80) -> [Caption] { Array(items.suffix(max(1, limit))) }

    private func index(for job: TranslationJob) -> Int? {
        items.indices.reversed().first { items[$0].id == job.id }
    }

    mutating func applyTranslation(_ translated: String, for job: TranslationJob, notes: [TermNote] = [], usedFallback: Bool = false) -> Bool {
        guard !translated.isEmpty, let i = index(for: job),
              items[i].source.hasPrefix(job.text), job.text.count >= items[i].translatedSource.count else { return false }
        items[i].translation = translated
        items[i].translatedSource = job.text
        items[i].termNotes = notes
        items[i].glossaryFallback = usedFallback
        return true
    }

    func isApplicable(_ job: TranslationJob) -> Bool {
        guard let i = index(for: job) else { return false }
        let caption = items[i]
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
    static func terms(_ caption: Caption) -> String {
        caption.termNotes.map { "\($0.applied ? "词典" : "对照")：\($0.source)→\($0.target)" }.joined(separator: " · ")
    }
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
        tail(caption.source, limit: max(4, Int((width - 48) / fontSize * 2.5)))
    }
    static func target(_ caption: Caption, width: Double, fontSize: Double) -> String {
        tail(caption.translation, limit: max(4, Int((width - 48) / fontSize * 2.5)))
    }
}
