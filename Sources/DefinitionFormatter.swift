import Cocoa

/// 把字典原始释义格式化为有结构的 NSAttributedString
/// 处理：音标 |xxx| / 圆圈数字 ①②③ / 三角▸ / 词性 noun/verb 等
enum DefinitionFormatter {

    static func attributedString(word: String, definition: String,
                                 titleSize: CGFloat = 22,
                                 bodySize: CGFloat = 13) -> NSAttributedString {
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
            .font: NSFont.boldSystemFont(ofSize: bodySize),
            .foregroundColor: NSColor.systemBlue
        ]
        let defAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: bodySize),
            .foregroundColor: NSColor.labelColor
        ]
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: bodySize),
            .foregroundColor: NSColor.labelColor
        ]
        let chineseAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: bodySize),
            .foregroundColor: NSColor.labelColor
        ]
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: bodySize - 2),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        // 标题（单词）
        result.append(NSAttributedString(string: word + "\n", attributes: titleAttrs))

        var text = definition

        // 提取音标（|xxx|）
        if let range = text.range(of: #"\|[^|]+\|"#, options: .regularExpression) {
            let phonetic = String(text[range])
            result.append(NSAttributedString(string: phonetic + "\n\n", attributes: phoneticAttrs))
            text = text.replacingCharacters(in: range, with: "")
        }

        // 圆圈数字 ① → \n\n1.
        let circleNums: [(String, String)] = [
            ("①", "\n\n1. "), ("②", "\n\n2. "), ("③", "\n\n3. "), ("④", "\n\n4. "), ("⑤", "\n\n5. "),
            ("⑥", "\n\n6. "), ("⑦", "\n\n7. "), ("⑧", "\n\n8. "), ("⑨", "\n\n9. "), ("⑩", "\n\n10. ")
        ]
        for (circle, num) in circleNums {
            text = text.replacingOccurrences(of: circle, with: num)
        }

        // 三角符号 ▸ / • → 缩进的 bullet
        text = text.replacingOccurrences(of: "▸", with: "\n    • ")
        text = text.replacingOccurrences(of: "•", with: "\n    • ")

        // 词性 keyword → 块级标题
        let posKeywords = [" noun ", " verb ", " adjective ", " adverb ",
                           "A. noun", "A. verb", "A. adjective", "B. noun", "B. verb", "B. adjective",
                           "B. plural noun", "C. noun", "C. verb", "C. adjective"]
        for kw in posKeywords {
            text = text.replacingOccurrences(of: kw, with: "\n\n【\(kw.trimmingCharacters(in: .whitespaces))】\n")
        }

        // 区段头 (A. / B. / C.)
        text = text.replacingOccurrences(of: #"(?<=\n)([A-Z])\. "#, with: "\n— $1. ", options: .regularExpression)

        // 拆行渲染
        for rawLine in text.components(separatedBy: CharacterSet.newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // 词性块
            if line.hasPrefix("【") && line.hasSuffix("】") {
                result.append(NSAttributedString(string: "\n" + line + "\n", attributes: posAttrs))
                continue
            }

            // 编号 1. 2. ...
            if let match = line.range(of: #"^\d+\.\s*"#, options: .regularExpression) {
                let numPart = String(line[match])
                let rest = String(line[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                result.append(NSAttributedString(string: numPart, attributes: numAttrs))
                if containsChinese(rest) {
                    result.append(NSAttributedString(string: rest + "\n", attributes: chineseAttrs))
                } else {
                    result.append(NSAttributedString(string: rest + "\n", attributes: defAttrs))
                }
                continue
            }

            // bullet
            if line.hasPrefix("•") {
                result.append(NSAttributedString(string: "  ", attributes: defAttrs))
                result.append(NSAttributedString(string: "• ", attributes: numAttrs))
                let rest = String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                let attrs = containsChinese(rest) ? chineseAttrs : defAttrs
                result.append(NSAttributedString(string: rest + "\n", attributes: attrs))
                continue
            }

            // ECDICT 元数据：标签/词频/柯林斯/牛津3000
            if line.hasPrefix("标签:") || line.hasPrefix("词频:") || line.hasPrefix("柯林斯:") || line == "牛津3000" || line.contains("·") && (line.contains("CET") || line.contains("TOEFL") || line.contains("IELTS") || line.contains("GRE") || line.contains("考研") || line.contains("中考") || line.contains("高考")) {
                result.append(NSAttributedString(string: line + "\n", attributes: metaAttrs))
                continue
            }

            if line.hasPrefix("原形:") {
                result.append(NSAttributedString(string: line + "\n", attributes: metaAttrs))
                continue
            }

            // 区段头
            if line.hasPrefix("— ") {
                result.append(NSAttributedString(string: "\n" + line + "\n", attributes: posAttrs))
                continue
            }

            // 普通行
            let attrs = containsChinese(line) ? chineseAttrs : defAttrs
            result.append(NSAttributedString(string: line + "\n", attributes: attrs))
        }

        // 段落间距
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 4
        result.addAttribute(.paragraphStyle, value: paragraphStyle,
                            range: NSRange(location: 0, length: result.length))

        return result
    }

    private static func containsChinese(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) {
                return true
            }
        }
        return false
    }
}
