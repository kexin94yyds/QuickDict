import Foundation

enum EnglishCandidateFilter {
    private static let allowedShortWords: Set<String> = ["ai", "ui", "ux", "os", "db", "io"]
    private static let stopWords: Set<String> = [
        "verb", "noun", "adjective", "adverb", "transitive verb", "intransitive verb",
        "plural noun", "countable noun", "uncountable noun", "preposition", "pronoun",
        "article", "auxiliary verb", "modal verb", "interjection", "conjunction"
    ]

    static func usefulUnique(
        _ words: [String],
        maxLength: Int = 40,
        maxWords: Int = 5
    ) -> [String] {
        words
            .map(normalize)
            .filter { isUseful($0, maxLength: maxLength, maxWords: maxWords) }
            .reduce(into: [String]()) { out, word in
                if !out.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                    out.append(word)
                }
            }
    }

    static func dictionaryBacked(
        _ words: [String],
        maxLength: Int = 40,
        maxWords: Int = 5,
        lookup: (String) -> LookupResult? = { DictService.shared.lookup($0) }
    ) -> [String] {
        usefulUnique(words, maxLength: maxLength, maxWords: maxWords)
            .compactMap { word -> String? in
                guard let result = lookup(word) else { return nil }
                return normalize(result.word)
            }
            .reduce(into: [String]()) { out, word in
                if !out.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                    out.append(word)
                }
            }
    }

    private static func normalize(_ word: String) -> String {
        let trimmed = word
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
        return trimmed
    }

    private static func isUseful(_ word: String, maxLength: Int, maxWords: Int) -> Bool {
        guard !word.isEmpty, word.count <= maxLength else { return false }
        if word.count < 3, !allowedShortWords.contains(word) { return false }
        guard !stopWords.contains(word) else { return false }
        guard word.split(separator: " ").count <= maxWords else { return false }
        return word.range(of: #"^[a-z][a-z '\-]*$"#, options: .regularExpression) != nil
    }
}
