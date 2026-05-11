import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// ECDICT 词条
/// 字段参考 https://github.com/skywind3000/ECDICT
struct ECDictEntry {
    let word: String
    let phonetic: String?      // 音标
    let definition: String?    // 英文释义
    let translation: String?   // 中文释义
    let pos: String?           // 词性
    let collins: Int?          // 柯林斯星级 1-5
    let oxford: Int?           // 是否牛津 3000 (0/1)
    let tag: String?           // zk/gk/cet4/cet6/ky/toefl/ielts/gre
    let bnc: Int?              // BNC 词频
    let frq: Int?              // 当代词频
    let exchange: String?      // 词形变化（s/p/i/3/r/t/0/1）
    let detail: String?        // JSON 扩展
    let audio: String?         // 发音 URL（部分）

    /// exchange 解析：返回原型词（lemma）
    /// 例: "0:run/1:p" 表示 lemma 是 "run", 当前词是过去式
    var lemma: String? {
        guard let exchange, !exchange.isEmpty else { return nil }
        let parts = exchange.split(separator: "/")
        for part in parts {
            let kv = part.split(separator: ":", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0] == "0" {
                return kv[1].isEmpty ? nil : kv[1]
            }
        }
        return nil
    }
}

/// ECDICT 离线词典
final class ECDictionary {
    static let shared = ECDictionary()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "QuickDict.ECDictionary", qos: .userInitiated)

    /// 词典文件路径
    var dbURL: URL {
        Database.appSupportDir().appendingPathComponent("ecdict.db")
    }

    /// 是否已经准备好（数据库已下载并打开）
    private(set) var isReady: Bool = false
    private var tableName: String?

    /// 默认下载源（精简版 stardict.7z 已经过大；优先使用 ecdict-sqlite-28 release）
    /// release 页：https://github.com/skywind3000/ECDICT/releases
    static let defaultDownloadURL = URL(string: "https://github.com/skywind3000/ECDICT/releases/download/1.0.28/ecdict-sqlite-28.zip")!

    private init() {
        if FileManager.default.fileExists(atPath: dbURL.path) {
            openIfPossible()
        }
    }

    /// 打开词典文件（已存在时调用）
    func openIfPossible() {
        queue.sync {
            guard FileManager.default.fileExists(atPath: dbURL.path),
                  let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
                  let size = attrs[.size] as? NSNumber,
                  size.intValue > 0 else {
                isReady = false
                tableName = nil
                return
            }
            if sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                tableName = detectTableName()
                isReady = tableName != nil
                if isReady {
                    NSLog("ECDICT 词典已加载: \(dbURL.path)")
                } else {
                    NSLog("ECDICT 打开失败: 未找到 stardict/ecdict 表")
                    sqlite3_close(db)
                    db = nil
                }
            } else {
                NSLog("ECDICT 打开失败: \(String(cString: sqlite3_errmsg(db)))")
                isReady = false
                tableName = nil
            }
        }
    }

    /// 主表名（ECDICT release 中通常为 stardict）
    private func detectTableName() -> String? {
        for name in ["stardict", "ecdict"] {
            if tableExists(name) {
                return name
            }
        }
        return nil
    }

    private func tableExists(_ name: String) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// 查询单词。会同时尝试 lemma 还原。
    func lookup(_ word: String) -> ECDictEntry? {
        guard isReady else { return nil }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if let entry = queryExact(trimmed) {
            // 如果当前词是变体（exchange 中包含 0:lemma），尝试再查 lemma 拿更完整释义
            if let lemma = entry.lemma, lemma != trimmed,
               (entry.translation?.isEmpty ?? true), let lemmaEntry = queryExact(lemma) {
                return lemmaEntry
            }
            return entry
        }
        return nil
    }

    private func queryExact(_ word: String) -> ECDictEntry? {
        queue.sync {
            guard let db, let tableName else { return nil }
            let sql = "SELECT word, phonetic, definition, translation, pos, collins, oxford, tag, bnc, frq, exchange, detail, audio FROM \(tableName) WHERE word = ? COLLATE NOCASE LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            func textCol(_ i: Int32) -> String? {
                if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
                guard let p = sqlite3_column_text(stmt, i) else { return nil }
                let s = String(cString: p)
                return s.isEmpty ? nil : s
            }
            func intCol(_ i: Int32) -> Int? {
                if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
                return Int(sqlite3_column_int(stmt, i))
            }

            return ECDictEntry(
                word: textCol(0) ?? word,
                phonetic: textCol(1),
                definition: textCol(2),
                translation: textCol(3),
                pos: textCol(4),
                collins: intCol(5),
                oxford: intCol(6),
                tag: textCol(7),
                bnc: intCol(8),
                frq: intCol(9),
                exchange: textCol(10),
                detail: textCol(11),
                audio: textCol(12)
            )
        }
    }

    /// 通过中文释义反查英文候选。用于中文查词时先映射到英文主词。
    func lookupByChinese(_ chinese: String, limit: Int = 8) -> [ECDictEntry] {
        let query = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return queue.sync {
            guard let db, let tableName else { return [] }
            let like = "%\(query)%"
            let prefix = "\(query)%"
            let sql = """
                SELECT word, phonetic, definition, translation, pos, collins, oxford, tag, bnc, frq, exchange, detail, audio
                FROM \(tableName)
                WHERE translation LIKE ?
                ORDER BY
                    CASE
                        WHEN translation = ? THEN 0
                        WHEN translation LIKE ? THEN 1
                        ELSE 2
                    END,
                    CASE WHEN frq IS NULL OR frq <= 0 THEN 999999 ELSE frq END ASC,
                    CASE WHEN collins IS NULL OR collins <= 0 THEN 1 ELSE 0 END,
                    length(word) ASC
                LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, like, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, query, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, prefix, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 4, Int32(limit))

            var out: [ECDictEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let entry = Self.readEntry(stmt: stmt) {
                    out.append(entry)
                }
            }
            return out
        }
    }

    private static func readEntry(stmt: OpaquePointer?) -> ECDictEntry? {
        guard let stmt else { return nil }

        func textCol(_ i: Int32) -> String? {
            if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
            guard let p = sqlite3_column_text(stmt, i) else { return nil }
            let s = String(cString: p)
            return s.isEmpty ? nil : s
        }
        func intCol(_ i: Int32) -> Int? {
            if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
            return Int(sqlite3_column_int(stmt, i))
        }

        guard let word = textCol(0) else { return nil }
        return ECDictEntry(
            word: word,
            phonetic: textCol(1),
            definition: textCol(2),
            translation: textCol(3),
            pos: textCol(4),
            collins: intCol(5),
            oxford: intCol(6),
            tag: textCol(7),
            bnc: intCol(8),
            frq: intCol(9),
            exchange: textCol(10),
            detail: textCol(11),
            audio: textCol(12)
        )
    }

    /// 把 ECDICT 词条格式化为人类可读字符串（参考系统词典风格）
    static func format(_ e: ECDictEntry) -> String {
        var out = ""
        if let p = e.phonetic, !p.isEmpty {
            out += "|\(p)|\n\n"
        }
        if let t = e.translation, !t.isEmpty {
            out += t.replacingOccurrences(of: "\\n", with: "\n") + "\n"
        }
        if let d = e.definition, !d.isEmpty {
            out += "\n【English】\n" + d.replacingOccurrences(of: "\\n", with: "\n") + "\n"
        }
        var meta: [String] = []
        if let tag = e.tag, !tag.isEmpty {
            meta.append("标签: " + tagLabel(tag))
        }
        if let frq = e.frq, frq > 0 {
            meta.append("词频: \(frq)")
        }
        if let collins = e.collins, collins > 0 {
            meta.append("柯林斯: " + String(repeating: "★", count: collins))
        }
        if let oxford = e.oxford, oxford == 1 {
            meta.append("牛津3000")
        }
        if !meta.isEmpty {
            out += "\n" + meta.joined(separator: "  ·  ") + "\n"
        }
        if let lemma = e.lemma, lemma != e.word.lowercased() {
            out += "\n原形: \(lemma)\n"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tagLabel(_ tag: String) -> String {
        let map: [String: String] = [
            "zk": "中考", "gk": "高考", "cet4": "CET-4", "cet6": "CET-6",
            "ky": "考研", "toefl": "TOEFL", "ielts": "IELTS", "gre": "GRE"
        ]
        return tag.split(separator: " ").map { map[String($0)] ?? String($0) }.joined(separator: "/")
    }

    // MARK: - 下载/导入

    enum InstallError: Error {
        case downloadFailed(String)
        case unzipFailed(String)
        case invalidArchive
    }

    /// 下载并解压词典。回调在主线程。
    func downloadDictionary(
        from url: URL = ECDictionary.defaultDownloadURL,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let delegate = DownloadDelegate(progress: progress) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            case .success(let tmpURL):
                do {
                    let extracted = try self.extractAndInstall(archive: tmpURL)
                    self.openIfPossible()
                    DispatchQueue.main.async { completion(.success(extracted)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        task.resume()
    }

    /// 从用户选择的本地文件导入（支持 .db / .zip）
    func importDictionary(from fileURL: URL) throws {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "db" || ext == "sqlite" || ext == "sqlite3" {
            try installDB(from: fileURL)
        } else if ext == "zip" {
            _ = try extractAndInstall(archive: fileURL)
        } else {
            throw InstallError.invalidArchive
        }
        openIfPossible()
    }

    private func installDB(from src: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dbURL.path) {
            try fm.removeItem(at: dbURL)
        }
        try fm.copyItem(at: src, to: dbURL)
    }

    /// 解压 zip，找到第一个 .db 文件复制为 ecdict.db
    private func extractAndInstall(archive: URL) throws -> URL {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("QuickDict_unzip_\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        // 用系统 unzip 命令（macOS 自带）
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", archive.path, "-d", workDir.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw InstallError.unzipFailed(msg)
        }

        // 在 workDir 下递归找 .db 文件
        guard let dbFile = findFirstDB(in: workDir) else {
            throw InstallError.invalidArchive
        }
        try installDB(from: dbFile)
        return dbURL
    }

    private func findFirstDB(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if ext == "db" || ext == "sqlite" || ext == "sqlite3" {
                return url
            }
        }
        return nil
    }
}

/// URLSession 下载代理，跟踪进度。
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progress: (Double) -> Void
    let completion: (Result<URL, Error>) -> Void

    init(progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        self.progress = progress
        self.completion = completion
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.progress(p) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 立即移到一个稳定的临时位置（系统会在闭包返回后清理 location）
        let stable = FileManager.default.temporaryDirectory.appendingPathComponent("QuickDict_dl_\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: stable)
            completion(.success(stable))
        } catch {
            completion(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completion(.failure(error))
        }
        session.finishTasksAndInvalidate()
    }
}
