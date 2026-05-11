import Foundation

struct ChineseEnglishResolution {
    let original: String
    let candidates: [String]
    let imageTerms: [String]

    var primary: String {
        candidates.first ?? original
    }

    init(original: String, candidates: [String], imageTerms: [String] = []) {
        self.original = original
        self.candidates = candidates
        self.imageTerms = imageTerms
    }
}

final class ChineseEnglishResolver {
    static let shared = ChineseEnglishResolver()

    private let builtInCandidates: [String: [String]] = [
        "尴尬": ["awkward", "embarrassed", "embarrassing", "embarrassment"],
        "难堪": ["embarrassed", "awkward", "embarrassing"],
        "窘迫": ["embarrassed", "awkward"],
        "开心": ["happy", "joyful", "joy"],
        "快乐": ["happy", "joyful", "joy"],
        "高兴": ["happy", "pleased", "glad"],
        "悲伤": ["sad", "sadness", "sorrow"],
        "难过": ["sad", "upset", "sadness"],
        "焦虑": ["anxious", "anxiety"],
        "紧张": ["nervous", "tense", "anxious"],
        "害怕": ["afraid", "fear", "scared"],
        "恐惧": ["fear", "afraid", "scared"],
        "生气": ["angry", "anger"],
        "愤怒": ["angry", "anger", "furious"],
        "困惑": ["confused", "confusion", "puzzled"],
        "惊讶": ["surprised", "surprise"],
        "羡慕": ["envy", "admire"],
        "嫉妒": ["jealous", "envy"],
        "孤独": ["lonely", "loneliness"],
        "自信": ["confident", "confidence"],
        "勇敢": ["brave", "courage"],
        "诚实": ["honest", "honesty"],
        "善良": ["kind", "kindness"],
        "压力": ["stress", "pressure"],
        "自由": ["freedom", "free"],
        "习惯": ["habit", "custom"],
        "机会": ["opportunity", "chance"],
        "风险": ["risk", "danger"],
        "原因": ["reason", "cause"],
        "结果": ["result", "outcome"],
        "问题": ["problem", "issue"],
        "目标": ["goal", "target"],
        "方法": ["method", "approach"],
        "重启": ["restart", "reboot"],
        "重新启动": ["restart", "reboot"],
        "苹果": ["apple"],
        "河流": ["river"],
        "森林": ["forest"],
        "山": ["mountain"],
        "海": ["sea", "ocean"]
    ]

    private init() {}

    func resolve(_ raw: String, appleDefinition: String? = nil) -> ChineseEnglishResolution? {
        let original = normalize(raw)
        guard containsCJK(original) else { return nil }

        var candidates: [String] = []
        if let exact = builtInCandidates[original] {
            append(&candidates, exact)
        } else if let contained = builtInCandidates.keys
            .filter({ original.contains($0) })
            .max(by: { $0.count < $1.count }) {
            append(&candidates, builtInCandidates[contained] ?? [])
        }
        append(&candidates, englishCandidates(fromAppleDefinition: appleDefinition))
        append(&candidates, ECDictionary.shared.lookupByChinese(original, limit: 8).map(\.word))

        let filtered = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter(Self.isUsefulEnglishCandidate)
            .reduce(into: [String]()) { out, word in
                if !out.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                    out.append(word)
                }
            }

        guard !filtered.isEmpty else { return nil }
        let singleWords = filtered.filter { !$0.contains(" ") }
        let phrases = filtered.filter { $0.contains(" ") }
        let ordered = singleWords.isEmpty ? filtered : singleWords + phrases
        return ChineseEnglishResolution(original: original, candidates: ordered, imageTerms: ordered)
    }

    func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }

    private func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let punct = CharacterSet.punctuationCharacters.union(.symbols)
        return trimmed.trimmingCharacters(in: punct)
    }

    private func append(_ target: inout [String], _ words: [String]) {
        for word in words where !word.isEmpty {
            target.append(word)
        }
    }

    private static func isUsefulEnglishCandidate(_ word: String) -> Bool {
        guard word.count >= 2, word.count <= 32 else { return false }
        let lower = word.lowercased()
        let stopWords: Set<String> = [
            "verb", "noun", "adjective", "adverb", "transitive verb", "intransitive verb",
            "plural noun", "countable noun", "uncountable noun", "preposition", "pronoun",
            "article", "auxiliary verb", "modal verb", "interjection", "conjunction"
        ]
        guard !stopWords.contains(lower) else { return false }
        guard lower.split(separator: " ").count <= 4 else { return false }
        return word.range(of: #"^[a-z][a-z '\-]*$"#, options: .regularExpression) != nil
    }

    private func englishCandidates(fromAppleDefinition definition: String?) -> [String] {
        guard let definition, !definition.isEmpty else { return [] }
        let pattern = #"[A-Za-z][A-Za-z' -]{1,48}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = definition as NSString
        let matches = regex.matches(in: definition, range: NSRange(location: 0, length: ns.length))
        return matches.map { match in
            ns.substring(with: match.range)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                .lowercased()
        }
    }
}
