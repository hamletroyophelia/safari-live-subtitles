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
        print("PASS: correction, stable-prefix streaming, stale-response rejection, finalization, bounded history, SRT, display tail")
    }
}
