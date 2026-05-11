import Cocoa

/// 单词本：历史 / 收藏 双 Tab + 搜索 + 删除 + 导出（TXT / Anki TSV）
class WordBookPanel: NSPanel {
    enum Tab: Int { case favorites = 0, history = 1 }

    private var segment: NSSegmentedControl!
    private var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var headerLabel: NSTextField!

    private var currentTab: Tab = .favorites
    private var favorites: [FavoriteEntry] = []
    private var history: [HistoryEntry] = []

    init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let panelWidth: CGFloat = 720
        let panelHeight: CGFloat = 540
        let panelX = (screenFrame.width - panelWidth) / 2
        let panelY = (screenFrame.height - panelHeight) / 2

        super.init(
            contentRect: NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "单词本"
        self.level = .floating
        self.isReleasedWhenClosed = false

        setupContent()
        reload()
    }

    private func setupContent() {
        let container = NSView(frame: contentView!.bounds)
        container.autoresizingMask = [.width, .height]

        segment = NSSegmentedControl(labels: ["⭐ 收藏", "🕐 历史"], trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
        segment.selectedSegment = 0
        segment.translatesAutoresizingMaskIntoConstraints = false

        headerLabel = NSTextField(labelWithString: "")
        headerLabel.font = NSFont.systemFont(ofSize: 12)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        searchField = NSSearchField()
        searchField.placeholderString = "搜索单词或例句"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 56
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.menu = makeContextMenu()
        scrollView.documentView = tableView

        rebuildColumns()

        let refreshButton = NSButton(title: "刷新", target: self, action: #selector(reload))
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        let reviewButton = NSButton(title: "开始复习", target: self, action: #selector(startReview))
        reviewButton.translatesAutoresizingMaskIntoConstraints = false
        reviewButton.bezelStyle = .rounded
        reviewButton.contentTintColor = .systemBlue

        let exportTxtButton = NSButton(title: "导出 TXT", target: self, action: #selector(exportTxt))
        exportTxtButton.translatesAutoresizingMaskIntoConstraints = false

        let exportAnkiButton = NSButton(title: "导出 Anki", target: self, action: #selector(exportAnki))
        exportAnkiButton.translatesAutoresizingMaskIntoConstraints = false

        let deleteButton = NSButton(title: "删除选中", target: self, action: #selector(deleteSelected))
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(segment)
        container.addSubview(headerLabel)
        container.addSubview(searchField)
        container.addSubview(scrollView)
        container.addSubview(refreshButton)
        container.addSubview(reviewButton)
        container.addSubview(exportTxtButton)
        container.addSubview(exportAnkiButton)
        container.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            segment.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            segment.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            headerLabel.centerYAnchor.constraint(equalTo: segment.centerYAnchor),
            headerLabel.leadingAnchor.constraint(equalTo: segment.trailingAnchor, constant: 16),

            searchField.centerYAnchor.constraint(equalTo: segment.centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            searchField.widthAnchor.constraint(equalToConstant: 220),

            scrollView.topAnchor.constraint(equalTo: segment.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: refreshButton.topAnchor, constant: -10),

            refreshButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            refreshButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            reviewButton.bottomAnchor.constraint(equalTo: refreshButton.bottomAnchor),
            reviewButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),

            deleteButton.bottomAnchor.constraint(equalTo: refreshButton.bottomAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: reviewButton.trailingAnchor, constant: 8),

            exportAnkiButton.bottomAnchor.constraint(equalTo: refreshButton.bottomAnchor),
            exportAnkiButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            exportTxtButton.bottomAnchor.constraint(equalTo: refreshButton.bottomAnchor),
            exportTxtButton.trailingAnchor.constraint(equalTo: exportAnkiButton.leadingAnchor, constant: -8)
        ])

        contentView = container
    }

    private func rebuildColumns() {
        for col in tableView.tableColumns { tableView.removeTableColumn(col) }
        switch currentTab {
        case .favorites:
            addColumn("word", title: "单词", width: 110)
            addColumn("sentence", title: "例句 / 上下文", width: 320)
            addColumn("date", title: "添加时间", width: 110)
            addColumn("due", title: "下次复习", width: 110)
        case .history:
            addColumn("word", title: "单词", width: 140)
            addColumn("count", title: "查询次数", width: 70)
            addColumn("last", title: "最近查询", width: 130)
            addColumn("context", title: "上下文", width: 280)
        }
    }

    private func addColumn(_ id: String, title: String, width: CGFloat) {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        col.title = title
        col.width = width
        tableView.addTableColumn(col)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "查询此词", action: #selector(lookupSelected), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "复制单词", action: #selector(copySelected), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "添加到收藏", action: #selector(favoriteSelected), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "删除", action: #selector(deleteSelected), keyEquivalent: ""))
        return menu
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        let newTab = Tab(rawValue: sender.selectedSegment) ?? .favorites
        if newTab == currentTab { return }
        // 先清空旧数据并 reloadData，避免 rebuildColumns 时 NSTableView 重用旧 row views
        // 调用 viewFor 访问不匹配的数组越界。
        favorites.removeAll()
        history.removeAll()
        tableView.reloadData()
        currentTab = newTab
        rebuildColumns()
        reload()
    }

    @objc private func searchChanged() {
        reload()
    }

    @objc private func reload() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        let q: String? = query.isEmpty ? nil : query
        switch currentTab {
        case .favorites:
            favorites = WordBook.shared.getAllFavorites(search: q)
            let due = WordBook.shared.dueFavoriteCount()
            headerLabel.stringValue = "共 \(favorites.count) 条收藏  ·  \(due) 个待复习"
        case .history:
            history = WordBook.shared.getHistory(search: q, limit: 1000)
            headerLabel.stringValue = "共 \(history.count) 条查询历史"
        }
        tableView.reloadData()
    }

    @objc private func rowDoubleClicked() {
        lookupSelected()
    }

    @objc private func lookupSelected() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0 else { return }
        let word: String
        switch currentTab {
        case .favorites: word = favorites[row].word
        case .history: word = history[row].word
        }
        if let result = DictService.shared.lookup(word) {
            HUDPanel(word: result.word, definition: result.definition, source: result.source.rawValue).show()
        } else {
            HUDPanel(word: word, definition: "未找到「\(word)」的定义").show()
        }
    }

    @objc private func copySelected() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0 else { return }
        let word: String
        switch currentTab {
        case .favorites: word = favorites[row].word
        case .history: word = history[row].word
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(word, forType: .string)
    }

    @objc private func favoriteSelected() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0 else { return }
        switch currentTab {
        case .favorites:
            return // 已在收藏内
        case .history:
            let h = history[row]
            _ = WordBook.shared.addFavorite(word: h.word, sentence: h.lastContext ?? h.word)
            reload()
        }
    }

    @objc private func deleteSelected() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0 else { return }
        switch currentTab {
        case .favorites:
            WordBook.shared.deleteFavorite(id: favorites[row].id)
        case .history:
            WordBook.shared.deleteHistory(word: history[row].word)
        }
        reload()
    }

