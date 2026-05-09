import Cocoa

class HUDPanel: NSPanel {
    private var word: String
    private var definition: String
    private var source: String?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var autoCloseWorkItem: DispatchWorkItem?
    private var favoriteButton: NSButton?

    init(word: String, definition: String, source: String? = nil) {
        self.word = word
        self.definition = definition
        self.source = source
        
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let panelWidth: CGFloat = 450
        let panelHeight: CGFloat = 380
        
        // 获取鼠标位置，将弹窗显示在单词下方（避免遮挡）
        let mouseLocation = NSEvent.mouseLocation
        let offset: CGFloat = 25  // 距离鼠标的偏移量
        
        var panelX = mouseLocation.x - panelWidth / 2
        var panelY = mouseLocation.y - panelHeight - offset  // 显示在鼠标下方
        
        // 如果下方空间不够，则显示在上方
        if panelY < screenFrame.minY {
            panelY = mouseLocation.y + offset
        }
        
        // 确保不超出屏幕左右边界
        if panelX < screenFrame.minX {
            panelX = screenFrame.minX + 10
        } else if panelX + panelWidth > screenFrame.maxX {
            panelX = screenFrame.maxX - panelWidth - 10
        }
        
        // 确保不超出屏幕上边界
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
        
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        
        let textView = NSTextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        
        let attrString = formatDefinition(word: word, definition: definition)
        textView.textStorage?.setAttributedString(attrString)
        
        scrollView.documentView = textView
        
        visualEffect.addSubview(scrollView)
        visualEffect.addSubview(closeButton)
        visualEffect.addSubview(favBtn)
        visualEffect.addSubview(sourceLabel)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: favBtn.topAnchor, constant: -8),

            favBtn.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 12),
            favBtn.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -10),

            sourceLabel.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -12),
            sourceLabel.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -10)
        ])
        
        textView.frame = scrollView.bounds
        textView.autoresizingMask = [.width]
        
        self.contentView = visualEffect
    }
    
    private func formatDefinition(word: String, definition: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 22),
            .foregroundColor: NSColor.labelColor
        ]
        
        let phoneticAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        
        let posAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        
        let defAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        
        let chineseAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        
        result.append(NSAttributedString(string: word + "\n", attributes: titleAttrs))
        
        var text = definition
        if let range = text.range(of: #"\|[^|]+\|"#, options: .regularExpression) {
            let phonetic = String(text[range])
            result.append(NSAttributedString(string: phonetic + "\n\n", attributes: phoneticAttrs))
            text = text.replacingCharacters(in: range, with: "")
        }
        
        let circleNums: [(String, String)] = [
            ("①", "\n\n1. "), ("②", "\n\n2. "), ("③", "\n\n3. "), ("④", "\n\n4. "), ("⑤", "\n\n5. "),
            ("⑥", "\n\n6. "), ("⑦", "\n\n7. "), ("⑧", "\n\n8. "), ("⑨", "\n\n9. "), ("⑩", "\n\n10. ")
        ]
        for (circle, num) in circleNums {
            text = text.replacingOccurrences(of: circle, with: num)
        }
        
        text = text.replacingOccurrences(of: "▸", with: "\n    • ")
        text = text.replacingOccurrences(of: "•", with: "\n    • ")
        
        let posKeywords = [" noun ", " verb ", " adjective ", " adverb ", 
                          "A. noun", "A. verb", "A. adjective", "B. noun", "B. verb", "B. adjective",
                          "B. plural noun", "C. noun", "C. verb"]
        for kw in posKeywords {
            text = text.replacingOccurrences(of: kw, with: "\n\n【\(kw.trimmingCharacters(in: .whitespaces))】\n")
        }
        
        let lines = text.components(separatedBy: CharacterSet.newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            if trimmed.hasPrefix("【") && trimmed.hasSuffix("】") {
                result.append(NSAttributedString(string: "\n" + trimmed + "\n", attributes: posAttrs))
                continue
            }
            
            if trimmed.hasPrefix("1.") || trimmed.hasPrefix("2.") || trimmed.hasPrefix("3.") ||
               trimmed.hasPrefix("4.") || trimmed.hasPrefix("5.") || trimmed.hasPrefix("6.") ||
               trimmed.hasPrefix("7.") || trimmed.hasPrefix("8.") || trimmed.hasPrefix("9.") ||
               trimmed.hasPrefix("10.") {
                let numEnd = trimmed.firstIndex(of: ".")!
                let numPart = String(trimmed[...numEnd]) + " "
                let rest = String(trimmed[trimmed.index(after: numEnd)...]).trimmingCharacters(in: .whitespaces)
                result.append(NSAttributedString(string: numPart, attributes: numAttrs))
                if containsChinese(rest) {
                    result.append(NSAttributedString(string: rest + "\n", attributes: chineseAttrs))
                } else {
                    result.append(NSAttributedString(string: rest + "\n", attributes: defAttrs))
                }
                continue
            }
            
            if trimmed.hasPrefix("•") {
                result.append(NSAttributedString(string: "  ", attributes: defAttrs))
                result.append(NSAttributedString(string: "• ", attributes: numAttrs))
                let rest = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                if containsChinese(rest) {
                    result.append(NSAttributedString(string: rest + "\n", attributes: chineseAttrs))
                } else {
                    result.append(NSAttributedString(string: rest + "\n", attributes: defAttrs))
                }
                continue
            }
            
            if containsChinese(trimmed) {
                result.append(NSAttributedString(string: "  " + trimmed + "\n", attributes: chineseAttrs))
            } else {
                result.append(NSAttributedString(string: trimmed + "\n", attributes: defAttrs))
            }
        }
        
        return result
    }
    
    private func containsChinese(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) {
                return true
            }
        }
        return false
    }
    
    private func setupAutoClose() {
        // Esc 关闭
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.closePanel()
                return nil
            }
            return event
        }

        // 只在「点击面板外部」时关闭（修复：原来点面板内也会立即关）
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: workItem)
    }
}
