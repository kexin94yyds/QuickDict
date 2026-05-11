import Foundation
import Security

enum GeminiAPIKeyStore {
    private static let service = "QuickDict.GeminiAPIKey"
    private static let account = "gemini"

    static func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }

        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        SecItemDelete(baseQuery() as CFDictionary) == errSecSuccess
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

final class GeminiEnglishResolver {
    static let shared = GeminiEnglishResolver()

    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 8
        session = URLSession(configuration: cfg)
    }

    func resolveSync(_ chinese: String, timeout: TimeInterval = 6) -> ChineseEnglishResolution? {
        guard let apiKey = GeminiAPIKeyStore.load(),
              let url = URL(string: endpoint + "?key=" + apiKey) else {
            return nil
        }

        let prompt = """
        Return only compact JSON for an English-learning dictionary app.
        Chinese input: \(chinese)
        Choose common English dictionary headwords, prefer single words.
        primary: best general English headword.
        candidates: 3-6 useful English headwords or short phrases.
        image_terms: 2-4 visually searchable English terms, prefer concrete terms.
        JSON schema: {"primary":"...","candidates":["..."],"image_terms":["..."]}
        """

        let body: [String: Any] = [
            "contents": [[
                "parts": [[
                    "text": prompt
                ]]
            ]],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 160,
                "responseMimeType": "application/json"
            ]
        ]

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        let semaphore = DispatchSemaphore(value: 0)
        var resolution: ChineseEnglishResolution?

        let task = session.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let text = Self.extractText(from: data),
                  let parsed = Self.parseResolutionJSON(text, original: chinese) else {
                return
            }
            resolution = parsed
        }
        task.resume()

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            return nil
        }
        return resolution
    }

    private static func extractText(from data: Data?) -> String? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            return nil
        }
        return text
    }

    private static func parseResolutionJSON(_ text: String, original: String) -> ChineseEnglishResolution? {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let primary = (obj["primary"] as? String).map(cleanWord)
        let candidates = (obj["candidates"] as? [String] ?? []).map(cleanWord)
        let imageTerms = (obj["image_terms"] as? [String] ?? []).map(cleanWord)

        var ordered: [String] = []
        if let primary, !primary.isEmpty { ordered.append(primary) }
        appendUnique(candidates, to: &ordered)
        let filtered = ordered.filter(isUsefulCandidate)
        guard !filtered.isEmpty else { return nil }

        var imageOrdered: [String] = []
        appendUnique(imageTerms, to: &imageOrdered)
        appendUnique(filtered, to: &imageOrdered)
        imageOrdered = imageOrdered.filter(isUsefulCandidate)

        return ChineseEnglishResolution(original: original, candidates: filtered, imageTerms: imageOrdered)
    }

    private static func cleanWord(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
    }

    private static func appendUnique(_ words: [String], to out: inout [String]) {
        for word in words where !word.isEmpty {
            if !out.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                out.append(word)
            }
        }
    }

    private static func isUsefulCandidate(_ word: String) -> Bool {
        guard word.count >= 2, word.count <= 40 else { return false }
        guard word.split(separator: " ").count <= 5 else { return false }
        return word.range(of: #"^[a-z][a-z '\-]*$"#, options: .regularExpression) != nil
    }
}
