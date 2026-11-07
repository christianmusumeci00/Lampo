import CoreGraphics
import Foundation

/// Text selected in another app, plus what's needed to write back into it.
struct SelectionContext: Identifiable {
    enum Source: Equatable {
        case accessibility
        case clipboard
    }

    let id = UUID()
    var text: String
    var app: SourceApp?
    /// Selection (or focused element) rectangle in Cocoa screen coordinates.
    var anchor: CGRect?
    var element: AXElementHandle?
    var source: Source

    var wordCount: Int { TextMetrics.wordCount(text) }
}

/// Context attached to a panel question, shown as a removable chip.
enum ContextItem: Identifiable {
    case selection(SelectionContext)
    case clipboard(String)

    var id: String {
        switch self {
        case .selection(let selection): return "selection-\(selection.id)"
        case .clipboard: return "clipboard"
        }
    }

    var isSelection: Bool {
        if case .selection = self { return true }
        return false
    }
}

enum TextMetrics {
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
