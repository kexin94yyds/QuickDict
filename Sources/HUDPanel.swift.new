import Cocoa

class HUDPanel: NSPanel {
    private let word: String
    private let definition: String
    private let source: String?

    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var autoCloseWorkItem: DispatchWorkItem?
    private var favoriteButton: NSButton?
    private var headerImageView: NSImageView!

    private var contentScroll: NSScrollView!
    private var contentStack: NSStackView!

    init(word: String, definition: String, source: String? = nil) {
        self.word = word
        self.definition = definition
        self.source = source

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let panelWidth: CGFloat = 520
        let panelHeight: CGFloat = 520

        let mouseLocation = NSEvent.mouseLocation
        let offset: CGFloat = 25
        var panelX = mouseLocation.x - panelWidth / 2
        var panelY = mouseLocation.y - panelHeight - offset

        if panelY < screenFrame.minY {
            panelY = mouseLocation.y + offset
        }
        if panelX < screenFrame.minX {
            panelX = screenFrame.minX + 10
        } else if panelX + panelWidth > screenFrame.maxX {
            panelX = screenFrame.maxX - panelWidth - 10
        }
        if panelY + panelHeight > screenFrame.maxY {
            panelY = screenFrame.maxY - panelHeight - 10
        }

        super.init(
            contentRect: NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.hidesOnDeactivate = false

        setupContent()
        setupAutoClose()
        loadEnrichmentsAsync()
    }

    private func setupContent() {
        let visualEffect = NSVisualEffectView(frame: self.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        let closeButton = NSButton(title: "×", target: self, action: #selector(closePanel))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 18, weight: .light)

        let favBtn = NSButton(title: "☆ 收藏", target: self, action: #selector(addToFavorites))
        favBtn.translatesAutoresizingMaskIntoConstraints = false
        favBtn.bezelStyle = .inline
        favBtn.font = NSFont.systemFont(ofSize: 11)
        favoriteButton = favBtn

        let sourceLabel = NSTextField(labelWithString: source.map { "来源：\($0)" } ?? "")
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.font = NSFont.systemFont(ofSize: 10)
        sourceLabel.textColor = .tertiaryLabelColor

        // Wikipedia 图（异步加载，先隐藏）
        headerImageView = NSImageView()
        headerImageView.translatesAutoresizingMaskIntoConstraints = false
        headerImageView.imageScaling = .scaleProportionallyUpOrDown
        headerImageView.wantsLayer = true
        headerImageView.layer?.cornerRadius = 6
        headerImageView.layer?.masksToBounds = true
        headerImageView.layer?.borderWidth = 1
        headerImageView.layer?.borderColor = NSColor.separatorColor.cgColor
        headerImageView.isHidden = true

        contentScroll = NSScrollView()
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.hasVerticalScroller = true
        contentScroll.borderType = .noBorder
        contentScroll.drawsBackground = false
        contentScroll.autohidesScrollers = true

        let docView = HUDFlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false

        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .fill
        contentStack.spacing = 12
        contentStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        docView.addSubview(contentStack)
        contentScroll.documentView = docView

        visualEffect.addSubview(contentScroll)
        visualEffect.addSubview(closeButton)
        visualEffect.addSubview(favBtn)
        visualEffect.addSubview(sourceLabel)
        visualEffect.addSubview(headerImageView)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            headerImageView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 12),
            headerImageView.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            headerImageView.widthAnchor.constraint(equalToConstant: 64),
            headerImageView.heightAnchor.constraint(equalToConstant: 64),

            contentScroll.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 8),
            contentScroll.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 4),
            contentScroll.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -4),
            contentScroll.bottomAnchor.constraint(equalTo: favBtn.topAnchor, constant: -8),

            docView.topAnchor.constraint(equalTo: contentScroll.contentView.topAnchor),
            docView.leadingAnchor.constraint(equalTo: contentScroll.contentView.leadingAnchor),
            docView.trailingAnchor.constraint(equalTo: contentScroll.contentView.trailingAnchor),
            docView.widthAnchor.constraint(equalTo: contentScroll.contentView.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: docView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor),

            favBtn.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 12),
            favBtn.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -10),

            sourceLabel.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -12),
            sourceLabel.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -10)
        ])

        self.contentView = visualEffect

        // 立即填入释义和你自己的语境（同步）
        appendDefinitionSection()
        appendOwnContextsSection()
        // 占位 Wikipedia / HN section（异步填）
        wikiSection = appendLoadingSection(title: "🌐 Wikipedia")
        hnSection = appendLoadingSection(title: "🟧 Hacker News 真实例句")
    }

    // MARK: - sections

    private var wikiSection: NSView!
    private var hnSection: NSView!

    private func appendDefinitionSection() {
        let attr = DefinitionFormatter.attributedString(
            word: word, definition: definition, includeTitle: true,
            titleSize: 22, bodySize: 13)
        appendSection(title: nil, attributedBody: attr)
    }

    private func appendOwnContextsSection() {
        let mine = EnrichService.shared.ownContexts(for: word, excludingID: nil, limit: 5)
        guard !mine.isEmpty else { return }
        let body = NSMutableAttributedString()
        for c in mine {
            body.append(quoteLine(c.sentence, footer: "你于 \(shortDate(c.savedAt)) 收藏过"))
            body.append(NSAttributedString(string: "\n"))
        }
        appendSection(title: "🪞 你自己的语境（\(mine.count)）", attributedBody: body)
    }

    private func loadEnrichmentsAsync() {
        EnrichService.shared.fetchWikipedia(word: word) { [weak self] extract, pageURL, imgPath in
            guard let self else { return }
            if let imgPath, let img = NSImage(contentsOfFile: imgPath) {
                self.headerImageView.image = img
                self.headerImageView.isHidden = false
            }
            if let extract, !extract.isEmpty {
                let body = NSMutableAttributedString()
                body.append(NSAttributedString(string: extract,
                                               attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                            .foregroundColor: NSColor.labelColor]))
                if let pageURL {
                    body.append(NSAttributedString(string: "\n\n"))
                    body.append(NSAttributedString(string: "→ \(pageURL.absoluteString)",
                                                   attributes: [.link: pageURL,
                                                                .font: NSFont.systemFont(ofSize: 11),
                                                                .foregroundColor: NSColor.linkColor]))
                }
                self.replaceSection(self.wikiSection, with: body)
            } else {
                self.replaceSection(self.wikiSection,
                                    with: NSAttributedString(string: "（无 Wikipedia 条目）",
                                                             attributes: self.faintAttrs))
            }
        }

        EnrichService.shared.fetchHackerNews(word: word) { [weak self] examples in
            guard let self else { return }
            if examples.isEmpty {
                self.replaceSection(self.hnSection,
                                    with: NSAttributedString(string: "（HN 暂未搜到合适例句）",
                                                             attributes: self.faintAttrs))
                return
            }
            let body = NSMutableAttributedString()
            for ex in examples {
                let snippet = self.highlight(ex.snippet, word: self.word)
                body.append(self.quoteLineAttr(snippet, footer: "@\(ex.author) · \(ex.storyTitle)", link: ex.url))
                body.append(NSAttributedString(string: "\n"))
            }
            self.replaceSection(self.hnSection, with: body)
        }
    }

    // MARK: - section helpers (与 ReviewPanel 同构)

    private var faintAttrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 12),
         .foregroundColor: NSColor.tertiaryLabelColor]
    }

    @discardableResult
    private func appendSection(title: String?, attributedBody: NSAttributedString) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let bodyView = NSTextView()
        bodyView.isEditable = false
        bodyView.isSelectable = true
        bodyView.backgroundColor = .clear
        bodyView.drawsBackground = false
        bodyView.textContainerInset = NSSize(width: 0, height: 4)
        bodyView.textContainer?.lineFragmentPadding = 0
        bodyView.textContainer?.widthTracksTextView = true
        bodyView.isVerticallyResizable = true
        bodyView.isHorizontallyResizable = false
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        bodyView.textStorage?.setAttributedString(attributedBody)

        if let title {
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            titleLabel.textColor = .secondaryLabelColor
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(titleLabel)
            container.addSubview(bodyView)
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
                titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bodyView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
                bodyView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bodyView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bodyView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else {
            container.addSubview(bodyView)
            NSLayoutConstraint.activate([
                bodyView.topAnchor.constraint(equalTo: container.topAnchor),
                bodyView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bodyView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bodyView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        contentStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: contentStack.widthAnchor,
                                         constant: -(contentStack.edgeInsets.left + contentStack.edgeInsets.right)).isActive = true
        return container
    }

    private func appendLoadingSection(title: String) -> NSView {
        return appendSection(title: title,
                             attributedBody: NSAttributedString(string: "加载中…", attributes: faintAttrs))
    }

    private func replaceSection(_ container: NSView, with attributed: NSAttributedString) {
        if let body = container.subviews.compactMap({ $0 as? NSTextView }).first {
            body.textStorage?.setAttributedString(attributed)
        }
    }

    private func quoteLine(_ text: String, footer: String, link: URL? = nil) -> NSAttributedString {
        let m = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 12
        para.headIndent = 12
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

    private func quoteLineAttr(_ attr: NSAttributedString, footer: String, link: URL?) -> NSAttributedString {
        let m = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 12
        para.headIndent = 12
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

    private func highlight(_ text: String, word: String) -> NSAttributedString {
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

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
    }

    // MARK: - close / favorite

    private func setupAutoClose() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.closePanel()
                return nil
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    @objc private func closePanel() {
        autoCloseWorkItem?.cancel()
        autoCloseWorkItem = nil
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        self.orderOut(nil)
    }

    @objc private func addToFavorites() {
        let sentence = definition.split(separator: "\n").first.map(String.init) ?? definition
        _ = WordBook.shared.addFavorite(word: word, sentence: String(sentence.prefix(120)))
        favoriteButton?.title = "★ 已收藏"
        favoriteButton?.isEnabled = false
    }

    deinit {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
    }

    func show() {
        self.makeKeyAndOrderFront(nil)
        let workItem = DispatchWorkItem { [weak self] in
            self?.closePanel()
        }
        autoCloseWorkItem = workItem
        // 异步内容可能要 8s+，把自动关闭从 15s 延长到 30s
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
    }
}

private class HUDFlippedView: NSView {
    override var isFlipped: Bool { true }
}
