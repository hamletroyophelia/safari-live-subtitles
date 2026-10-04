import Foundation
import Translation

struct GlossaryTerm: Codable, Equatable {
    let ja: [String]
    let en: [String]
    let target: String
    let mode: String?
    enum CodingKeys: String, CodingKey { case ja, en, target = "zh-Hans", mode }
}

struct GameProfile: Codable, Identifiable, Equatable {
    let id: String
    let title: String?
    let inherits: [String]?
    let resolveConflicts: String?
    let terms: [GlossaryTerm]
    var displayName: String { title ?? id }
}

struct GlossaryDocument: Codable {
    let schemaVersion: Int
    let profiles: [GameProfile]
}

struct TermNote: Codable, Equatable {
    let source: String
    let target: String
    let applied: Bool
}

struct GlossaryMatch {
    let range: NSRange
    let source: String
    let term: GlossaryTerm
    let priority: Int
}

struct GlossaryPlan {
    let source: String
    let matches: [GlossaryMatch]
    let tokens: [(match: GlossaryMatch, token: String)]

    init(source: String, matches: [GlossaryMatch]) {
        self.source = source
        self.matches = matches
        var prefix = "LLTERM"
        while source.contains(prefix) { prefix += "Z" }
        tokens = matches.filter { $0.term.mode == "protect" }.enumerated().map {
            (match: $0.element, token: "\(prefix)\($0.offset)X")
        }
    }

    @available(macOS 26.4, *)
    func attributedInput() -> AttributedString {
        let original = source as NSString
        var input = AttributedString()
        var position = 0
        for entry in tokens {
            input.append(AttributedString(original.substring(with: NSRange(location: position, length: entry.match.range.location - position))))
            var token = AttributedString(entry.token)
            token.skipsTranslation = true
            input.append(token)
            position = NSMaxRange(entry.match.range)
        }
        input.append(AttributedString(original.substring(from: position)))
        return input
    }

    /// Reject lost, duplicated, altered or unknown markers; never expose markers in subtitles.
    func restore(_ translated: String) -> String? {
        guard !translated.isEmpty else { return nil }
        var text = translated
        for entry in tokens {
            guard text.components(separatedBy: entry.token).count == 2 else { return nil }
            text = text.replacingOccurrences(of: entry.token, with: entry.match.term.target)
        }
        if let token = tokens.first?.token {
            let prefix = String(token.prefix { !$0.isNumber })
            guard !text.contains(prefix) else { return nil }
        }
        return text
    }

    func notes(applied: Bool) -> [TermNote] {
        var seen = Set<String>()
        return matches.compactMap { match in
            let key = match.source.lowercased() + "\u{0}" + match.term.target
            guard seen.insert(key).inserted else { return nil }
            return TermNote(source: match.source, target: match.term.target,
                            applied: applied && match.term.mode == "protect")
        }
    }
}

struct GameGlossary {
    let document: GlossaryDocument
    private struct Candidate {
        let pattern: NSRegularExpression
        let term: GlossaryTerm
        let priority: Int
    }
    private let candidates: [String: [Candidate]]
    var profiles: [GameProfile] { document.profiles }

