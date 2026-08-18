import Foundation

enum PasteboardCopySettleDecision: Equatable {
    case waiting
    case ready(text: String, expectedChangeCount: Int)
    case preserveCurrentClipboard(text: String)
    case unavailable
}

struct PasteboardCopySettleState {
    private(set) var copiedText: String?
    private var lastObservedChangeCount: Int?
    private var stableObservationCount = 0

    mutating func observe(
        originalChangeCount: Int,
        currentChangeCount: Int,
        currentText: String?,
        requiredStableObservations: Int
    ) -> PasteboardCopySettleDecision {
        guard let copiedText else {
            guard currentChangeCount != originalChangeCount, let currentText else {
                return .waiting
            }

            self.copiedText = currentText
            lastObservedChangeCount = currentChangeCount
            stableObservationCount = 0
            return .waiting
        }

        guard let currentText else {
            lastObservedChangeCount = currentChangeCount
            stableObservationCount = 0
            return .waiting
        }

        guard currentText == copiedText else {
            return .preserveCurrentClipboard(text: copiedText)
        }

        guard currentChangeCount == lastObservedChangeCount else {
            lastObservedChangeCount = currentChangeCount
            stableObservationCount = 0
            return .waiting
        }

        stableObservationCount += 1
        let required = max(1, requiredStableObservations)
        guard stableObservationCount >= required else {
            return .waiting
        }

        return .ready(text: copiedText, expectedChangeCount: currentChangeCount)
    }

    func timeoutDecision() -> PasteboardCopySettleDecision {
        guard let copiedText else { return .unavailable }
        return .preserveCurrentClipboard(text: copiedText)
    }
}
