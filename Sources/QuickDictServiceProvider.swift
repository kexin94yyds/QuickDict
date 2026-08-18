import Cocoa

enum QuickDictServiceRequest {
    static func selectedText(from pasteboard: NSPasteboard) -> String? {
        guard pasteboard.availableType(from: [.string]) != nil,
              let rawText = pasteboard.string(forType: .string) else {
            return nil
        }

        let normalized = rawText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }
}

final class QuickDictServiceProvider: NSObject {
    private let lookup: (String) -> Void

    init(lookup: @escaping (String) -> Void) {
        self.lookup = lookup
    }

    @objc func lookupSelection(
        _ pasteboard: NSPasteboard,
        userData _: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let selectedText = QuickDictServiceRequest.selectedText(from: pasteboard) else {
            error.pointee = "没有收到可查询的文本。" as NSString
            return
        }

        if Thread.isMainThread {
            lookup(selectedText)
        } else {
            DispatchQueue.main.async { [lookup] in
                lookup(selectedText)
            }
        }
    }
}