    static func bundledURL() throws -> URL {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "game-glossary", withExtension: "json") else {
            throw GlossaryError("内置词典未找到，请重新构建应用。")
        }
        return url
    }

    init(data: Data) throws {
        guard data.count <= 2_000_000 else { throw GlossaryError("词典不能超过 2 MB。") }
        let document: GlossaryDocument
        do { document = try JSONDecoder().decode(GlossaryDocument.self, from: data) }
        catch { throw GlossaryError("词典 JSON 格式不正确，请使用项目提供的格式。") }
        guard (1...2).contains(document.schemaVersion), !document.profiles.isEmpty,
              document.profiles.count <= 64 else { throw GlossaryError("不支持的词典版本或游戏分类数量。") }
        let ids = document.profiles.map(\.id)
        guard Set(ids).count == ids.count, ids.allSatisfy({ $0.range(of: "^[a-z0-9_]{1,64}$", options: .regularExpression) != nil }) else {
            throw GlossaryError("游戏分类 ID 必须唯一，仅使用小写字母、数字或下划线。")
        }
        guard document.profiles.reduce(0, { $0 + $1.terms.count }) <= 2000 else { throw GlossaryError("词典最多包含 2000 条术语。") }
        let byID = Dictionary(uniqueKeysWithValues: document.profiles.map { ($0.id, $0) })
        func expanded(_ id: String, path: Set<String>) throws -> [GameProfile] {
            var visited = Set<String>()
            var active = path
            var result: [GameProfile] = []
            func visit(_ next: String) throws {
                guard !active.contains(next), let profile = byID[next] else { throw GlossaryError("分类继承不存在或存在循环。") }
                guard !visited.contains(next) else { return }
                active.insert(next)
                for parent in profile.inherits ?? [] { try visit(parent) }
                active.remove(next)
                visited.insert(next)
                result.append(profile)
            }
            try visit(id)
            return result
        }
        for profile in document.profiles {
            guard (profile.title?.count ?? 0) <= 80, (profile.inherits?.count ?? 0) <= 64,
                  profile.resolveConflicts == nil || profile.resolveConflicts == "hint" else { throw GlossaryError("分类名称、继承列表或冲突策略无效。") }
            for term in profile.terms {
                guard !term.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      term.target.count <= 100, !term.target.contains("LLTERM"),
                      !term.target.contains("\n"), term.mode == nil || ["protect", "hint"].contains(term.mode!),
                      !term.ja.isEmpty || !term.en.isEmpty,
                      term.ja.count + term.en.count <= 24,
                      (term.ja + term.en).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 120 && !$0.contains("\n") }) else {
                    throw GlossaryError("术语内容或模式无效；模式应为 protect 或 hint。")
                }
            }
            _ = try expanded(profile.id, path: [])
        }
        var candidates: [String: [Candidate]] = [:]
        // Inherited and combined profiles share compiled regexes for identical aliases.
        var compiledPatterns: [String: NSRegularExpression] = [:]
        for profile in document.profiles {
            let inherited = try expanded(profile.id, path: [])
            for language in ["ja", "en"] {
                var aliases: [String: Candidate] = [:]
                for (priority, group) in inherited.enumerated() {
                    for term in group.terms {
                        for alias in language == "ja" ? term.ja : term.en {
                            let escaped = NSRegularExpression.escapedPattern(for: alias)
                            let pattern = language == "en" ? "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])" : escaped
                            let key = language == "en" ? alias.lowercased() : alias
                            var effective = term
                            if profile.resolveConflicts == "hint", let previous = aliases[key],
                               previous.term.target != term.target || previous.term.mode != term.mode {
                                let targets = Set(previous.term.target.components(separatedBy: " / ") + [term.target])
                                effective = GlossaryTerm(ja: term.ja, en: term.en, target: targets.sorted().joined(separator: " / "), mode: "hint")
                            }
                            let patternKey = language + ":" + pattern
                            let regex: NSRegularExpression
                            if let cached = compiledPatterns[patternKey] { regex = cached }
                            else {
                                regex = try NSRegularExpression(pattern: pattern, options: language == "en" ? [.caseInsensitive] : [])
                                compiledPatterns[patternKey] = regex
                            }
                            aliases[key] = Candidate(pattern: regex, term: effective, priority: priority)
                        }
                    }
                }
                candidates[profile.id + ":" + language] = Array(aliases.values)
            }
        }
        self.document = document
        self.candidates = candidates
    }

    func plan(source: String, language: SourceLanguage, profileID: String) -> GlossaryPlan {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var found: [GlossaryMatch] = []
        for candidate in candidates[profileID + ":" + language.code] ?? [] {
            for match in candidate.pattern.matches(in: source, range: range) {
                found.append(GlossaryMatch(range: match.range, source: (source as NSString).substring(with: match.range),
                                          term: candidate.term, priority: candidate.priority))
            }
        }
        found.sort {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            if $0.range.length != $1.range.length { return $0.range.length > $1.range.length }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.term.target < $1.term.target
        }
        var matches: [GlossaryMatch] = []
        var end = 0
        for match in found where match.range.location >= end {
            matches.append(match)
            end = NSMaxRange(match.range)
        }
        return GlossaryPlan(source: source, matches: matches)
    }
}

struct GlossaryError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct GlossaryTranslation {
    let text: String
    let notes: [TermNote]
    let usedFallback: Bool
}

enum GlossaryTranslator {
    @MainActor static func translate(_ text: String, language: SourceLanguage, glossary: GameGlossary?,
                                     profileID: String, session: TranslationSession) async throws -> GlossaryTranslation {
        let plan = glossary?.plan(source: text, language: language, profileID: profileID)
        if #available(macOS 26.4, *) {
            return try await execute(text, plan: plan, plain: { try await session.translate($0).targetText },
                protected: { try await session.translate($0.attributedInput()).targetText })
        }
        return try await execute(text, plan: plan, plain: { try await session.translate($0).targetText }, protected: nil)
    }

    @MainActor static func execute(_ text: String, plan: GlossaryPlan?, plain: (String) async throws -> String,
                                   protected: ((GlossaryPlan) async throws -> String)?) async throws -> GlossaryTranslation {
        guard let plan else { return GlossaryTranslation(text: try await plain(text), notes: [], usedFallback: false) }
        if let protected, !plan.tokens.isEmpty {
            do {
                let response = try await protected(plan)
                try Task.checkCancellation()
                if let restored = plan.restore(response) {
                    return GlossaryTranslation(text: restored, notes: plan.notes(applied: true), usedFallback: false)
                }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
            }
            // A failed protected translation gets one plain retry using the untouched original.
            return GlossaryTranslation(text: try await plain(text),
                                       notes: plan.notes(applied: false), usedFallback: true)
        }
        return GlossaryTranslation(text: try await plain(text),
                                   notes: plan.notes(applied: false), usedFallback: false)
    }
}
