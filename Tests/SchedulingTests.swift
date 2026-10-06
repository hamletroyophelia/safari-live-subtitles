import Foundation

@main struct SchedulingTests {
    static func main() {
        var store = CaptionStore()
        let first = store.ingest(text: "古い", start: 0, end: 1, isFinal: false)!
        let waiting = TranslationJob(id: first.id, revision: 0, text: first.source, generation: UUID())
        store.ingest(text: "新しい文", start: 0, end: 2, isFinal: true)
        let refreshed = store.latestJob(for: waiting)!
        precondition(refreshed.text == "新しい文" && refreshed.revision == 1)
        precondition(store.applyTranslation("新句子", for: refreshed))
        precondition(store.latestJob(for: waiting) == nil, "an already completed revision must not run twice")
        store.ingest(text: "次の文", start: 3, end: 4, isFinal: true)
        precondition(store.latestJob(for: waiting) == nil, "other sentences must not resurrect a completed job")

        let response = GlossaryTranslation(text: "译文", notes: [], usedFallback: false)
        var memo = TranslationMemo(limit: 2)
        memo.insert(response, for: "一"); memo.insert(response, for: "二")
        memo.insert(response, for: "三")
        precondition(memo.count == 2 && memo.result(for: "一") == nil && memo.result(for: "三")?.text == "译文")
        memo.insert(GlossaryTranslation(text: "回退", notes: [], usedFallback: true), for: "四")
        precondition(memo.result(for: "四") == nil, "a failed term protection must not become a cached result")
        var small = TranslationMemo(byteLimit: 12)
        small.insert(response, for: "一"); small.insert(response, for: "二")
        precondition(small.count == 1 && small.result(for: "一") == nil)
        var separateSession = TranslationMemo()
        precondition(separateSession.result(for: "三") == nil, "languages and changed dictionaries start a fresh memo")
        separateSession.insert(response, for: String(repeating: "x", count: 257))
        precondition(separateSession.count == 0)

        var schedule = PartialTranslationSchedule()
        precondition(schedule.delay(now: 10) == 0.015)
        schedule.enqueued(now: 10)
        precondition(abs(schedule.delay(now: 10.05) - 0.10) < 0.001)
        for _ in 0..<30 { schedule.completed(seconds: 0.02) }
        precondition(schedule.interval == 0.12)
        for _ in 0..<30 { schedule.completed(seconds: 1.0) }
        precondition(schedule.interval == 0.45 && schedule.delay(now: 12) == 0.015)
        schedule.completed(seconds: .nan)
        precondition(schedule.interval.isFinite)
        precondition(CaptionDisplay.tail("abc hello world", limit: 11) == "…hello world", "a word starting at the tail boundary must remain")
        precondition(CaptionDisplay.tail("abcdefghi world", limit: 11) == "…world", "a cut word is skipped")
        precondition(CaptionDisplay.tail("😀日本語字幕", limit: 4) == "…本語字幕")
        precondition(TranslationText.clean(" 使用 冷却时间 ， 然后 重生。 ") == "使用冷却时间，然后重生。")
        precondition(TranslationText.clean("hololive Super Chat 与 中文\n第二行") == "hololive Super Chat 与中文\n第二行")
        print("PASS: fresh revisions, duplicate suppression, bounded session memo, fallback isolation, adaptive schedule, Unicode/word display")
    }
}
