import Cocoa

/// 共享的 attributed-string 构造工具：section 头、引用块、目标词高亮等
enum SectionUtil {

    static let headerAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
        .foregroundColor: NSColor.labelColor
    ]

    /// 构造一个完整 section（标题 + 内容 + 底部空行）
    static func section(header: String, body: NSAttributedString, topGap: Bool = true) -> NSAttributedString {
        let m = NSMutableAttributedString()
        if topGap {
            m.append(NSAttributedString(string: "\n",
                                        attributes: [.font: NSFont.systemFont(ofSize: 6)]))
        }
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 6
        var hdrAttrs = headerAttrs
        hdrAttrs[.paragraphStyle] = para
        m.append(NSAttributedString(string: header + "\n", attributes: hdrAttrs))
        m.append(body)
        m.append(NSAttributedString(string: "\n",
                                    attributes: [.font: NSFont.systemFont(ofSize: 8)]))
        return m
    }

    /// 灰色提示行
    static func faintLine(_ text: String) -> NSAttributedString {
        return NSAttributedString(string: text + "\n",
                                  attributes: [.font: NSFont.systemFont(ofSize: 12),
                                               .foregroundColor: NSColor.tertiaryLabelColor])
    }

    /// 引用块（缩进左边框风格）
    static func quote(_ text: String, footer: String, link: URL? = nil) -> NSAttributedString {
        let m = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 14
        para.headIndent = 14
        para.paragraphSpacingBefore = 4
        m.append(NSAttributedString(string: text + "\n",
                                    attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                 .foregroundColor: NSColor.labelColor,
                                                 .paragraphStyle: para]))
        var fAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: para
        ]
        if let link {
            fAttrs[.link] = link
            fAttrs[.foregroundColor] = NSColor.linkColor
        }
        m.append(NSAttributedString(string: footer + "\n", attributes: fAttrs))
        return m
    }

    static func quoteAttr(_ attr: NSAttributedString, footer: String, link: URL?) -> NSAttributedString {
        let m = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 14
        para.headIndent = 14
        para.paragraphSpacingBefore = 4
        let body = NSMutableAttributedString(attributedString: attr)
        body.addAttribute(.paragraphStyle, value: para,
                          range: NSRange(location: 0, length: body.length))
        m.append(body)
        m.append(NSAttributedString(string: "\n"))
        var fAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: para
        ]
        if let link {
            fAttrs[.link] = link
            fAttrs[.foregroundColor] = NSColor.linkColor
        }
        m.append(NSAttributedString(string: footer + "\n", attributes: fAttrs))
        return m
    }

    /// 把例句中的目标词加粗高亮
    static func highlight(_ text: String, word: String) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        let m = NSMutableAttributedString(string: text, attributes: base)
        let lower = (text as NSString).lowercased as NSString
        let key = word.lowercased()
        let total = lower.length
        var range = NSRange(location: 0, length: total)
        while range.length > 0 {
            let r = lower.range(of: key, options: [], range: range)
            if r.location == NSNotFound { break }
            m.addAttributes([
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.systemOrange
            ], range: r)
            let next = r.location + r.length
            range = NSRange(location: next, length: max(0, total - next))
        }
        return m
    }

    /// 从释义文本里提取音标 |xxx|
    static func extractPhonetic(from text: String) -> String? {
        guard let r = text.range(of: #"\|[^|]{1,80}\|"#, options: .regularExpression) else { return nil }
        return String(text[r])
    }

    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
    }
}

/// NSTextView 子类：支持把右上角某个矩形从 textContainer 排除（让文字自动绕开图片区）
final class ImageHostTextView: NSTextView {
    /// 设为非零后，会在右上角排除一个对应大小的区域
    var exclusionImageSize: CGSize = .zero {
        didSet { updateExclusion() }
    }
    /// 图片右侧/上方距离 textView 边界的内边距（用于和右上角图片视图位置对齐）
    var exclusionPadding: NSEdgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 12, right: 0) {
        didSet { updateExclusion() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateExclusion()
    }

    private func updateExclusion() {
        guard exclusionImageSize.width > 0, exclusionImageSize.height > 0 else {
            textContainer?.exclusionPaths = []
            return
        }
        let w = bounds.width
        // 减去文本容器的 inset 和 lineFragmentPadding
        let inset = textContainerInset
        let frag = textContainer?.lineFragmentPadding ?? 0
        let usableWidth = max(0, w - inset.width * 2 - frag * 2)
        guard usableWidth > exclusionImageSize.width + 40 else {
            // 太窄时不排除（避免文字被压成一列）
            textContainer?.exclusionPaths = []
            return
        }
        let rect = NSRect(
            x: usableWidth - exclusionImageSize.width - exclusionPadding.left,
            y: 0,
            width: exclusionImageSize.width + exclusionPadding.left,
            height: exclusionImageSize.height + exclusionPadding.bottom
        )
        textContainer?.exclusionPaths = [NSBezierPath(rect: rect)]
    }
}
