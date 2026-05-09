import Cocoa

/// 复习卡片：4 档评分（忘记/模糊/记得/简单）
final class ReviewPanel: NSPanel {
    private var queue: [FavoriteEntry]
    private var index: Int = 0

    private var wordLabel: NSTextField!
    private var sentenceLabel: NSTextField!
    private var definitionScroll: NSScrollView!
    private var definitionView: NSTextView!
    private var revealButton: NSButton!
    private var ratingStack: NSStackView!
    private var progressLabel: NSTextField!
    private var defRevealed = false

    init(entries: [FavoriteEntry]) {
        self.queue = entries
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let w: CGFloat = 560
        let h: CGFloat = 460
        let x = (screenFrame.width - w) / 2
        let y = (screenFrame.height - h) / 2

        super.init(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.title = "复习"
        self.level = .floating
        self.isReleasedWhenClosed = false

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

        wordLabel = NSTextField(labelWithString: "")
        wordLabel.font = .boldSystemFont(ofSize: 32)
        wordLabel.alignment = .center
        wordLabel.translatesAutoresizingMaskIntoConstraints = false

        sentenceLabel = NSTextField(wrappingLabelWithString: "")
        sentenceLabel.font = .systemFont(ofSize: 13)
        sentenceLabel.textColor = .secondaryLabelColor
        sentenceLabel.alignment = .center
        sentenceLabel.maximumNumberOfLines = 3
        sentenceLabel.translatesAutoresizingMaskIntoConstraints = false

        revealButton = NSButton(title: "显示释义 (空格)", target: self, action: #selector(revealDefinition))
        revealButton.bezelStyle = .rounded
        revealButton.translatesAutoresizingMaskIntoConstraints = false

        definitionScroll = NSScrollView()
        definitionScroll.translatesAutoresizingMaskIntoConstraints = false
        definitionScroll.hasVerticalScroller = true
        definitionScroll.borderType = .bezelBorder
        definitionScroll.drawsBackground = false

        definitionView = NSTextView()
        definitionView.isEditable = false
        definitionView.isSelectable = true
        definitionView.backgroundColor = .clear
        definitionView.textContainerInset = NSSize(width: 8, height: 8)
        definitionScroll.documentView = definitionView
        definitionScroll.isHidden = true

        ratingStack = NSStackView()
        ratingStack.orientation = .horizontal
        ratingStack.distribution = .fillEqually
        ratingStack.spacing = 8
        ratingStack.translatesAutoresizingMaskIntoConstraints = false
        ratingStack.isHidden = true

        let buttons: [(String, RecallQuality, NSColor)] = [
            ("忘记 (1)", .forgot, .systemRed),
            ("模糊 (2)", .hard, .systemOrange),
            ("记得 (3)", .good, .systemBlue),
            ("简单 (4)", .easy, .systemGreen)
        ]
        for (title, q, color) in buttons {
            let btn = NSButton(title: title, target: self, action: #selector(rateButtonTapped(_:)))
            btn.bezelStyle = .rounded
            btn.tag = q.rawValue
            btn.contentTintColor = color
            ratingStack.addArrangedSubview(btn)
        }

        container.addSubview(progressLabel)
        container.addSubview(wordLabel)
        container.addSubview(sentenceLabel)
        container.addSubview(revealButton)
        container.addSubview(definitionScroll)
        container.addSubview(ratingStack)

        NSLayoutConstraint.activate([
            progressLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            progressLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            wordLabel.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 12),
            wordLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            wordLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            sentenceLabel.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 8),
            sentenceLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            sentenceLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            revealButton.topAnchor.constraint(equalTo: sentenceLabel.bottomAnchor, constant: 16),
            revealButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            definitionScroll.topAnchor.constraint(equalTo: revealButton.bottomAnchor, constant: 12),
            definitionScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            definitionScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            definitionScroll.bottomAnchor.constraint(equalTo: ratingStack.topAnchor, constant: -16),

            ratingStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            ratingStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            ratingStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            ratingStack.heightAnchor.constraint(equalToConstant: 36)
        ])

        contentView = container
    }

    private func loadCurrent() {
        if index >= queue.count {
            finish()
            return
        }
        let entry = queue[index]
        progressLabel.stringValue = "进度 \(index + 1) / \(queue.count)"
        wordLabel.stringValue = entry.word
        sentenceLabel.stringValue = entry.sentence
        defRevealed = false
        definitionScroll.isHidden = true
        ratingStack.isHidden = true
        revealButton.isHidden = false
        definitionView.string = ""
    }

    @objc private func revealDefinition() {
        guard index < queue.count else { return }
        let entry = queue[index]
        let result = DictService.shared.lookup(entry.word)
        let text = result?.definition ?? "（未找到释义）"
        let attr = DefinitionFormatter.attributedString(
            word: result?.word ?? entry.word,
            definition: text,
            titleSize: 18,
            bodySize: 13
        )
        definitionView.textStorage?.setAttributedString(attr)
        defRevealed = true
        definitionScroll.isHidden = false
        ratingStack.isHidden = false
        revealButton.isHidden = true
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
        // 空格：显示释义
        if event.keyCode == 49 { // space
            if !defRevealed {
                revealDefinition()
                return
            }
        }
        // 1-4：评分（仅在已显示释义时生效）
        if defRevealed {
            let mapping: [UInt16: RecallQuality] = [
                18: .forgot, // 1
                19: .hard,   // 2
                20: .good,   // 3
                21: .easy    // 4
            ]
            if let q = mapping[event.keyCode] {
                applyRating(q)
                return
            }
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
