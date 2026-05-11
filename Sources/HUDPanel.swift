import Cocoa

class HUDPanel: NSPanel {
    private let word: String
    private let definition: String
    private let source: String?
    private let context: String?
    private let displayWord: String
    private let imageWords: [String]

    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var autoCloseWorkItem: DispatchWorkItem?
    private var favoriteButton: NSButton?
    private var headerImageView: NSImageView!

    private var contentTextView: ImageHostTextView!

    private var defSection = NSAttributedString()
    private var ownSection = NSAttributedString()
    private var wikiSection = NSAttributedString()
    private var hnSection = NSAttributedString()

    init(
        word: String,
        definition: String,
        source: String? = nil,
        context: String? = nil,
        displayWord: String? = nil,
        imageWords: [String] = []
    ) {
        self.word = word
        self.definition = definition
        self.source = source
        self.context = context
        self.displayWord = displayWord ?? word
        self.imageWords = imageWords

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let panelWidth: CGFloat = 540
        let panelHeight: CGFloat = 540

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

        // 初始填入释义 + 你的语境，触发首次渲染
        defSection = SectionUtil.section(
            header: "📖 释义" + (source.map { "  ·  \($0)" } ?? ""),
            body: DefinitionFormatter.attributedString(
                word: self.displayWord, definition: definition, includeTitle: true,
                titleSize: 22, bodySize: 13),
            topGap: false)

        let mine = EnrichService.shared.ownContexts(for: word, excludingID: nil, limit: 5)
        if !mine.isEmpty {
            let body = NSMutableAttributedString()
            for c in mine {
                body.append(SectionUtil.quote(c.sentence, footer: "你于 \(SectionUtil.shortDate(c.savedAt)) 收藏过"))
                body.append(NSAttributedString(string: "\n"))
            }
            ownSection = SectionUtil.section(header: "🪞 你自己的语境（\(mine.count)）", body: body)
        }

        // 占位
        wikiSection = SectionUtil.section(header: "🌐 Wikipedia", body: SectionUtil.faintLine("加载中…"))
        hnSection = SectionUtil.section(header: "🟧 Hacker Ne ws 真实例句", body: SectionUtil.faintLine("加载中…"))

        renderAll()
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

        headerImageView = NSImageView()
        headerImageView.translatesAutoresizingMaskIntoConstraints = false
        headerImageView.imageScaling = .scaleProportionallyUpOrDown
        headerImageView.wantsLayer = true
        headerImageView.layer?.cornerRadius = 6
        headerImageView.layer?.masksToBounds = true
        headerImageView.layer?.borderWidth = 1
        headerImageView.layer?.borderColor = NSColor.separatorColor.cgColor
        headerImageView.isHidden = true

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        contentTextView = ImageHostTextView()
        contentTextView.isEditable = false
        contentTextView.isSelectable = true
        contentTextView.backgroundColor = .clear
        contentTextView.drawsBackground = false
        contentTextView.textContainerInset = NSSize(width: 14, height: 12)
        contentTextView.textContainer?.lineFragmentPadding = 0
        contentTextView.isVerticallyResizable = true
        contentTextView.isHorizontallyResizable = false
        contentTextView.autoresizingMask = [.width]
        contentTextView.textContainer?.widthTracksTextView = true
        contentTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                         height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = contentTextView

        visualEffect.addSubview(scrollView)
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
            headerImageView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -12),
            headerImageView.widthAnchor.constraint(equalToConstant: 200),
            headerImageView.heightAnchor.constraint(equalToConstant: 200),

            scrollView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: favBtn.topAnchor, constant: -8),

            favBtn.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 12),
            favBtn.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -10),

            sourceLabel.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -12),
            sourceLabel.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -10)
        ])

        self.contentView = visualEffect
        updateFavoriteButtonState()
    }

    private func favoriteSentence() -> String {
        let base: String
        if let ctx = context, !ctx.isEmpty {
            base = ctx
        } else {
            base = definition.split(separator: "\n").first.map(String.init) ?? definition
        }
        return String(base.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
    }

    private func updateFavoriteButtonState() {
        guard let button = favoriteButton else { return }
        if WordBook.shared.hasFavorite(word: word, sentence: favoriteSentence()) {
            button.title = "★ 已收藏"
            button.isEnabled = false
        } else {
            button.title = "☆ 收藏"
            button.isEnabled = true
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

    private func loadEnrichmentsAsync() {
        EnrichService.shared.fetchWikipedia(word: word, imageFallbackWords: imageWords) { [weak self] extract, pageURL, imgPath in
            guard let self else { return }
            if let imgPath, let img = NSImage(contentsOfFile: imgPath) {
                self.headerImageView.image = img
                self.headerImageView.isHidden = false
                self.contentTextView.exclusionImageSize = NSSize(width: 200, height: 200)
                self.renderAll()
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

        EnrichService.shared.fetchHackerNews(word: word) { [weak self] examples in
            guard let self else { return }
            if examples.isEmpty {
                self.hnSection = SectionUtil.section(header: "🟧 Hacker News 真实例句",
                                                     body: SectionUtil.faintLine("（HN 暂未搜到合适例句）"))
            } else {
                let body = NSMutableAttributedString()
                for ex in examples {
                    let snippet = SectionUtil.highlight(ex.snippet, word: self.word)
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

    private func setupAutoClose() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.command),
               !modifiers.contains(.shift),
               !modifiers.contains(.option),
               !modifiers.contains(.control),
               event.charactersIgnoringModifiers?.lowercased() == "b" {
                self?.addToFavorites()
                return nil
            }
            if event.keyCode == 53 {
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
        _ = WordBook.shared.addFavorite(word: word, sentence: favoriteSentence())
        updateFavoriteButtonState()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
    }
}
