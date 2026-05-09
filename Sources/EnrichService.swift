import Cocoa

/// 一个词的扩展信息：来自 Wikipedia / Hacker News / 用户自己的语料
struct WordEnrichment {
    var wikipediaSummary: String?
    var wikipediaImagePath: String?     // 本地缓存图片绝对路径（已下载）
    var wikipediaURL: URL?
    var hackerNewsExamples: [HNExample] = []
    var ownContexts: [OwnContext] = []  // 用户自己保存过的句子
}

struct HNExample {
    let snippet: String           // 评论摘要（含此词）
    let author: String            // 评论作者
    let storyTitle: String        // 关联的 HN 帖子标题
    let url: URL                  // HN 评论或帖子 URL
}

struct OwnContext {
    let sentence: String
    let savedAt: Date
    let id: UUID
}

/// 把外部 + 本地的扩展信息聚合在一起（异步加载、互不阻塞）
final class EnrichService {
    static let shared = EnrichService()

    private let session: URLSession
    private let imagesDir: URL

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: cfg)

        let appSupport = Database.appSupportDir()
        let imgs = appSupport.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imgs, withIntermediateDirectories: true)
        self.imagesDir = imgs
    }

    /// 同步获取本地 cross-ref（用户自己的语料）
    func ownContexts(for word: String, excludingID: UUID? = nil, limit: Int = 5) -> [OwnContext] {
        Database.shared.searchFavoriteSentences(word: word, excludingID: excludingID, limit: limit)
    }

    /// 异步获取 Wikipedia 摘要+图片
    func fetchWikipedia(word: String, completion: @escaping (String?, URL?, String?) -> Void) {
        // REST API: https://en.wikipedia.org/api/rest_v1/page/summary/{title}
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else {
            DispatchQueue.main.async { completion(nil, nil, nil) }
            return
        }
        var req = URLRequest(url: url)
        req.setValue("QuickDict-mac/1.0 (https://github.com/local)", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: req) { [weak self] data, _, err in
            guard let self, let data, err == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(nil, nil, nil) }
                return
            }
            // type 可能是 "disambiguation" 之类，照样能用 extract
            let extract = json["extract"] as? String
            let pageURL: URL? = {
                if let urls = json["content_urls"] as? [String: Any],
                   let desktop = urls["desktop"] as? [String: Any],
                   let s = desktop["page"] as? String {
                    return URL(string: s)
                }
                return nil
            }()
            let imageURL: URL? = {
                if let thumb = json["thumbnail"] as? [String: Any],
                   let s = thumb["source"] as? String {
                    return URL(string: s)
                }
                return nil
            }()

            // 没有图片直接回调
            guard let imageURL else {
                DispatchQueue.main.async { completion(extract, pageURL, nil) }
                return
            }
            // 下载图片到本地缓存
            self.downloadImage(from: imageURL, key: word) { localPath in
                DispatchQueue.main.async { completion(extract, pageURL, localPath) }
            }
        }
        task.resume()
    }

    /// 异步获取 Hacker News 含此词的评论例句（Algolia API，免费）
    func fetchHackerNews(word: String, completion: @escaping ([HNExample]) -> Void) {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://hn.algolia.com/api/v1/search?query=\(encoded)&tags=comment&hitsPerPage=10") else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        let task = session.dataTask(with: url) { data, _, err in
            guard let data, err == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hits = json["hits"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            var out: [HNExample] = []
            for hit in hits {
                guard let raw = hit["comment_text"] as? String,
                      let objectID = hit["objectID"] as? String else { continue }
                // 提取包含此词的那个句子
                guard let snippet = Self.sentenceContaining(word: word, in: Self.stripHTML(raw)) else { continue }
                let author = hit["author"] as? String ?? "anon"
                let storyTitle = (hit["story_title"] as? String) ?? (hit["story_id"].map { "HN Story \($0)" } ?? "Hacker News")
                let cleanedSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleanedSnippet.count > 20, cleanedSnippet.count < 400 else { continue }
                let cmtURL = URL(string: "https://news.ycombinator.com/item?id=\(objectID)") ?? URL(string: "https://news.ycombinator.com")!
                out.append(HNExample(snippet: cleanedSnippet, author: author, storyTitle: storyTitle, url: cmtURL))
                if out.count >= 5 { break }
            }
            DispatchQueue.main.async { completion(out) }
        }
        task.resume()
    }

    // MARK: - 私有工具

    private func downloadImage(from url: URL, key: String, completion: @escaping (String?) -> Void) {
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let dest = imagesDir.appendingPathComponent("\(safeKey).img")
        // 缓存命中
        if FileManager.default.fileExists(atPath: dest.path) {
            completion(dest.path)
            return
        }
        let task = session.downloadTask(with: url) { tmp, _, _ in
            guard let tmp else { completion(nil); return }
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tmp, to: dest)
                completion(dest.path)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }

    private static func stripHTML(_ s: String) -> String {
        // 简单 HTML 解码 + 标签清理（HN comment 是 HTML）
        var t = s
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "&#x27;", with: "'")
        t = t.replacingOccurrences(of: "&#x2F;", with: "/")
        t = t.replacingOccurrences(of: "&quot;", with: "\"")
        t = t.replacingOccurrences(of: "&amp;", with: "&")
        t = t.replacingOccurrences(of: "&lt;", with: "<")
        t = t.replacingOccurrences(of: "&gt;", with: ">")
        t = t.replacingOccurrences(of: "&#039;", with: "'")
        return t
    }

    /// 从段落里抽出第一个含此词（whole word）的句子
    private static func sentenceContaining(word: String, in text: String) -> String? {
        // 句号/问号/感叹号断句
        let sentences = text.split(whereSeparator: { ".!?\n".contains($0) })
        let lower = word.lowercased()
        for s in sentences {
            let str = String(s)
            let strLower = str.lowercased()
            // 整词匹配
            let boundary = CharacterSet(charactersIn: " ,;:'\"()[]{}-—/").union(.whitespacesAndNewlines)
            if let r = strLower.range(of: lower) {
                let before = r.lowerBound == strLower.startIndex ? " " : String(strLower[strLower.index(before: r.lowerBound)])
                let after = r.upperBound == strLower.endIndex ? " " : String(strLower[r.upperBound])
                if (before.unicodeScalars.first.map { boundary.contains($0) } ?? true) &&
                   (after.unicodeScalars.first.map { boundary.contains($0) } ?? true) {
                    return str
                }
            }
        }
        return nil
    }
}
