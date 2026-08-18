import AppKit

struct PasteboardSnapshot: Equatable {
    struct Item: Equatable {
        let representations: [String: Data]
    }

    let items: [Item]
    let missingRepresentationCount: Int

    var itemCount: Int { items.count }
    var representationCount: Int {
        items.reduce(0) { $0 + $1.representations.count }
    }
    var isComplete: Bool {
        missingRepresentationCount == 0
            && items.allSatisfy { !$0.representations.isEmpty }
    }

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            return PasteboardSnapshot(items: [], missingRepresentationCount: 0)
        }

        var missingRepresentationCount = 0
        let items = pasteboardItems.map { pasteboardItem in
            var representations: [String: Data] = [:]

            if pasteboardItem.types.isEmpty {
                missingRepresentationCount += 1
            }

            for type in pasteboardItem.types {
                if let data = pasteboardItem.data(forType: type) {
                    // A representation can be backed by the current pasteboard owner.
                    // Copy its bytes before any later clearContents() invalidates that owner.
                    representations[type.rawValue] = data.withUnsafeBytes { Data($0) }
                } else {
                    missingRepresentationCount += 1
                }
            }

            return Item(representations: representations)
        }

        return PasteboardSnapshot(
            items: items,
            missingRepresentationCount: missingRepresentationCount
        )
    }

    func restore(to pasteboard: NSPasteboard) -> PasteboardRestoreResult {
        let changeCountBeforeRestore = pasteboard.changeCount
        guard isComplete || items.isEmpty else {
            return PasteboardRestoreResult(
                attempted: false,
                representationsAccepted: false,
                writeSucceeded: false,
                exactMatch: false,
                changeCountBeforeRestore: changeCountBeforeRestore,
                changeCountAfterRestore: changeCountBeforeRestore
            )
        }

        // Rehydrate every destination item before clearing the source pasteboard. The
        // previous clear-first order could invalidate lazily supplied representations
        // and leave the general pasteboard empty when writeObjects() had nothing valid.
        var representationsAccepted = true
        let pasteboardItems = items.map { snapshotItem -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for (rawType, data) in snapshotItem.representations {
                let type = NSPasteboard.PasteboardType(rawValue: rawType)
                if !pasteboardItem.setData(data, forType: type) {
                    representationsAccepted = false
                }
            }
            return pasteboardItem
        }

        guard representationsAccepted else {
            return PasteboardRestoreResult(
                attempted: false,
                representationsAccepted: false,
                writeSucceeded: false,
                exactMatch: false,
                changeCountBeforeRestore: changeCountBeforeRestore,
                changeCountAfterRestore: changeCountBeforeRestore
            )
        }

        pasteboard.clearContents()
        let writeSucceeded = pasteboardItems.isEmpty || pasteboard.writeObjects(pasteboardItems)
        let restoredSnapshot = PasteboardSnapshot.capture(from: pasteboard)

        return PasteboardRestoreResult(
            attempted: true,
            representationsAccepted: true,
            writeSucceeded: writeSucceeded,
            exactMatch: restoredSnapshot == self,
            changeCountBeforeRestore: changeCountBeforeRestore,
            changeCountAfterRestore: pasteboard.changeCount
        )
    }
}

struct PasteboardRestoreResult: Equatable {
    let attempted: Bool
    let representationsAccepted: Bool
    let writeSucceeded: Bool
    let exactMatch: Bool
    let changeCountBeforeRestore: Int
    let changeCountAfterRestore: Int
}
