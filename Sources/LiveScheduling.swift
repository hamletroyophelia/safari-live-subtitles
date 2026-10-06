import Foundation

/// Exact-text memo scoped to one language/glossary session, never persisted.
struct TranslationMemo {
    private var values: [String: GlossaryTranslation] = [:]
    private var order: [String] = []
    private var bytes = 0
    let limit: Int
    let byteLimit: Int
    init(limit: Int = 64, byteLimit: Int = 65_536) {
        self.limit = max(1, limit); self.byteLimit = max(1, byteLimit)
    }
    var count: Int { values.count }
    func result(for text: String) -> GlossaryTranslation? { values[text] }
    mutating func insert(_ result: GlossaryTranslation, for text: String) {
        let size = text.utf8.count + result.text.utf8.count
            + result.notes.reduce(0) { $0 + $1.source.utf8.count + $1.target.utf8.count }
        guard !result.usedFallback, text.count <= 256, size <= byteLimit, values[text] == nil else { return }
        while order.count >= limit || bytes + size > byteLimit {
            let key = order.removeFirst()
            if let old = values.removeValue(forKey: key) {
                bytes -= key.utf8.count + old.text.utf8.count
                    + old.notes.reduce(0) { $0 + $1.source.utf8.count + $1.target.utf8.count }
            }
        }
        values[text] = result; order.append(text); bytes += size
    }
}

/// Translate quickly when the model keeps up; merge revisions when it falls behind.
struct PartialTranslationSchedule {
    private(set) var averageSeconds = 0.15
    private var lastEnqueuedTime = -Double.infinity
    var interval: Double { min(0.45, max(0.12, averageSeconds)) }
    func delay(now: Double) -> Double { max(0.015, interval - (now - lastEnqueuedTime)) }
    mutating func enqueued(now: Double) { lastEnqueuedTime = now }
    mutating func completed(seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        averageSeconds = averageSeconds * 0.7 + min(2, seconds) * 0.3
    }
}
