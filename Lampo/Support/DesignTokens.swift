import SwiftUI

/// Single source of truth for Lampo's visual constants.
enum DesignTokens {
    /// Brand accent, #2F6FDE.
    static let accent = Color(red: 0x2F / 255, green: 0x6F / 255, blue: 0xDE / 255)

    enum Panel {
        static let width: CGFloat = 700
        static let cornerRadius: CGFloat = 22
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 18
        static let inputFontSize: CGFloat = 21
        static let bodyFontSize: CGFloat = 15
        /// Line height 1.5 × body size → extra spacing of half the font size.
        static let bodyLineSpacing: CGFloat = bodyFontSize * 0.5
        /// Distance of the panel's top edge from the top of the screen.
        static let topOffsetFraction: CGFloat = 0.2
        static let maxResponseHeight: CGFloat = 440
        /// Transparent margin around the glass so the soft shadow is not clipped.
        static let shadowMargin: CGFloat = 36
        static let shadowRadius: CGFloat = 28
    }

    enum Badge {
        static let height: CGFloat = 24
        static let fontSize: CGFloat = 12
    }

    enum Button {
        static let height: CGFloat = 34
        static let cornerRadius: CGFloat = 9
    }

    enum Dictation {
        /// Panel width, shadow margins included.
        static let width: CGFloat = 600
        static let shadowMargin: CGFloat = 24
        /// Distance of the capsule's panel from the bottom of the visible screen (above the Dock).
        static let bottomOffset: CGFloat = 40
    }

    enum Lens {
        static let width: CGFloat = 660
        static let cornerRadius: CGFloat = 16
        static let chipHeight: CGFloat = 32
        static let previewCornerRadius: CGFloat = 10
    }
}
