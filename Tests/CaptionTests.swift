import Foundation

@main struct CaptionTests {
    static func main() {
        var store = CaptionStore(limit: 3)
        let first = store.ingest(text: "日本語です", start: 0, end: 1, isFinal: false)!
        let job = TranslationJob(id: first.id, revision: first.revision, text: first.source, generation: UUID())
        let corrected = store.ingest(text: "日本語の字幕", start: 0, end: 2, isFinal: false)!
        precondition(corrected.id == first.id && corrected.revision == 1)
        precondition(!store.applyTranslation("旧译文", for: job), "stale translations must be rejected")
        let newJob = TranslationJob(id: corrected.id, revision: corrected.revision, text: corrected.source, generation: UUID())
        precondition(store.applyTranslation("日语字幕", for: newJob))
        store.ingest(text: "日本語の字幕", start: 0, end: 2, isFinal: true)
        precondition(store.items[0].translation == "日语字幕", "finalization must keep a matching translation")
        store.ingest(text: "次の文", start: 2, end: 3, isFinal: true)
        precondition(store.items.count == 2, "adjacent ranges must remain separate")
        store.ingest(text: "追加", start: 3, end: 4, isFinal: false)
        store.ingest(text: "修正", start: 3.5, end: 4.5, isFinal: true)
        precondition(store.items.count == 3 && !store.items.contains(where: { $0.source == "追加" }))
        store.ingest(text: "最後", start: 5, end: 6, isFinal: true)
        precondition(store.items.count == 3 && store.items.first!.start == 2, "history must be bounded")
        precondition(store.ingest(text: "", start: 6, end: 7, isFinal: true) == nil)
        precondition(store.ingest(text: "invalid", start: .nan, end: 7, isFinal: true) == nil)
        precondition(CaptionStore.timestamp(3661.234) == "01:01:01,234")
        precondition(store.srt().contains("[中文翻译尚未完成]"))
        precondition(store.srt().contains("00:00:02,000 --> 00:00:03,000"))
        var streaming = CaptionStore()
        let short = streaming.ingest(text: "今日は", start: 0, end: 1, isFinal: false)!
        let shortJob = TranslationJob(id: short.id, revision: short.revision, text: short.source, generation: UUID())
        streaming.ingest(text: "今日は日本語", start: 0, end: 2, isFinal: false)
        precondition(streaming.applyTranslation("今天", for: shortJob), "a stable prefix must remain usable")
        streaming.ingest(text: "今日は日本語を翻訳", start: 0, end: 3, isFinal: false)
        precondition(streaming.items[0].translation == "今天", "new words must not flash away existing translation")
        precondition(streaming.srt().contains("今天\n[中文翻译尚未完成]"), "exports must identify incomplete prefix translations")
        let longJob = TranslationJob(id: short.id, revision: 2, text: "今日は日本語を翻訳", generation: UUID())
        precondition(streaming.applyTranslation("今天翻译日语", for: longJob))
        precondition(!streaming.applyTranslation("今天", for: shortJob), "older prefix cannot overwrite newer translation")
        streaming.ingest(text: "明日は日本語を翻訳", start: 0, end: 3, isFinal: false)
        precondition(streaming.items[0].translation.isEmpty, "a corrected prefix must clear its translation")
        precondition(!streaming.applyTranslation("今天翻译日语", for: longJob))
        precondition(CaptionDisplay.tail("短い文", limit: 10) == "短い文")
        precondition(CaptionDisplay.tail("日本語の長い字幕", limit: 4) == "…長い字幕")
        var backlog = TranslationBacklog(limit: 2)
        let other = TranslationJob(id: UUID(), revision: 0, text: "next", generation: shortJob.generation)
        backlog.enqueue(shortJob)
        backlog.enqueue(other)
        backlog.enqueue(longJob)
        // Use one generation when coalescing; a different session must not replace the old job.
        precondition(backlog.jobs.count == 2)
        var sameRun = TranslationBacklog()
        sameRun.enqueue(shortJob)
        sameRun.enqueue(other)
        let latest = TranslationJob(id: shortJob.id, revision: 2, text: longJob.text, generation: shortJob.generation)
        sameRun.enqueue(latest)
        precondition(sameRun.pop()?.text == latest.text && sameRun.pop()?.id == other.id && sameRun.pop() == nil)
        for i in 0..<10 { backlog.enqueue(TranslationJob(id: UUID(), revision: i, text: String(i), generation: UUID())) }
        precondition(backlog.jobs.count == 2 && backlog.pop()?.text == "8" && backlog.pop()?.text == "9")

        var history = CaptionStore()
        for i in 0..<2000 { history.ingest(text: String(i), start: Double(i * 2), end: Double(i * 2 + 1), isFinal: true) }
        let snapshot = history.visibleItems()
        history.ingest(text: "replacement", start: 3998, end: 3999, isFinal: true)
        precondition(history.items.count == 2000 && history.visibleItems().count == 80)
        precondition(snapshot.last?.source == "1999" && history.items.last?.source == "replacement")
        precondition(history.srt().contains("2000\n"), "visible snapshots must not truncate exported history")

        // Differential range audit against the original removal rules, including near-start boundaries.
        var ranges: [(Double, Double, String, Bool)] = []
        var audit = CaptionStore(limit: 17)
        var seed: UInt64 = 12345
        for i in 0..<5000 {
            seed = seed &* 6364136223846793005 &+ 1
            let start = Double((seed >> 32) % 150) / 100
            let end = start + Double((seed >> 16) % 100) / 100
            let final = seed % 3 == 0
            let text = String(i)
            ranges.removeAll { abs($0.0 - start) < 0.015 || (!$0.3 && $0.0 < end - 0.001 && $0.1 > start + 0.001) }
            ranges.append((start, end, text, final))
            ranges.sort { $0.0 < $1.0 }
            if ranges.count > 17 { ranges.removeFirst(ranges.count - 17) }
            audit.ingest(text: text, start: start, end: end, isFinal: final)
            precondition(audit.items.count == ranges.count)
            for (caption, expected) in zip(audit.items, ranges) {
                precondition(caption.start == expected.0 && caption.end == expected.1 && caption.source == expected.2 && caption.isFinal == expected.3)
            }
        }
        print("PASS: streaming, stale responses, bounded history, full SRT, immutable visible snapshots, coalesced translation backlog, 5000 range revisions")
    }
}
