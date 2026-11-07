import AppKit

/// Minimal pasteboard abstraction so output and clipboard-restore logic is testable.
@MainActor
protocol PasteboardClient: AnyObject {
    var changeCount: Int { get }
    func string() -> String?
    func setString(_ string: String)
}

@MainActor
final class SystemPasteboard: PasteboardClient {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func string() -> String? { pasteboard.string(forType: .string) }

    func setString(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
