import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import Lampo

@MainActor
struct ClipboardBridgeTests {
    let pasteboard = MockPasteboard()

    @Test func copySelectionRestoresTheUserClipboard() async {
        pasteboard.setString("user's clipboard")
        pasteboard.extra = ["public.png": Data([1, 2, 3])]
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        keystrokes.selectedText = "selected words"

        let text = await makeBridge(pasteboard, keystrokes).copySelection()

        #expect(text == "selected words")
        #expect(pasteboard.contents == "user's clipboard")
        #expect(pasteboard.extra == ["public.png": Data([1, 2, 3])])
        #expect(keystrokes.posted == [.copy])
    }

    @Test func copyWithNothingSelectedReturnsNilAndLeavesClipboard() async {
        pasteboard.setString("keep me")
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        let before = pasteboard.changeCount

        #expect(await makeBridge(pasteboard, keystrokes).copySelection() == nil)
        #expect(pasteboard.contents == "keep me")
        #expect(pasteboard.changeCount == before)
    }

    @Test func pasteIsSingleAndRestores() async {
        pasteboard.setString("original")
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)

        await makeBridge(pasteboard, keystrokes).paste("new text")

        #expect(keystrokes.posted == [.paste])
        #expect(keystrokes.pastedTexts == ["new text"])
        #expect(pasteboard.transientWrites == ["new text"])
        #expect(pasteboard.contents == "original")
    }

    @Test func pasteDoesNotClobberANewerClipboard() async {
        pasteboard.setString("original")
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        let pb = pasteboard
        let bridge = ClipboardBridge(pasteboard: pb, keystrokes: keystrokes, sleep: { _ in
            pb.externalWrite("copied meanwhile")
        })
        await bridge.paste("new text")
        #expect(pasteboard.contents == "copied meanwhile")
    }

    @Test func emptyClipboardStaysEmpty() async {
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        keystrokes.selectedText = "x"
        _ = await makeBridge(pasteboard, keystrokes).copySelection()
        #expect(pasteboard.contents == nil)
    }

    @Test func waitsForHotkeyModifiersToBeReleased() async {
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        keystrokes.heldModifierChecks = 3
        keystrokes.selectedText = "x"
        _ = await makeBridge(pasteboard, keystrokes).copySelection()
        #expect(keystrokes.heldModifierChecks == 0)
        #expect(keystrokes.posted == [.copy])
    }
}

@MainActor
struct SelectionServiceTests {
    let pasteboard = MockPasteboard()
    let accessibility = MockAccessibility()

    func service(_ keystrokes: MockKeystrokes) -> SelectionService {
        SelectionService(accessibility: accessibility, clipboard: makeBridge(pasteboard, keystrokes),
                         frontmostApp: { .textEdit })
    }

    @Test func prefersAccessibility() async throws {
        accessibility.selectedText = "via AX"
        accessibility.bounds = CGRect(x: 10, y: 20, width: 30, height: 14)
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        let selection = try #require(await service(keystrokes).readSelection(allowClipboardFallback: true))
        #expect(selection.text == "via AX")
        #expect(selection.source == .accessibility)
        #expect(selection.anchor == CGRect(x: 10, y: 20, width: 30, height: 14))
        #expect(selection.app == .textEdit)
        #expect(keystrokes.posted.isEmpty)
    }

    @Test func fallsBackToClipboard() async throws {
        pasteboard.setString("mine")
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        keystrokes.selectedText = "from Electron"
        let selection = try #require(await service(keystrokes).readSelection(allowClipboardFallback: true))
        #expect(selection.text == "from Electron")
        #expect(selection.source == .clipboard)
        #expect(selection.element == nil)
        #expect(pasteboard.contents == "mine")
    }

    @Test func noFallbackWhenNotAllowed() async {
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        keystrokes.selectedText = "x"
        #expect(await service(keystrokes).readSelection(allowClipboardFallback: false) == nil)
        #expect(keystrokes.posted.isEmpty)
    }

    @Test func nothingWithoutPermission() async {
        accessibility.isTrusted = false
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        keystrokes.selectedText = "x"
        #expect(await service(keystrokes).readSelection(allowClipboardFallback: true) == nil)
        #expect(keystrokes.posted.isEmpty)
    }

    @Test func whitespaceOnlyIsNoSelection() async {
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        keystrokes.selectedText = "  \n "
        #expect(await service(keystrokes).readSelection(allowClipboardFallback: true) == nil)
    }
}

@MainActor
struct OutputServiceTests {
    let pasteboard = MockPasteboard()
    let accessibility = MockAccessibility()

    func makeSelection(withElement: Bool) -> SelectionContext {
        SelectionContext(text: "old", app: .textEdit, anchor: nil,
                         element: withElement ? AXElementHandle(AXUIElementCreateSystemWide()) : nil,
                         source: withElement ? .accessibility : .clipboard)
    }

    func service(_ keystrokes: MockKeystrokes) -> OutputService {
        OutputService(accessibility: accessibility, clipboard: makeBridge(pasteboard, keystrokes),
                      pasteboard: pasteboard, activate: { _ in })
    }

    @Test func replacesThroughAccessibility() async {
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        let method = await service(keystrokes).replaceSelection("new", in: makeSelection(withElement: true))
        #expect(method == .accessibility)
        #expect(accessibility.replacements == ["new"])
        #expect(keystrokes.posted.isEmpty)
    }

    @Test func fallsBackToOnePasteAndRestoresClipboard() async {
        pasteboard.setString("user")
        accessibility.replaceSucceeds = false
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        let method = await service(keystrokes).replaceSelection("new", in: makeSelection(withElement: true))
        #expect(method == .paste)
        #expect(keystrokes.posted == [.paste])
        #expect(keystrokes.pastedTexts == ["new"])
        #expect(pasteboard.contents == "user")
    }

    @Test func clipboardSelectionsArePasted() async {
        let keystrokes = MockKeystrokes(pasteboard: pasteboard)
        let method = await service(keystrokes).replaceSelection("new", in: makeSelection(withElement: false))
        #expect(method == .paste)
        #expect(accessibility.replacements.isEmpty)
    }
}
