import Foundation

enum FavoriteContentClassifier {
    static func normalizedContext(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(400))
    }

    static func normalizedDefinition(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(1200))
    }

    static func normalizedNote(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(400))
    }

    static func legacySentence(word: String, contextSentence: String?) -> String {
        if let contextSentence = normalizedContext(contextSentence) {
            return contextSentence
        }
        return word.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contextText(for entry: FavoriteEntry) -> String? {
        if let context = normalizedContext(entry.contextSentence) {
            return context
        }

        let legacy = entry.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacy.isEmpty,
              legacy.caseInsensitiveCompare(entry.word) != .orderedSame,
              !isLikelyDefinitionText(legacy) else {
            return nil
        }
        return String(legacy.prefix(400))
    }

    static func definitionText(for entry: FavoriteEntry) -> String? {
        if let definition = normalizedDefinition(entry.definitionSnapshot) {
            return definition
        }

        let legacy = entry.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelyDefinitionText(legacy) else { return nil }
        return String(legacy.prefix(1200))
    }

    static func listPreview(for entry: FavoriteEntry) -> String {
        if let context = contextText(for: entry) {
            return context
        }
        if let definition = definitionText(for: entry) {
            return "释义快照：" + firstLine(definition)
        }
        return "暂无语境"
    }

    static func reviewPrompt(for entry: FavoriteEntry) -> String {
        contextText(for: entry) ?? "暂无语境：\(entry.word)"
    }

    static func exportContext(for entry: FavoriteEntry) -> String {
        contextText(for: entry) ?? ""
    }

    static func containsTerm(_ text: String, term: String) -> Bool {
        let cleanedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTerm.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: cleanedTerm)
        let pattern = #"(?i)(^|[^A-Za-z])"# + escaped + #"($|[^A-Za-z])"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func isLikelyDefinitionText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()

        let hasPronunciation = trimmed.contains("BrE")
            || trimmed.contains("AmE")
            || trimmed.contains(" | ")
        let grammarMarkers = [
            " noun", " verb", " adjective", " adverb",
            " countable", " uncountable", " transitive",
            " intransitive", " phrasal verb", " origin "
        ].filter { lower.contains($0) }.count

        if hasPronunciation && grammarMarkers > 0 {
            return true
        }
        if trimmed.count > 240 && grammarMarkers >= 2 {
            return true
        }
        if lower.hasPrefix("noun ") || lower.hasPrefix("verb ") || lower.hasPrefix("adjective ") {
            return true
        }
        return false
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        return String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    }
}
