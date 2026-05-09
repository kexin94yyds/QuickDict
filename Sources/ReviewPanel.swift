import Cocoa

/// 复习卡片：单一 NSTextView 渲染多区域内容（释义 / 你的语境 / Wikipedia / HN）
final class ReviewPanel: NSPanel {
    private var queue: [FavoriteEntry]
    private var index: Int = 0

    private var headerImageView: NSImageView!
    private var wordLabel: NSTextField!
    private var phoneticLabel: NSTextField!
    private var sentenceLabel: NSTextField!
    private var revealButton: NSButton!

    private var contentScroll: NSScrollView!
    private var contentTextView: NSTextView!

    private var ratingStack: NSStackView!
    private var progressLabel: NSTextField!

    private var defRevealed = false

    // 各区域的当前内容（异步会更新）
    private var defSection = NSAttributedString()
    private var ownSection = NSAttributedString()
    private var wikiSection = NSAttributedString()
    private var hnSection = NSAttributedString()

    init(entries: [FavoriteEntry]) {
        self.queue = entries
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let w: CGFloat = 700
        let h: CGFloat = 640
        let x = (screenFrame.width - w) / 2
        let y = (screenFrame.height - h) / 2

        super.init(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.title = "复习"
        self.level = .floating
        self.isReleasedWhenClosed = false
        self.minSize = NSSize(width: 580, height: 500)

        setupUI()
        loadCurrent()
    }

    private func setupUI() {
        let container = NSView(frame: contentView!.bounds)
        container.autoresizingMask = [.width, .height]

        progressLabel = NSTextField(labelWithString: "")
        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        headerImageView = NSImageView()
        headerImageView.translatesAutoresizingMaskIntoConstraints = false
        headerImageView.imageScaling = .scaleProportionallyUpOrDown
        headerImageView.wantsLayer = true
        headerImageView.layer?.cornerRadius = 8
        headerImageView.layer?.masksToBounds = true
        headerImageView.layer?.borderWidth = 1
        headerImageView.layer?.borderColor = NSColor.separatorColor.cgColor
        headerImageView.isHidden = true

        wordLabel = NSTextField(labelWithString: "")
        wordLabel.font = .systemFont(ofSize: 32, weight: .bold)
        wordLabel.translatesAutoresizingMaskIntoConstraints = false

        phoneticLabel = NSTextField(labelWithString: "")
        phoneticLabel.font = .systemFont(ofSize: 12)
        phoneticLabel.textColor = .secondaryLabelColor
        phoneticLabel.translatesAutoresizingMaskIntoConstraints = false

        sentenceLabel = NSTextField(wrappingLabelWithString: "")
        sentenceLabel.font = .systemFont(ofSize: 14, weight: .medium)
        sentenceLabel.maximumNumberOfLines = 4
        sentenceLabel.textColor = .labelColor
        sentenceLabel.translatesAutoresizingMaskIntoConstraints = false
        sentenceLabel.drawsBackground = true
        sentenceLabel.backgroundColor = NSColor.controlBackgroundColor
        sentenceLabel.isEditable = false
        sentenceLabel.isBordered = false

        revealButton = NSButton(title: "显示释义和扩展（空格）", target: self, action: #selector(revealDefinition))
        revealButton.bezelStyle = .rounded
        revealButton.translatesAutoresizingMaskIntoConstraints = false
        revealButton.controlSize = .large

        // 单一 NSTextView 渲染全部内容
        contentScroll = NSScrollView()
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.hasVerticalScroller = true
        contentScroll.borderType = .bezelBorder
        contentScroll.drawsBackground = false
        contentScroll.isHidden = true
        contentScroll.autohidesScrollers = false

        contentTextView = NSTextView()
        contentTextView.isEditable = false
        contentTextView.isSelectable = true
        contentTextView.backgroundColor = .clear
        contentTextView.drawsBackground = false
        contentTextView.textContainerInset = NSSize(width: 12, height: 12)
        contentTextView.textContainer?.lineFragmentPadding = 0
        contentTextView.isVerticallyResizable = true
        contentTextView.isHorizontallyResizable = false
        contentTextView.autoresizingMask = [.width]
        contentTextView.textContainer?.widthTracksTextView = true
        contentTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                         height: CGFloat.greatestFiniteMagnitude)
        contentScroll.documentView = contentTextView

        // 4 档评分
        ratingStack = NSStackView()
        ratingStack.orientation = .horizontal
        ratingStack.distribution = .fillEqually
        ratingStack.spacing = 8
        ratingStack.translatesAutoresizingMaskIntoConstraints = false
        ratingStack.isHidden = true

        for (title, q, color) in [
            ("忘记 (1)", RecallQuality.forgot, NSColor.systemRed),
            ("模糊 (2)", RecallQuality.hard,   NSColor.systemOrange),
            ("记得 (3)", RecallQuality.good,   NSColor.systemBlue),
            ("简单 (4)", RecallQuality.easy,   NSColor.systemGreen)
        ] {
            let btn = NSButton(title: title, target: self, action: #selector(rateButtonTapped(_:)))
            btn.bezelStyle = .rounded
            btn.tag = q.rawValue
            btn.contentTintColor = color
            ratingStack.addArrangedSubview(btn)
        }

        container.addSubview(progressLabel)
        container.addSubview(headerImageView)
        container.addSubview(wordLabel)
        container.addSubview(phoneticLabel)
        container.addSubview(sentenceLabel)
        container.addSubview(revealButton)
        container.addSubview(contentScroll)
        container.addSubview(ratingStack)

        NSLayoutConstraint.activate([
            progressLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            progressLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            headerImageView.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 8),
            headerImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            headerImageView.widthAnchor.constraint(equalToConstant: 180),
            headerImageView.heightAnchor.constraint(equalToConstant: 180),

            wordLabel.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 12),
            wordLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            wordLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerImageView.leadingAnchor, constant: -12),

            phoneticLabel.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 2),
            phoneticLabel.leadingAnchor.constraint(equalTo: wordLabel.leadingAnchor),
            phoneticLabel.trailingAnchor.constraint(equalTo: wordLabel.trailingAnchor),

            sentenceLabel.topAnchor.constraint(equalTo: phoneticLabel.bottomAnchor, constant: 12),
            sentenceLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            sentenceLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            revealButton.topAnchor.constraint(equalTo: sentenceLabel.bottomAnchor, constant: 14),
            revealButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            contentScroll.topAnchor.constraint(equalTo: revealButton.bottomAnchor, constant: 12),
            contentScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            contentScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            contentScroll.bottomAnchor.constraint(equalTo: ratingStack.topAnchor, constant: -14),

            ratingStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            ratingStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            ratingStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            ratingStack.heightAnchor.constraint(equalToConstant: 36)
        ])

        contentView = container
    }

    // MARK: - 状态

    private func loadCurrent() {
        if index >= queue.count { finish(); return }
        let entry = queue[index]
        progressLabel.stringValue = "进度 \(index + 1) / \(queue.count)"
        wordLabel.stringValue = entry.word
        phoneticLabel.stringValue = ""
        sentenceLabel.stringValue = entry.sentence
        defRevealed = false
        contentScroll.isHidden = true
        ratingStack.isHidden = true
        revealButton.isHidden = false
        headerImageView.isHidden = true
        headerImageView.image = nil
        defSection = NSAttributedString()
        ownSection = NSAttributedString()
        wikiSection = NSAttributedString()
        hnSection = NSAttributedString()
        renderAll()
    }

    @objc private func revealDefinition() {
        guard index < queue.count else { return }
        let entry = queue[index]

        defRevealed = true
        contentScroll.isHidden = false
        ratingStack.isHidden = false
        revealButton.isHidden = true

        // 释义（同步）
        let result = DictService.shared.lookup(entry.word)
        let definition = result?.definition ?? "（未找到释义）"
        if let phonetic = SectionUtil.extractPhonetic(from: definition) {
            phoneticLabel.stringValue = phonetic
        }
        let sourceTag = result.map { "  ·  \($0.source.rawValue)" } ?? ""
        defSection = SectionUtil.section(
            header: "📖 释义" + sourceTag,
            body: DefinitionFormatter.attributedString(
                word: entry.word, definition: definition,
                includeTitle: false, bodySize: 13))

        // 你自己的语境（同步）
        let mine = EnrichService.shared.ownContexts(for: entry.word, excludingID: entry.id, limit: 5)
        if !mine.isEmpty {
            let body = NSMutableAttributedString()
            for c in mine {
                body.append(SectionUtil.quote(c.sentence, footer: "你于 \(SectionUtil.shortDate(c.savedAt)) 收藏过"))
                body.append(NSAttributedString(string: "\n"))
            }
            ownSection = SectionUtil.section(header: "🪞 你自己的语境（\(mine.count)）", body: body)
        }

        // 占位
        wikiSection = SectionUtil.section(header: "🌐 Wikipedia",
                                          body: SectionUtil.faintLine("加载中…"))
        hnSection = SectionUtil.section(header: "🟧 Hacker News 真实例句",
                                        body: SectionUtil.faintLine("加载中…"))

        renderAll()

        // 异步 Wikipedia
        EnrichService.shared.fetchWikipedia(word: entry.word) { [weak self] extract, pageURL, imgPath in
            guard let self else { return }
            // 处于此卡片才更新
            guard self.index < self.queue.count, self.queue[self.index].id == entry.id else { return }
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
                self.wikiSection = SectionUtil.section(header: "🌐 Wikipedia", body: body)
            } else {
                self.wikiSection = SectionUtil.section(header: "🌐 Wikipedia",
                                                       body: SectionUtil.faintLine("（无 Wikipedia 条目）"))
            }
            self.renderAll()
        }

        // 异步 HN
        EnrichService.shared.fetchHackerNews(word: entry.word) { [weak self] examples in
            guard let self else { return }
            guard self.index < self.queue.count, self.queue[self.index].id == entry.id else { return }
            if examples.isEmpty {
                self.hnSection = SectionUtil.section(header: "🟧 Hacker News 真实例句",
                                                     body: SectionUtil.faintLine("（HN 上暂未搜到合适例句）"))
            } else {
                let body = NSMutableAttributedString()
                for ex in examples {
                    let snippet = SectionUtil.highlight(ex.snippet, word: entry.word)
                    body.append(SectionUtil.quoteAttr(snippet,
                                                      footer: "@\(ex.author) · \(ex.storyTitle)",
                                                      link: ex.url))
                    body.append(NSAttributedString(string: "\n"))
                }
                self.hnSection = SectionUtil.section(header: "🟧 Hacker News 真实例句", body: body)
            }
            self.renderAll()
        }
    }

    private func renderAll() {
        let m = NSMutableAttributedString()
        m.append(defSection)
        m.append(ownSection)
        m.append(wikiSection)
        m.append(hnSection)
        contentTextView.textStorage?.beginEditing()
        contentTextView.textStorage?.setAttributedString(m)
        contentTextView.textStorage?.endEditing()
    }

    @objc private func rateButtonTapped(_ sender: NSButton) {
        guard let q = RecallQuality(rawValue: sender.tag) else { return }
        applyRating(q)
    }

    private func applyRating(_ q: RecallQuality) {
        guard index < queue.count else { return }
        let entry = queue[index]
        let updated = ReviewScheduler.schedule(entry: entry, quality: q)
        ReviewScheduler.apply(updated)
        index += 1
        loadCurrent()
    }

    private func finish() {
        let alert = NSAlert()
        alert.messageText = "复习完成 🎉"
        alert.informativeText = "今天的复习已经全部完成，共 \(queue.count) 个单词。"
        alert.addButton(withTitle: "好")
        alert.runModal()
        self.close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            if !defRevealed { revealDefinition(); return }
        }
        if defRevealed {
            let mapping: [UInt16: RecallQuality] = [18: .forgot, 19: .hard, 20: .good, 21: .easy]
            if let q = mapping[event.keyCode] { applyRating(q); return }
        }
        super.keyDown(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
