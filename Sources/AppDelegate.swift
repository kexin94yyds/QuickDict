import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var eventMonitor: Any?
    var hotKeyRef: EventHotKeyRef?
    var hotKeyRef2: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !hasAnotherQuickDictInstance() else {
            NSLog("检测到已有 QuickDict 实例在运行，退出当前实例")
            NSApp.terminate(nil)
            return
        }
        
        NSApp.setActivationPolicy(.accessory)
        
        // 检查辅助功能权限
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        // 启动 WordBook（会自动迁移旧 JSON）
        _ = WordBook.shared

        DispatchQueue.main.async { [weak self] in
            self?.setupStatusItem()
            self?.setupPopover()
            self?.registerGlobalHotkey()
            self?.updateStatusBadge()

            // 显示权限状态
            if !accessibilityEnabled {
                self?.showAccessibilityAlert()
            }

            // 首次启动提示下载 ECDICT
            self?.checkECDICTAvailability()

            // 每日首次启动复习提醒
            self?.maybeShowReviewReminder()
        }
    }
    
    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "快捷查词需要辅助功能权限才能监听全局快捷键 ⌃L 和模拟复制操作。\n\n请前往：系统设置 → 隐私与安全性 → 辅助功能\n添加并启用 QuickDict"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后再说")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "快捷查词")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "测试查词 (手动)", action: #selector(testLookup), keyEquivalent: "t"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "快捷键 ⌃L : 查词（任意 App 选中后按）", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "快捷键 ⇧⌘B : 打开收藏库（全局）", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "打开单词本", action: #selector(openWordBook), keyEquivalent: "b"))
        let reviewItem = NSMenuItem(title: "开始复习", action: #selector(startReview), keyEquivalent: "r")
        menu.addItem(reviewItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "下载/更新离线词典 (ECDICT)", action: #selector(downloadECDICT), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "从本地文件导入词典…", action: #selector(importECDICT), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    /// 状态栏图标 badge（到期复习数量）
    private func updateStatusBadge() {
        guard let button = statusItem?.button else { return }
        let due = WordBook.shared.dueFavoriteCount()
        if due > 0 {
            button.title = " \(due)"
        } else {
            button.title = ""
        }
    }
    
    func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 300)
        popover.behavior = .transient
    }
    
    func registerGlobalHotkey() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        NSLog("辅助功能权限: \(accessibilityEnabled)")
        
        let eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return noErr }
                
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                guard status == noErr else { return status }
                
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                if hotKeyID.id == 1 {
                    NSLog("快捷键触发，开始查词")
                    delegate.lookupSelectedText()
                } else if hotKeyID.id == 2 {
                    NSLog("快捷键触发，打开收藏库")
                    DispatchQueue.main.async { delegate.openWordBook() }
                }
                
                return noErr
            },
            1,
            [eventSpec],
            userData,
            &hotKeyHandler
        )
        
        guard handlerStatus == noErr else {
            NSLog("安装快捷键处理器失败: \(handlerStatus)")
            return
        }
        
        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("QDLK"),
            id: 1
        )
        
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            UInt32(controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        NSLog("注册快捷键状态: \(registerStatus)")

        // ⇧⌘B → 打开收藏库
        let hotKeyID2 = EventHotKeyID(signature: fourCharCode("QDBK"), id: 2)
        let registerStatus2 = RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            UInt32(cmdKey | shiftKey),
            hotKeyID2,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef2
        )
        NSLog("注册收藏库快捷键状态: \(registerStatus2)")
    }
    
    func lookupSelectedText() {
        if let selectedText = selectedTextFromAccessibility() {
            NSLog("通过辅助功能获取到选中文本: \(selectedText)")
            showDictionary(for: selectedText)
            return
        }
        
        copySelectedTextFromFrontmostApp { [weak self] selectedText in
            guard let self = self else { return }
            
            if let selectedText, !selectedText.isEmpty {
                NSLog("通过复制回退获取到选中文本: \(selectedText)")
                self.showDictionary(for: selectedText)
            } else {
                NSLog("未获取到选中文本")
                self.showLookupFailure()
            }
        }
    }
    
    func showDictionary(for text: String) {
        let normalizedText = normalizeSelectedText(text)
        guard !normalizedText.isEmpty else { return }

        // 选定段里挑一个英文词做查询目标（去标点、过滤纯数字/符号、取最长的英文词）
        let candidate = pickLookupWord(from: normalizedText) ?? normalizedText
        let baseContext = (candidate == normalizedText) ? nil : normalizedText
        let possibleChineseDefinition = ChineseEnglishResolver.shared.containsCJK(candidate)
            ? DictService.shared.lookup(candidate)?.definition
            : nil
        let chineseResolution = ChineseEnglishResolver.shared.resolve(candidate, appleDefinition: possibleChineseDefinition)

        let result: LookupResult?
        let lookupWord: String
        let chineseDefinition: String?
        if let chineseResolution {
            chineseDefinition = possibleChineseDefinition
            var resolvedResult: LookupResult?
            var resolvedWord = chineseResolution.primary
            for englishCandidate in chineseResolution.candidates {
                if let candidateResult = DictService.shared.lookup(englishCandidate) {
                    resolvedResult = candidateResult
                    resolvedWord = candidateResult.word
                    break
                }
            }
            result = resolvedResult
            lookupWord = resolvedWord
        } else {
            chineseDefinition = nil
            result = DictService.shared.lookup(candidate)
            lookupWord = result?.word ?? candidate
        }

        let context = makeLookupContext(
            normalizedText: normalizedText,
            candidate: candidate,
            baseContext: baseContext,
            chineseResolution: chineseResolution,
            englishWord: result?.word ?? lookupWord
        )

        // 记录到 history（不自动保存为收藏，用户要保存自己点 ☆）
        WordBook.shared.recordLookup(word: result?.word ?? lookupWord, context: context)

        if let result {
            let displayWord = chineseResolution.map { "\($0.original) → \(result.word)" }
            let definition = chineseResolution.map {
                mergedChineseEnglishDefinition(
                    original: $0.original,
                    candidates: $0.candidates,
                    chineseDefinition: chineseDefinition,
                    englishDefinition: result.definition
                )
            } ?? result.definition
            let imageWords = chineseResolution.map {
                imageCandidateList(primary: result.word, candidates: $0.candidates)
            } ?? []
            let source = chineseResolution == nil
                ? result.source.rawValue
                : "\(result.source.rawValue) · 中文→英文"
            let panel = HUDPanel(word: result.word,
                                 definition: definition,
                                 source: source,
                                 context: context,
                                 displayWord: displayWord,
                                 imageWords: imageWords)
            panel.show()
        } else {
            let displayWord = chineseResolution.map { "\($0.original) → \(lookupWord)" }
            let definition: String
            if let chineseResolution {
                definition = """
                未找到「\(chineseResolution.original)」对应英文候选的定义

                已尝试候选：\(chineseResolution.candidates.joined(separator: " / "))

                可试试：
                • 菜单「下载/更新离线词典」获取 ECDICT
                • 换一个更具体的中文词
                """
            } else {
                definition = """
                未找到「\(candidate)」的定义

                可试试：
                • 在系统『词典』 App 里启用「简明英汉字典」
                • 菜单「下载/更新离线词典」获取 ECDICT (含 77万词条)。
                """
            }
            let panel = HUDPanel(
                word: lookupWord,
                definition: definition,
                context: context,
                displayWord: displayWord,
                imageWords: chineseResolution?.candidates ?? []
            )
            panel.show()
        }
    }

    private func makeLookupContext(
        normalizedText: String,
        candidate: String,
        baseContext: String?,
        chineseResolution: ChineseEnglishResolution?,
        englishWord: String
    ) -> String? {
        guard let chineseResolution else { return baseContext }
        var lines = [
            "中文原词：\(chineseResolution.original)",
            "英文主词：\(englishWord)"
        ]
        if chineseResolution.candidates.count > 1 {
            lines.append("英文候选：\(chineseResolution.candidates.joined(separator: " / "))")
        }
        if normalizedText != candidate {
            lines.append("原始选区：\(normalizedText)")
        }
        return lines.joined(separator: "\n")
    }

    private func mergedChineseEnglishDefinition(
        original: String,
        candidates: [String],
        chineseDefinition: String?,
        englishDefinition: String
    ) -> String {
        var sections: [String] = []
        if let chineseDefinition, !chineseDefinition.isEmpty {
            sections.append("【中文原词】\n\(original)\n\n\(chineseDefinition)")
        } else {
            sections.append("【中文原词】\n\(original)")
        }
        sections.append("【英文主词】\n\(englishDefinition)")
        if candidates.count > 1 {
            sections.append("【英文候选】\n\(candidates.joined(separator: " / "))")
        }
        return sections.joined(separator: "\n\n")
    }

    private func imageCandidateList(primary: String, candidates: [String]) -> [String] {
        var out: [String] = [primary]
        for candidate in candidates where !out.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
            out.append(candidate)
        }
        return out
    }

    /// 从一段选定文本里挑出最适合查询的英文单词
    /// 规则：去标点；保留只含字母（含连字符）的 token；优先取最长（长度 ≥ 3）
    private func pickLookupWord(from text: String) -> String? {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters).union(.symbols)
        let tokens = text.components(separatedBy: separators).filter { !$0.isEmpty }
        let englishWords = tokens.filter { tok in
            tok.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" }
                && tok.contains(where: { $0.isLetter })
        }
        // 单词数 ≤ 2 时直接拼接；多词时取最长那个
        if englishWords.count <= 2 {
            return englishWords.joined(separator: " ").isEmpty ? nil : englishWords.joined(separator: " ")
        }
        return englishWords.max(by: { $0.count < $1.count })
    }
    
    func saveToWordBook(sentence: String) {
        let words = sentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let firstWord = words.first ?? sentence

        _ = WordBook.shared.addFavorite(word: firstWord, sentence: sentence)
        updateStatusBadge()

        let panel = SavedPanel(word: firstWord, sentence: sentence, count: WordBook.shared.favoriteCount())
        panel.show()
    }
    
    @objc func openWordBook() {
        let panel = WordBookPanel()
        panel.show()
    }

    @objc func startReview() {
        let due = WordBook.shared.getDueFavorites()
        if due.isEmpty {
            let alert = NSAlert()
            alert.messageText = "暂无到期复习的单词"
            alert.informativeText = "现在还没有要复习的单词。先收藏一些单词、句子后，复习会按固定间隔自动安排。"
            alert.runModal()
            return
        }
        let panel = ReviewPanel(entries: due)
        panel.show()
    }

    @objc func downloadECDICT() {
        let alert = NSAlert()
        alert.messageText = "下载 ECDICT 离线词典"
        alert.informativeText = "将从 GitHub 下载 ECDICT 词典数据库（约 50MB，含 77万词条）到本机。需要联网。"
        alert.addButton(withTitle: "开始下载")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        showECDICTDownloadProgress()
    }

    private func showECDICTDownloadProgress() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 130),
            styleMask: [.titled],
            backing: .buffered, defer: false
        )
        win.title = "下载 ECDICT…"
        win.center()

        let label = NSTextField(labelWithString: "正在下载词典… 0%")
        label.translatesAutoresizingMaskIntoConstraints = false
        let bar = NSProgressIndicator()
        bar.isIndeterminate = false
        bar.minValue = 0; bar.maxValue = 1
        bar.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(label)
        content.addSubview(bar)
        win.contentView = content
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            bar.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 14),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20)
        ])
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        ECDictionary.shared.downloadDictionary(progress: { p in
            bar.doubleValue = p
            label.stringValue = String(format: "正在下载词典… %.0f%%", p * 100)
        }, completion: { result in
            win.close()
            let done = NSAlert()
            switch result {
            case .success:
                done.messageText = "词典下载完成 ✅"
                done.informativeText = "ECDICT 已可用，查不到的词会自动走这个词典。"
            case .failure(let err):
                done.messageText = "下载失败"
                done.informativeText = "错误: \(err.localizedDescription)\n\n你也可以从 GitHub Releases 手动下载后，菜单选「从本地文件导入词典」。"
            }
            done.runModal()
        })
    }

    @objc func importECDICT() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.data]
        panel.message = "选择 ecdict.db / stardict.db / .zip 文件"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try ECDictionary.shared.importDictionary(from: url)
                let a = NSAlert()
                a.messageText = "导入成功 ✅"
                a.informativeText = "词典已加载，可以查词了。"
                a.runModal()
            } catch {
                let a = NSAlert()
                a.messageText = "导入失败"
                a.informativeText = "\(error.localizedDescription)"
                a.runModal()
            }
        }
    }

    /// 每日首次启动复习提醒
    private func maybeShowReviewReminder() {
        let key = "QuickDict.lastReviewReminderDay"
        let today = dayString(Date())
        if UserDefaults.standard.string(forKey: key) == today { return }

        let due = WordBook.shared.dueFavoriteCount()
        guard due > 0 else { return }

        UserDefaults.standard.set(today, forKey: key)

        let alert = NSAlert()
        alert.messageText = "今天有 \(due) 个单词待复习"
        alert.informativeText = "要现在开始复习吗？可以随时从菜单栏「开始复习」中进入。"
        alert.addButton(withTitle: "开始复习")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            startReview()
        }
    }

    private func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 检查 ECDICT 是否已下载，如果没有且从未提示过，提示下载
    private func checkECDICTAvailability() {
        if ECDictionary.shared.isReady { return }

        let key = "QuickDict.ECDICTPromptedV1"
        if UserDefaults.standard.bool(forKey: key) { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "是否下载离线词典 ECDICT？"
        alert.informativeText = "仅依赖系统词典可能查不到中文释义。推荐下载 ECDICT（约 50MB，含 77万词条、音标、考试标签）。随时可从菜单重新下载。"
        alert.addButton(withTitle: "现在下载")
        alert.addButton(withTitle: "以后再说")
        if alert.runModal() == .alertFirstButtonReturn {
            showECDICTDownloadProgress()
        }
    }

    @objc func testLookup() {
        // 手动测试：直接使用剪贴板内容查词
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            NSLog("手动测试 - 剪贴板内容: \(text)")
            showDictionary(for: text)
        } else {
            // 测试显示功能
            NSLog("手动测试 - 剪贴板为空，显示测试窗口")
            let panel = HUDPanel(word: "测试", definition: "这是一个测试窗口\n\n如果看到这个窗口，说明显示功能正常。\n\n请复制一个单词后再次点击测试查词。")
            panel.show()
        }
    }
    
    @objc func quit() {
        NSApp.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        if let hotKeyRef2 {
            UnregisterEventHotKey(hotKeyRef2)
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
        }
    }

    private func selectedTextFromAccessibility() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        
        guard focusedResult == .success, let focusedElementRef else {
            NSLog("读取焦点元素失败: \(focusedResult.rawValue)")
            return nil
        }
        
        let focusedElement = focusedElementRef as! AXUIElement
        
        if let selectedText = copyStringAttribute(kAXSelectedTextAttribute as CFString, from: focusedElement) {
            let normalized = normalizeSelectedText(selectedText)
            if !normalized.isEmpty {
                return normalized
            }
        }
        
        return selectedTextFromRange(on: focusedElement)
    }
    
    private func selectedTextFromRange(on element: AXUIElement) -> String? {
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        
        guard rangeResult == .success, let rangeRef else {
            return nil
        }
        
        let rangeValue = rangeRef as! AXValue
        
        guard AXValueGetType(rangeValue) == .cfRange else {
            return nil
        }
        
        var selectedRange = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &selectedRange), selectedRange.length > 0 else {
            return nil
        }
        
        var selectedTextRef: CFTypeRef?
        let textResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &selectedTextRef
        )
        
        guard textResult == .success, let selectedText = selectedTextRef as? String else {
            return nil
        }
        
        let normalized = normalizeSelectedText(selectedText)
        return normalized.isEmpty ? nil : normalized
    }
    
    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success, let value = valueRef as? String else {
            return nil
        }
        
        return value
    }
    
    private func copySelectedTextFromFrontmostApp(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let originalSnapshot = snapshotPasteboard(pasteboard)
        let originalChangeCount = pasteboard.changeCount
        
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        waitForCopiedText(
            originalChangeCount: originalChangeCount,
            maxAttempts: 8,
            interval: 0.1
        ) { copiedText in
            self.restorePasteboard(pasteboard, from: originalSnapshot)
            completion(copiedText)
        }
    }
    
    private func waitForCopiedText(
        originalChangeCount: Int,
        maxAttempts: Int,
        interval: TimeInterval,
        completion: @escaping (String?) -> Void
    ) {
        let pasteboard = NSPasteboard.general
        
        func poll(attempt: Int) {
            if pasteboard.changeCount != originalChangeCount {
                let copiedText = pasteboard.string(forType: .string)
                completion(copiedText)
                return
            }
            
            guard attempt < maxAttempts else {
                completion(nil)
                return
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                poll(attempt: attempt + 1)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            poll(attempt: 1)
        }
    }
    
    private func normalizeSelectedText(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func showLookupFailure() {
        let panel = HUDPanel(
            word: "未获取到选中文本",
            definition: """
            请确认以下几点：
            1. 已在“系统设置 → 隐私与安全性 → 辅助功能”中启用 QuickDict
            2. 当前应用允许复制所选文本
            3. 选中的是可复制的纯文本
            
            如果仍失败，可以先复制单词，再从菜单栏里点“测试查词 (手动)”验证词典功能。
            """
        )
        panel.show()
    }
    
    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        
        return items.map { item in
            var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot[type] = data
                }
            }
            return snapshot
        }
    }
    
    private func restorePasteboard(_ pasteboard: NSPasteboard, from snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        pasteboard.clearContents()
        
        guard !snapshot.isEmpty else { return }
        
        let items: [NSPasteboardItem] = snapshot.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        
        pasteboard.writeObjects(items)
    }
    
    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
    
    private func hasAnotherQuickDictInstance() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        
        return NSWorkspace.shared.runningApplications.contains { app in
            guard app.processIdentifier != currentPID else { return false }
            
            let executableName = app.executableURL?.lastPathComponent ?? ""
            let bundleName = app.bundleURL?.lastPathComponent ?? ""
            let localizedName = app.localizedName ?? ""
            
            let myBundleID = Bundle.main.bundleIdentifier
            let sameBundleID = (myBundleID != nil) && (app.bundleIdentifier == myBundleID)
            let looksLikeQuickDict = executableName == "QuickDict"
                || bundleName == "QuickDict.app"
                || bundleName == "快捷查词.app"
                || localizedName == "QuickDict"
                || localizedName == "快捷查词"
            
            return sameBundleID || looksLikeQuickDict
        }
    }
}
