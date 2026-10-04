import Foundation
import Translation

@main struct GlossaryTests {
    @MainActor static func main() async throws {
        let glossary = try GameGlossary(data: Data(contentsOf: URL(fileURLWithPath: "Resources/game-glossary.json")))
        precondition(glossary.profiles.count == 12)
        let combined = glossary.plan(source: "クリーパー、戦灰、忍殺、ヘッドショット、対空", language: .japanese, profileID: "all_games")
        precondition(combined.tokens.count == 5, "one combined profile must cover all game genres")
        let conflict = glossary.plan(source: "中段", language: .japanese, profileID: "all_games")
        precondition(conflict.tokens.isEmpty && conflict.matches[0].term.target.contains("中段攻击") && conflict.matches[0].term.target.contains("中段架势"), "cross-game conflicts must be hints")
        let japanese = glossary.plan(source: "😀クリーパーとクリーパー。ネザーでレッドストーンを探す。", language: .japanese, profileID: "minecraft")
        precondition(japanese.tokens.count == 4, "Unicode offsets and repeated terms must match")
        if #available(macOS 26.4, *) {
            let input = japanese.attributedInput()
            precondition(!String(input.characters).contains("クリーパー"))
            let protected = input.runs.filter { $0.skipsTranslation == true }
            precondition(protected.count == 4, "each token must carry the native skip attribute")
        }
        let translated = japanese.tokens.map(\.token).joined(separator: "、")
        precondition(japanese.restore(translated) == "苦力怕、苦力怕、下界、红石")
        precondition(japanese.restore(japanese.tokens[0].token + translated) == nil, "duplicated tokens must fail")
        precondition(japanese.restore("没有保留术语") == nil, "lost tokens must fail")
        precondition(japanese.restore(translated + " LLTERM999X") == nil, "unknown tokens must fail")
        let english = glossary.plan(source: "CREEPER, creepers, Nether. Netherland, redstoneish, under_Creeper", language: .english, profileID: "minecraft")
        precondition(english.matches.count == 3, "English matching requires case folding and Unicode word boundaries")
        let unrelated = glossary.plan(source: "クリーパー", language: .japanese, profileID: "elden_ring")
        precondition(unrelated.matches.isEmpty, "profiles must not mix Minecraft terms into Souls games")
        let inherited = glossary.plan(source: "戦灰、ローリング、ネタバレ", language: .japanese, profileID: "elden_ring")
        precondition(inherited.matches.count == 3, "game, genre and common terms must be inherited")
        let hint = glossary.plan(source: "my build", language: .english, profileID: "souls_common")
        precondition(hint.matches.count == 1 && hint.tokens.isEmpty, "ambiguous build must be a hint")
        let collision = glossary.plan(source: "LLTERM0X クリーパー", language: .japanese, profileID: "minecraft")
        precondition(collision.tokens[0].token != "LLTERM0X", "markers must not collide with source content")

        let custom = #"{"schemaVersion":2,"profiles":[{"id":"parent","terms":[{"ja":["クリーパー"],"en":["Creeper"],"zh-Hans":"原译名","mode":"protect"}]},{"id":"child","inherits":["parent"],"terms":[{"ja":["クリーパー","クリーパートラップ"],"en":["Creeper"],"zh-Hans":"自定义译名","mode":"protect"}]}]}"#
        let loaded = try GameGlossary(data: Data(custom.utf8))
        let longest = loaded.plan(source: "クリーパートラップ", language: .japanese, profileID: "child")
        precondition(longest.matches.count == 1 && longest.matches[0].source == "クリーパートラップ")
        precondition(longest.matches[0].term.target == "自定义译名", "specific profile must override its parent")
        let legacy = #"{"schemaVersion":1,"profiles":[{"id":"legacy","terms":[{"ja":["語"],"en":[],"zh-Hans":"词"}]}]}"#
        let legacyGlossary = try GameGlossary(data: Data(legacy.utf8))
        precondition(legacyGlossary.plan(source: "語", language: .japanese, profileID: "legacy").tokens.isEmpty)
        for invalid in [#"{"schemaVersion":2,"profiles":[{"id":"a","inherits":["a"],"terms":[]}]}"#,
                        #"{"schemaVersion":2,"profiles":[{"id":"a","inherits":["missing"],"terms":[]}]}"#,
                        #"{"schemaVersion":2,"profiles":[{"id":"a","terms":[]},{"id":"a","terms":[]}]}"#,
                        #"{"schemaVersion":2,"profiles":[{"id":"a","terms":[{"ja":["x"],"en":[],"zh-Hans":"","mode":"protect"}]}]}"#] {
            do { _ = try GameGlossary(data: Data(invalid.utf8)); preconditionFailure("invalid dictionaries must be rejected") }
            catch is GlossaryError { }
        }

        var plainCalls = 0
        let result = try await GlossaryTranslator.execute(japanese.source, plan: japanese, plain: { source in
            plainCalls += 1; precondition(source == japanese.source); return "普通译文"
        }, protected: { _ in translated })
        precondition(plainCalls == 0 && result.notes.allSatisfy(\.applied) && !result.usedFallback)
        let fallback = try await GlossaryTranslator.execute(japanese.source, plan: japanese, plain: { source in
            plainCalls += 1; precondition(source == japanese.source); return "普通译文"
        }, protected: { _ in "坏的 LLTERM0X" })
        precondition(plainCalls == 1 && fallback.text == "普通译文" && fallback.usedFallback && fallback.notes.allSatisfy { !$0.applied })
        do {
            _ = try await GlossaryTranslator.execute(japanese.source, plan: japanese, plain: { _ in
                preconditionFailure("cancellation must never trigger a second request")
            }, protected: { _ in throw CancellationError() })
            preconditionFailure("cancellation must propagate")
        } catch is CancellationError { }
        var store = CaptionStore()
        let caption = store.ingest(text: "クリーパー", start: 0, end: 1, isFinal: false)!
        let job = TranslationJob(id: caption.id, revision: 0, text: caption.source, generation: UUID())
        let note = TermNote(source: "クリーパー", target: "苦力怕", applied: true)
        precondition(store.applyTranslation("苦力怕", for: job, notes: [note]))
        store.ingest(text: "クリーパーが来た", start: 0, end: 2, isFinal: false)
        precondition(store.items[0].termNotes == [note], "a stable prefix retains applied terms")
        precondition(store.srt().contains("クリーパーが来た\n苦力怕"), "SRT must contain original source and corrected Chinese")
        store.ingest(text: "ゾンビが来た", start: 0, end: 2, isFinal: false)
        precondition(store.items[0].termNotes.isEmpty && !store.applyTranslation("苦力怕", for: job, notes: [note]))
        print("PASS: glossary loading, inheritance, Japanese longest match, English boundaries, Unicode, repeated tokens, protected attributes, fallback, cancellation, streaming and SRT")
    }
}
