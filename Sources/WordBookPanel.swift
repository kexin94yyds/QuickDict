import Cocoa

class WordBookPanel: NSPanel {
    private var tableView: NSTableView!
    private var entries: [WordEntry] = []
    
    init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let panelWidth: CGFloat = 600
        let panelHeight: CGFloat = 500
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
        
        entries = WordBook.shared.getAll()
        setupContent()
    }
    
    private func setupContent() {
        let container = NSView(frame: self.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        
        let headerLabel = NSTextField(labelWithString: "📚 我的单词本 (\(entries.count) 条记录)")
        headerLabel.font = NSFont.boldSystemFont(ofSize: 18)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 60
        tableView.usesAlternatingRowBackgroundColors = true
        
        let wordColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("word"))
        wordColumn.title = "单词"
        wordColumn.width = 100
        tableView.addTableColumn(wordColumn)
        
        let sentenceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sentence"))
        sentenceColumn.title = "例句"
        sentenceColumn.width = 350
        tableView.addTableColumn(sentenceColumn)
        
        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "日期"
        dateColumn.width = 100
        tableView.addTableColumn(dateColumn)
        
        scrollView.documentView = tableView
        
        let refreshButton = NSButton(title: "刷新", target: self, action: #selector(refresh))
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        
        let exportButton = NSButton(title: "导出", target: self, action: #selector(exportData))
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(headerLabel)
        container.addSubview(scrollView)
        container.addSubview(refreshButton)
        container.addSubview(exportButton)
        
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 15),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
            
            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: refreshButton.topAnchor, constant: -10),
            
            refreshButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            refreshButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
            
            exportButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            exportButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 10)
        ])
        
        self.contentView = container
    }
    
    @objc private func refresh() {
        entries = WordBook.shared.getAll()
        tableView.reloadData()
    }
    
    @objc private func exportData() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "单词本_\(Date().formatted(date: .numeric, time: .omitted)).txt"
        
        savePanel.begin { [weak self] result in
            guard result == .OK, let url = savePanel.url, let self = self else { return }
            
            var content = "我的单词本\n\n"
            for (index, entry) in self.entries.enumerated() {
                content += "\(index + 1). \(entry.word)\n"
                content += "   例句: \(entry.sentence)\n"
                content += "   日期: \(entry.date.formatted())\n\n"
            }
            
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension WordBookPanel: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return entries.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        
        let cell = NSTextField(labelWithString: "")
        cell.lineBreakMode = .byTruncatingTail
        
        switch tableColumn?.identifier.rawValue {
        case "word":
            cell.stringValue = entry.word
            cell.font = NSFont.boldSystemFont(ofSize: 13)
        case "sentence":
            cell.stringValue = entry.sentence
            cell.font = NSFont.systemFont(ofSize: 12)
            cell.textColor = .secondaryLabelColor
        case "date":
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd HH:mm"
            cell.stringValue = formatter.string(from: entry.date)
            cell.font = NSFont.systemFont(ofSize: 11)
            cell.textColor = .tertiaryLabelColor
        default:
            break
        }
        
        return cell
    }
}