    @objc private func startReview() {
        let due = WordBook.shared.getDueFavorites()
        guard !due.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "暂无到期复习的单词"
            alert.informativeText = "现在还没有到期的复习。先收藏一些单词，复习会按固定间隔自动安排。"
            alert.runModal()
            return
        }
        let panel = ReviewPanel(entries: due)
        panel.show()
    }

    @objc private func exportTxt() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        let stamp = Date().formatted(.dateTime.year().month().day())
        savePanel.nameFieldStringValue = "单词本_\(stamp).txt"
        savePanel.begin { [weak self] result in
            guard result == .OK, let url = savePanel.url, let self else { return }
            var text = ""
            switch self.currentTab {
            case .favorites:
                text = "我的收藏单词\n\n"
                for (i, e) in self.favorites.enumerated() {
                    text += "\(i + 1). \(e.word)\n   例句: \(e.sentence)\n   添加: \(e.addedAt.formatted())\n\n"
                }
            case .history:
                text = "查询历史\n\n"
                for (i, e) in self.history.enumerated() {
                    text += "\(i + 1). \(e.word) (查询 \(e.lookupCount) 次)\n"
                    if let c = e.lastContext, !c.isEmpty {
                        text += "   上下文: \(c)\n"
                    }
                    text += "   最近: \(e.lastAt.formatted())\n\n"
                }
            }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// 导出为 Anki 可导入的 TSV：单词 \t 释义 \t 例句
    @objc private func exportAnki() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText, .plainText]
        let stamp = Date().formatted(.dateTime.year().month().day())
        savePanel.nameFieldStringValue = "anki_\(stamp).tsv"
        savePanel.begin { [weak self] result in
            guard result == .OK, let url = savePanel.url, let self else { return }
            var lines: [String] = []
            let words: [(word: String, sentence: String)] = {
                switch self.currentTab {
                case .favorites: return self.favorites.map { ($0.word, $0.sentence) }
                case .history: return self.history.map { ($0.word, $0.lastContext ?? "") }
                }
            }()
            for w in words {
                let def = DictService.shared.lookup(w.word)?.definition ?? ""
                let row = [w.word, def, w.sentence]
                    .map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: "<br>") }
                    .joined(separator: "\t")
                lines.append(row)
            }
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func show() {
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension WordBookPanel: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        switch currentTab {
        case .favorites: return favorites.count
        case .history: return history.count
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: "")
        cell.lineBreakMode = .byTruncatingTail
        let id = tableColumn?.identifier.rawValue ?? ""

        switch currentTab {
        case .favorites:
            guard row >= 0, row < favorites.count else { return cell }
            let e = favorites[row]
            switch id {
            case "word":
                cell.stringValue = e.word
                cell.font = .boldSystemFont(ofSize: 13)
            case "sentence":
                cell.stringValue = e.sentence
                cell.font = .systemFont(ofSize: 12)
                cell.textColor = .secondaryLabelColor
            case "date":
                cell.stringValue = formatShortDate(e.addedAt)
                cell.font = .systemFont(ofSize: 11)
                cell.textColor = .tertiaryLabelColor
            case "due":
                let now = Date()
                if e.dueAt <= now {
                    cell.stringValue = "待复习"
                    cell.textColor = .systemRed
                } else {
                    cell.stringValue = formatShortDate(e.dueAt)
                    cell.textColor = .tertiaryLabelColor
                }
                cell.font = .systemFont(ofSize: 11)
            default: break
            }
        case .history:
            guard row >= 0, row < history.count else { return cell }
            let e = history[row]
            switch id {
            case "word":
                cell.stringValue = e.word
                cell.font = .boldSystemFont(ofSize: 13)
            case "count":
                cell.stringValue = "× \(e.lookupCount)"
                cell.font = .systemFont(ofSize: 12)
                cell.textColor = .secondaryLabelColor
            case "last":
                cell.stringValue = formatShortDate(e.lastAt)
                cell.font = .systemFont(ofSize: 11)
                cell.textColor = .tertiaryLabelColor
            case "context":
                cell.stringValue = e.lastContext ?? ""
                cell.font = .systemFont(ofSize: 12)
                cell.textColor = .secondaryLabelColor
            default: break
            }
        }
        return cell
    }

    private func formatShortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
    }
}
