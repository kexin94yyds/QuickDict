import Cocoa

/// 把字典原始释义格式化为有结构的 NSAttributedString
/// 用 Unicode 范围匹配以应对 Apple/ECDICT 不同来源的细微符号差异
enum DefinitionFormatter {

    static func attributedString(word: String, definition: String,
                                 includeTitle: Bool = true,
                                 titleSize: CGFloat = 22,
                                 bodySize: CGFloat = 13) -> NSAttributedString {
        // 首次调用打日志便于排查
        NSLog("DefinitionFormatter: word=\(word) defLen=\(definition.count) head=\(String(definition.prefix(80)))")

        let result = NSMutableAttributedString()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: titleSize),
            .foregroundColor: NSColor.labelColor
        ]
        let phoneticAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: bodySize - 1),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let posAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: bodySize + 1),
            .foregroundColor: NSColor.systemBlue
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: bodySize),
            .foregroundColor: NSColor.labelColor
        ]
        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: bodySize),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: bodySize),
            .foregroundColor: NSColor.systemOrange
        ]

        if includeTitle {
            result.append(NSAttributedString(string: word + "\n", attributes: titleAttrs))
        }

        var text = definition

        // 1) 提取音标（|xxx|）
        if let range = text.range(of: #"\|[^|]{1,80}\|"#, options: .regularExpression) {
            let phonetic = String(text[range])
            result.append(NSAttributedString(string: phonetic + "\n\n", attributes: phoneticAttrs))
            text.removeSubrange(range)
        }

        // 2) 把所有 "圆圈数字"（Unicode 0x2460-0x2473 / 0x24EB-0x24FF）替换成 \n\nN.
        text = replaceCircledDigits(in: text)

        // 3) 把所有"指向符号"（▸ ▶ ▹ ► ➤ • U+2022 等）替换成 \n    • 
        let bulletPattern = "[\u{2022}\u{2023}\u{25B8}\u{25B9}\u{25BA}\u{25BB}\u{25BC}\u{25BD}\u{25BE}\u{25BF}\u{2192}\u{27A4}\u{27A2}\u{2043}]"
        text = text.replacingOccurrences(of: bulletPattern, with: "\n    \u{2022} ", options: .regularExpression)

        // 4) 词性 keyword → 块级标题
        let posKeywords = [" noun ", " verb ", " adjective ", " adverb ",
                           " plural noun ", " transitive verb ", " intransitive verb "]
        for kw in posKeywords {
            let trimmed = kw.trimmingCharacters(in: .whitespaces)
            text = text.replacingOccurrences(of: kw, with: "\n\n【\(trimmed)】\n")
        }

        // 5) A. / B. / C. 区段头
        text = text.replacingOccurrences(of: #"(?<=[\s\n])([A-Z])\. (?=[a-zA-Z])"#,
                                         with: "\n\n— $1 ——\n",
                                         options: .regularExpression)

        // 6) 拆行渲染
        for rawLine in text.components(separatedBy: CharacterSet.newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }

            // 块级词性
            if line.hasPrefix("【") && line.hasSuffix("】") {
                result.append(NSAttributedString(string: "\n" + line + "\n", attributes: posAttrs))
                continue
            }

            // 区段头
            if line.hasPrefix("— ") && line.hasSuffix(" ——") {
                result.append(NSAttributedString(string: "\n" + line + "\n", attributes: posAttrs))
                continue
            }

            // 编号 1. 2. ...
            if let m = line.range(of: #"^\d+\.\s*"#, options: .regularExpression) {
                let numPart = String(line[m])
                let rest = String(line[m.upperBound...]).trimmingCharacters(in: .whitespaces)
                result.append(NSAttributedString(string: numPart, attributes: numAttrs))
                result.append(NSAttributedString(string: rest + "\n", attributes: bodyAttrs))
                continue
            }

            // bullet
            if line.hasPrefix("•") || line.hasPrefix("\u{2022}") {
                result.append(NSAttributedString(string: "  ", attributes: bulletAttrs))
                result.append(NSAttributedString(string: "• ", attributes: bulletAttrs))
                let rest = String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                result.append(NSAttributedString(string: rest + "\n", attributes: bodyAttrs))
                continue
            }

            // ECDICT 元数据
            if line.hasPrefix("标签:") || line.hasPrefix("词频:") || line.hasPrefix("柯林斯:") || line == "牛津3000" || line.hasPrefix("原形:") {
                result.append(NSAttributedString(string: line + "\n", attributes: bulletAttrs))
                continue
            }

            // 普通行
            result.append(NSAttributedString(string: line + "\n", attributes: bodyAttrs))
        }

        // 整段段落间距
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 4
        result.addAttribute(.paragraphStyle, value: paragraphStyle,
                            range: NSRange(location: 0, length: result.length))

        return result
    }

    // MARK: - 辅助

    /// 把 ① ② ③ ... 替换成 \n\n1. \n\n2. \n\n3. ...，覆盖完整 Unicode 圆圈数字
    private static func replaceCircledDigits(in text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v >= 0x2460, v <= 0x2473 {
                // ① = 0x2460  → 1
                let n = Int(v - 0x2460 + 1)
                out.append(contentsOf: "\n\n\(n). ".unicodeScalars)
            } else if v >= 0x2474, v <= 0x2487 {
                // (1) ~ (20) 0x2474..
                let n = Int(v - 0x2474 + 1)
                out.append(contentsOf: "\n\n\(n). ".unicodeScalars)
            } else if v >= 0x2488, v <= 0x249B {
                // 1. ~ 20. (Latin small numbers with full stop) — already a number, but rendered as glyph
                let n = Int(v - 0x2488 + 1)
                out.append(contentsOf: "\n\n\(n). ".unicodeScalars)
            } else if v >= 0x24EB, v <= 0x24FE {
                // 11~24 negative circled
                let n = Int(v - 0x24EB + 11)
                out.append(contentsOf: "\n\n\(n). ".unicodeScalars)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }
}
