// SPDX-License-Identifier: MIT

import SwiftUI
import SwimWorkoutKit

#if canImport(UIKit)
import UIKit
/// `UIFont` on UIKit platforms, `NSFont` on macOS.
public typealias PlatformFont = UIFont
/// `UIColor` on UIKit platforms, `NSColor` on macOS.
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
#endif

/// Turns SwimText into colored, attributed text using a ``SwimTextTheme``.
///
/// Two outputs, one tokenization (``SwimTextLexer``):
/// - ``attributedString(_:theme:font:)`` returns a SwiftUI `AttributedString`
///   for `Text` — available on every platform, including watchOS.
/// - ``nsAttributedString(_:theme:font:)`` returns an `NSAttributedString` for
///   `UITextView` / `NSTextView` (used by ``SwimTextView``).
public enum SwimTextHighlighter {

    // MARK: - SwiftUI

    /// A highlighted `AttributedString`, ready for `Text(_:)`.
    public static func attributedString(
        _ text: String,
        theme: SwimTextTheme = .standard,
        font: Font = .system(.callout, design: .monospaced)
    ) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = font
        attributed.foregroundColor = theme.plain

        let characters = attributed.characters
        let emphasized = font.weight(.semibold)
        for token in SwimTextLexer.tokens(in: text) {
            let start = text.distance(from: text.startIndex, to: token.range.lowerBound)
            let length = text.distance(from: token.range.lowerBound, to: token.range.upperBound)
            let lower = characters.index(characters.startIndex, offsetBy: start)
            let upper = characters.index(lower, offsetBy: length)
            attributed[lower..<upper].foregroundColor = theme.color(for: token.kind)
            if theme.isEmphasized(token.kind) {
                attributed[lower..<upper].font = emphasized
            }
        }
        return attributed
    }

    // MARK: - Platform (AppKit / UIKit)

    #if canImport(UIKit) || canImport(AppKit)

    /// The default monospaced font, sized to the dynamic-type Callout style.
    public static var defaultFont: PlatformFont {
        #if canImport(UIKit)
        let size = UIFont.preferredFont(forTextStyle: .callout).pointSize
        return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #else
        let size = NSFont.preferredFont(forTextStyle: .callout).pointSize
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #endif
    }

    /// A highlighted `NSAttributedString` for text-view backing stores.
    public static func nsAttributedString(
        _ text: String,
        theme: SwimTextTheme = .standard,
        font: PlatformFont = SwimTextHighlighter.defaultFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        result.addAttribute(.font, value: font, range: full)
        result.addAttribute(.foregroundColor, value: PlatformColor(theme.plain), range: full)

        let emphasized = PlatformFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold)
        for token in SwimTextLexer.tokens(in: text) {
            let nsRange = NSRange(token.range, in: text)
            result.addAttribute(.foregroundColor, value: PlatformColor(theme.color(for: token.kind)), range: nsRange)
            if theme.isEmphasized(token.kind) {
                result.addAttribute(.font, value: emphasized, range: nsRange)
            }
        }
        return result
    }

    #endif
}
