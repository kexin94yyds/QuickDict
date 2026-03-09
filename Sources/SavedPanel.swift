import Cocoa

class SavedPanel: NSPanel {
    private var word: String
    private var sentence: String
    private var count: Int
    
    init(word: String, sentence: String, count: Int) {
        self.word = word
        self.sentence = sentence
        self.count = count
        
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 150
        let panelX = (screenFrame.width - panelWidth) / 2
        let panelY = (screenFrame.height - panelHeight) / 2 + 100
        
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
        
        let checkmark = NSTextField(labelWithString: "✓")
        checkmark.font = NSFont.systemFont(ofSize: 40, weight: .light)
        checkmark.textColor = .systemGreen
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = NSTextField(labelWithString: "已保存到单词本")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let countLabel = NSTextField(labelWithString: "第 \(count) 条记录")
        countLabel.font = NSFont.systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let previewLabel = NSTextField(wrappingLabelWithString: sentence)
        previewLabel.font = NSFont.systemFont(ofSize: 11)
        previewLabel.textColor = .tertiaryLabelColor
        previewLabel.maximumNumberOfLines = 2
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        
        visualEffect.addSubview(checkmark)
        visualEffect.addSubview(titleLabel)
        visualEffect.addSubview(countLabel)
        visualEffect.addSubview(previewLabel)
        
        NSLayoutConstraint.activate([
            checkmark.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 20),
            checkmark.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor, constant: -10),
            
            titleLabel.leadingAnchor.constraint(equalTo: checkmark.trailingAnchor, constant: 15),
            titleLabel.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 25),
            
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            countLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            
            previewLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            previewLabel.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -20),
            previewLabel.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 10)
        ])
        
        self.contentView = visualEffect
    }
    
    private func setupAutoClose() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.orderOut(nil)
        }
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
    }
}
