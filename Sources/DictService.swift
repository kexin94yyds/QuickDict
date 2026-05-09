import Foundation
import CoreServices

/// 查词结果
struct LookupResult {
    let word: String         // 实际查到的词（可能是 lemma 还原后的）
    let definition: String   // 格式化后的释义文本
    let source: Source

    enum Source: String {
        case appleDictionary = "Apple"
        case ecdict = "ECDICT"
        case none = "None"
    }
}

/// 统一查词服务：苹果系统词典 → ECDICT
final class DictService {
    static let shared = DictService()

    private init() {}

    /// 同步查询（在主线程调用，因 DCSCopyTextDefinition 是同步的且不重）
    func lookup(_ rawWord: String) -> LookupResult? {
        let word = sanitize(rawWord)
        guard !word.isEmpty else { return nil }

        let appleDef = appleLookup(word)
        let ecdictEntry = ECDictionary.shared.lookup(word)

        // 把 ECDICT 的中文/词性/标签部分单独抽出来（不含原词标题）
        let ecdictTrimmed: String? = ecdictEntry.map { entry in
            ECDictionary.format(entry)
                .replacingOccurrences(of: "^\(entry.word)\\s*\\n?", with: "",
                                      options: .regularExpression)
        }

        // 优先苹果词典；如果苹果命中但没中文，追加 ECDICT 的中文部分
        if let apple = appleDef, !apple.isEmpty {
            if containsChinese(apple) || ecdictTrimmed == nil {
                return LookupResult(word: word, definition: apple, source: .appleDictionary)
            }
            // 合并
            let merged = apple + "\n\n— 中文释义 (ECDICT) ——\n" + (ecdictTrimmed ?? "")
            return LookupResult(word: word, definition: merged, source: .appleDictionary)
        }

        // 苹果没命中，回退到 ECDICT
        if let entry = ecdictEntry {
            let formatted = ECDictionary.format(entry)
            let actual = entry.word.isEmpty ? word : entry.word
            return LookupResult(word: actual, definition: formatted, source: .ecdict)
        }

        return nil
    }

    private func containsChinese(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) { return true }
        }
        return false
    }

    private func appleLookup(_ word: String) -> String? {
        let cf = word as CFString
        let len = (word as NSString).length
        guard let result = DCSCopyTextDefinition(nil, cf, CFRangeMake(0, len))?.takeRetainedValue() else {
            return nil
        }
        let s = result as String
        return s.isEmpty ? nil : s
    }

    private func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉首尾标点/符号
        let punct = CharacterSet.punctuationCharacters.union(.symbols)
        return trimmed.trimmingCharacters(in: punct)
    }
}
