import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var eventMonitor: Any?
    var hotKeyRef: EventHotKeyRef?
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
        
        DispatchQueue.main.async { [weak self] in
            self?.setupStatusItem()
            self?.setupPopover()
            self?.registerGlobalHotkey()
            
            // 显示权限状态
            if !accessibilityEnabled {
                self?.showAccessibilityAlert()
            }
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
        menu.addItem(NSMenuItem(title: "快捷键: ⌃L (查词/保存)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "单词≤2个: 查词典", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "单词>2个: 保存到单词本", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "打开单词本", action: #selector(openWordBook), keyEquivalent: "b"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
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
        
        let wordCount = normalizedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        
        if wordCount > 2 {
            saveToWordBook(sentence: normalizedText)
        } else {
            let lookupText = normalizedText.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            let finalLookupText = lookupText.isEmpty ? normalizedText : lookupText
            
            if let definition = DCSCopyTextDefinition(nil, finalLookupText as CFString, CFRangeMake(0, (finalLookupText as NSString).length))?.takeRetainedValue() as String? {
                let panel = HUDPanel(word: finalLookupText, definition: definition)
                panel.show()
            } else {
                let panel = HUDPanel(
                    word: finalLookupText,
                    definition: "未找到「\(finalLookupText)」的定义\n\n你也可以先打开系统“词典”App确认该词是否存在，或选中更干净的单词/短语后重试。"
                )
                panel.show()
            }
        }
    }
    
    func saveToWordBook(sentence: String) {
        let words = sentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let firstWord = words.first ?? sentence
        
        WordBook.shared.add(word: firstWord, sentence: sentence)
        
        let panel = SavedPanel(word: firstWord, sentence: sentence, count: WordBook.shared.getCount())
        panel.show()
    }
    
    @objc func openWordBook() {
        let panel = WordBookPanel()
        panel.show()
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
            
            let sameBundleID = app.bundleIdentifier == Bundle.main.bundleIdentifier
            let looksLikeQuickDict = executableName == "QuickDict"
                || bundleName == "QuickDict.app"
                || bundleName == "快捷查词.app"
                || localizedName == "QuickDict"
                || localizedName == "快捷查词"
            
            return sameBundleID || looksLikeQuickDict
        }
    }
}
