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

            // 主接口有图：直接下载
            if let imageURL {
                self.downloadImage(from: imageURL, key: word) { localPath in
                    DispatchQueue.main.async { completion(extract, pageURL, localPath) }
                }
                return
            }
            // 主接口没有图（消歧义/抽象词），回退到搜索接口 + 语义近邻
            self.fetchImageViaFallbacks(for: word) { fallbackPath in
                DispatchQueue.main.async { completion(extract, pageURL, fallbackPath) }
            }
        }
        task.resume()
    }

    /// Wikipedia search + pageimages 回退：找第一个有缩略图的结果
    private func fetchImageFallback(for word: String, completion: @escaping (String?) -> Void) {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(nil); return
        }
        // 用 generator=search + prop=pageimages 一次拿到 top 候选 + 缩略图
        let urlStr = "https://en.wikipedia.org/w/api.php?action=query&format=json"
            + "&prop=pageimages&piprop=thumbnail&pithumbsize=480"
            + "&generator=search&gsrsearch=\(encoded)&gsrlimit=6"
        guard let url = URL(string: urlStr) else { completion(nil); return }
        var req = URLRequest(url: url)
        req.setValue("QuickDict-mac/1.0", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: req) { [weak self] data, _, err in
            guard let self, let data, err == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let query = json["query"] as? [String: Any],
                  let pages = query["pages"] as? [String: Any] else {
                completion(nil); return
            }
            // 按 search index 排序候选
            let sorted = pages.values.compactMap { $0 as? [String: Any] }.sorted { a, b in
                let ai = (a["index"] as? Int) ?? 99
                let bi = (b["index"] as? Int) ?? 99
                return ai < bi
            }
            for page in sorted {
                if let thumb = page["thumbnail"] as? [String: Any],
                   let s = thumb["source"] as? String,
                   let imageURL = URL(string: s) {
                    self.downloadImage(from: imageURL, key: word) { path in
                        completion(path)
                    }
                    return
                }
            }
            completion(nil)
        }
        task.resume()
    }

    /// 取图回退链：Wikipedia search → Datamuse 语义近邻
    private func fetchImageViaFallbacks(for word: String, completion: @escaping (String?) -> Void) {
        fetchImageFallback(for: word) { [weak self] path in
            if let path { completion(path); return }
            guard let self else { completion(nil); return }
            self.fetchImageViaNeighbors(originalWord: word, completion: completion)
        }
    }

    /// 通过语义近邻（上位词 / 反向词典）找图：每个邻居跑一次 Wikipedia summary 取缩略图
    private func fetchImageViaNeighbors(originalWord: String, completion: @escaping (String?) -> Void) {
        fetchSemanticNeighbors(for: originalWord) { [weak self] neighbors in
            guard let self, !neighbors.isEmpty else { completion(nil); return }
            self.tryNeighborsForImage(ArraySlice(neighbors), completion: completion)
        }
    }

    private func tryNeighborsForImage(_ neighbors: ArraySlice<String>, completion: @escaping (String?) -> Void) {
        guard let neighbor = neighbors.first else { completion(nil); return }
        let rest = neighbors.dropFirst()
        fetchWikipediaThumbnailURL(forTitle: neighbor) { [weak self] imageURL in
            guard let self else { completion(nil); return }
            guard let imageURL else {
                self.tryNeighborsForImage(rest, completion: completion); return
            }
            // 用 neighbor 做缓存 key，方便跨原词共享
            self.downloadImage(from: imageURL, key: neighbor) { [weak self] path in
                if let path { completion(path); return }
                self?.tryNeighborsForImage(rest, completion: completion)
            }
        }
    }

    private func fetchWikipediaThumbnailURL(forTitle title: String, completion: @escaping (URL?) -> Void) {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.setValue("QuickDict-mac/1.0 (https://github.com/local)", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let thumb = json["thumbnail"] as? [String: Any],
                  let s = thumb["source"] as? String,
                  let u = URL(string: s) else {
                completion(nil); return
            }
            completion(u)
        }
        task.resume()
    }

    /// Datamuse 语义近邻：rel_spc（上位词，更稳）+ ml（means-like / 反向词典）并发查询、合并去重
    /// 限制最多 3 个，保持网络开销可控
    private func fetchSemanticNeighbors(for word: String, completion: @escaping ([String]) -> Void) {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              !encoded.isEmpty else {
            completion([]); return
        }
        let endpoints = [
            "https://api.datamuse.com/words?rel_spc=\(encoded)&max=5",  // hypernym
            "https://api.datamuse.com/words?ml=\(encoded)&max=5"        // means-like
        ]
        let group = DispatchGroup()
        // 索引对齐结果，保证 spc 优先排序
        var results: [[String]] = Array(repeating: [], count: endpoints.count)
        let lock = NSLock()
        for (i, urlStr) in endpoints.enumerated() {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.setValue("QuickDict-mac/1.0", forHTTPHeaderField: "User-Agent")
            group.enter()
            let task = session.dataTask(with: req) { data, _, _ in
                let words = Self.parseDatamuseWords(data: data)
                lock.lock(); results[i] = words; lock.unlock()
                group.leave()
            }
            task.resume()
        }
        group.notify(queue: .global()) {
            var seen = Set<String>()
            seen.insert(word.lowercased())
            var out: [String] = []
            for arr in results {
                for w in arr {
                    let key = w.lowercased()
                    // 跳过含空格的多词条目（Wikipedia summary 命中率差）
                    if key.contains(" ") { continue }
                    if seen.contains(key) { continue }
                    seen.insert(key)
                    out.append(w)
                    if out.count >= 3 { break }
                }
                if out.count >= 3 { break }
            }
            completion(out)
        }
    }

    private static func parseDatamuseWords(data: Data?) -> [String] {
        guard let data,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { $0["word"] as? String }
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
