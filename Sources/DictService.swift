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

        // 1) 苹果系统词典
        if let def = appleLookup(word), !def.isEmpty {
            return LookupResult(word: word, definition: def, source: .appleDictionary)
        }

        // 2) ECDICT 离线词典
        if let entry = ECDictionary.shared.lookup(word) {
            let formatted = ECDictionary.format(entry)
            // 如果 ECDICT 命中的是变体的 lemma，使用 lemma 作为单词显示
            let actual = entry.word.isEmpty ? word : entry.word
            return LookupResult(word: actual, definition: formatted, source: .ecdict)
        }

        // 3) 苹果词典对原词查不到，尝试用小写再查一次（已在 sanitize 后基本一致）
        return nil
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
