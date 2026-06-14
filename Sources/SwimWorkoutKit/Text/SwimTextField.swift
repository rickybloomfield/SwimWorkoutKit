// SPDX-License-Identifier: MIT

import Foundation

/// A span of SwimText whose value can be swapped from a fixed list — a body
/// keyword (stroke, activity, equipment, effort level/shape) or a document
/// metadata value (pool course, categories, date). Editors use it to offer an
/// in-place picker without disturbing free-text editing.
///
/// Resolution is pure and UI-free (and unit-tested). The live editor in
/// `SwimWorkoutKitUI` maps these to a keyboard context bar: when the caret sits
/// on a line, it surfaces a small pop-up list for each swappable field there.
public struct SwimTextField: Sendable, Equatable {

    /// The axis a field swaps along. Drives both the option list and, for
    /// metadata, how the replacement is written back ("key: value").
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case stroke
        case activity
        case equipment
        case effortLevel
        case effortShape
        case course        // pool size: scy / scm / lcm
        case categories    // comma list (multi-select)
        case date          // calendar value

        /// Document-level metadata written as a "key: value" line, as opposed to
        /// a keyword inside a set line. Metadata swaps rewrite the value clause;
        /// body swaps replace just the token.
        public var isMetadata: Bool {
            switch self {
            case .course, .categories, .date: return true
            case .stroke, .activity, .equipment, .effortLevel, .effortShape: return false
            }
        }
    }

    /// The span whose text a swap replaces. Empty (an insertion point at the end
    /// of the line) for an unset metadata placeholder like `date:`.
    public let range: Range<String.Index>
    public let kind: Kind
    /// The current value text — "free", "scy", "sprint, distance" — or "" when
    /// the metadata value is an unfilled placeholder.
    public let currentRaw: String

    public init(range: Range<String.Index>, kind: Kind, currentRaw: String) {
        self.range = range
        self.kind = kind
        self.currentRaw = currentRaw
    }
}

/// Locates ``SwimTextField``s in SwimText and lists their options.
///
/// Shares ``SwimTextLexer`` for body keywords, so highlighting and swapping
/// never drift, and reads metadata lines directly to associate a value with its
/// key (the lexer types every metadata value the same).
public enum SwimTextFieldResolver {

    /// Every swappable field in `text`, in source order.
    public static func fields(in text: String) -> [SwimTextField] {
        var result: [SwimTextField] = []

        // Body keywords — the lexer already typed and located them.
        for token in SwimTextLexer.tokens(in: text) {
            let kind: SwimTextField.Kind?
            switch token.kind {
            case .stroke: kind = .stroke
            case .activity: kind = .activity
            case .equipment: kind = .equipment
            case .effortLevel: kind = .effortLevel
            case .effortShape: kind = .effortShape
            default: kind = nil
            }
            if let kind {
                result.append(SwimTextField(range: token.range, kind: kind,
                                            currentRaw: String(text[token.range])))
            }
        }

        // Metadata values that have pickers (course / categories / date).
        forEachLine(text) { line in
            if let field = metadataField(in: line) { result.append(field) }
        }

        result.sort { $0.range.lowerBound < $1.range.lowerBound }
        return result
    }

    /// The swappable fields on the line that contains `caret` — what the editor
    /// surfaces while the cursor sits on that line.
    public static func fields(in text: String, onLineContaining caret: String.Index) -> [SwimTextField] {
        guard let line = lineRange(in: text, containing: caret) else { return [] }
        return fields(in: text).filter {
            $0.range.lowerBound >= line.lowerBound && $0.range.lowerBound <= line.upperBound
        }
    }

    /// The single field whose value contains `caret`, if any (inclusive of the
    /// span's end so a caret just after a token still resolves it).
    public static func field(in text: String, at caret: String.Index) -> SwimTextField? {
        fields(in: text).first { (
            $0.range.lowerBound...$0.range.upperBound).contains(caret)
        }
    }

    /// Canonical option tokens for a swappable `kind`, alphabetically ordered so
    /// the menus read predictably. The raw strings match what ``SwimTextPrinter``
    /// emits, so a swap round-trips cleanly — with one deliberate exception:
    /// `swim` (the implicit-default activity, which the lexer still recognizes
    /// and the bar shows) is offered so the menu reflects a detected `swim`, even
    /// though the printer omits it on a reprint. The meaning is preserved either
    /// way, since absence of an activity already means swim. `steady` (the
    /// default shape) is left out for the same reason but isn't commonly written.
    ///
    /// Sorting by raw token matches sorting by display label for every list, so
    /// the on-screen order is alphabetical too. `.date` returns none — editors
    /// offer a calendar instead.
    public static func rawOptions(for kind: SwimTextField.Kind) -> [String] {
        let options: [String]
        switch kind {
        case .stroke:      options = ["free", "back", "breast", "fly", "im", "imo", "rimo", "stroke", "choice"]
        case .activity:    options = ["swim", "kick", "pull", "drill", "scull"]
        case .equipment:   options = Equipment.allCases.map(\.rawValue)
        case .effortLevel: options = EffortLevel.allCases.map(\.rawValue)
        case .effortShape: options = ["build", "descend", "ascend", "ns", "vs"]
        case .course:      options = ["scy", "scm", "lcm"]
        case .categories:  options = WorkoutCategory.allCases.map(\.rawValue)
        case .date:        return []
        }
        return options.sorted()
    }

    // MARK: - Adding modifiers

    /// Body modifier kinds that can still be *added* to the set line at `caret`
    /// (a line leading with reps×distance) — those not already present, in a
    /// natural writing order. Empty for non-set lines (metadata, headers, blank).
    public static func addableModifiers(in text: String, onLineContaining caret: String.Index) -> [SwimTextField.Kind] {
        guard let line = lineRange(in: text, containing: caret), isSetLine(text[line]) else { return [] }
        let present = Set(fields(in: text, onLineContaining: caret).map(\.kind))
        return [.stroke, .activity, .equipment, .effortShape, .effortLevel].filter { !present.contains($0) }
    }

    /// Where and what to insert to add the `raw` modifier token to the set line
    /// at `caret`: just before the line's send-off / rest / note (or at the end of
    /// its content), with surrounding spaces normalized. Nil for non-set lines.
    public static func modifierInsertion(
        of raw: String, in text: String, onLineContaining caret: String.Index
    ) -> (index: String.Index, replacement: String)? {
        guard let line = lineRange(in: text, containing: caret), isSetLine(text[line]) else { return nil }
        let at = insertionBoundary(in: text, line: line)
        var replacement = raw
        if at > text.startIndex, !text[text.index(before: at)].isWhitespace { replacement = " " + replacement }
        if at < text.endIndex, !text[at].isWhitespace { replacement += " " }
        return (at, replacement)
    }

    /// Where and what to insert to start an inline note (the `|` delimiter) on the
    /// set line at `caret`. Nil for non-set lines or lines that already have a note.
    public static func commentInsertion(
        in text: String, onLineContaining caret: String.Index
    ) -> (index: String.Index, replacement: String)? {
        guard let line = lineRange(in: text, containing: caret), isSetLine(text[line]),
              !text[line].contains("|")
        else { return nil }
        return (insertionBoundary(in: text, line: line, beforeInterval: false), " | ")
    }

    /// True when `line` leads with a reps×distance (a swappable/annotatable set).
    static func isSetLine(_ line: Substring) -> Bool {
        SwimTextLexer.tokens(in: String(line)).contains {
            if case .repsDistance = $0.kind { return true }
            return false
        }
    }

    /// The index to insert a trailing token at: before the earliest send-off /
    /// rest / note on the line when `beforeInterval`, else the end of the line's
    /// content. Either way past any trailing whitespace.
    private static func insertionBoundary(
        in text: String, line: Range<String.Index>, beforeInterval: Bool = true
    ) -> String.Index {
        var boundary = trimmedEnd(of: text, line: line)
        guard beforeInterval else { return boundary }
        for token in SwimTextLexer.tokens(in: text) {
            guard token.range.lowerBound >= line.lowerBound,
                  token.range.lowerBound < line.upperBound else { continue }
            switch token.kind {
            case .sendoff, .rest, .note:
                if token.range.lowerBound < boundary { boundary = token.range.lowerBound }
            default: break
            }
        }
        return boundary
    }

    /// `line.upperBound` backed up past any trailing whitespace.
    private static func trimmedEnd(of text: String, line: Range<String.Index>) -> String.Index {
        var end = line.upperBound
        while end > line.lowerBound, text[text.index(before: end)].isWhitespace {
            end = text.index(before: end)
        }
        return end
    }

    // MARK: - Metadata

    private static let pickerMetadataKeys: [String: SwimTextField.Kind] = [
        "course": .course, "categories": .categories, "date": .date,
    ]

    /// The picker field for a `key: value` metadata line, or nil. The value span
    /// skips a single leading space after the colon, and trailing whitespace, so
    /// `currentRaw` is the bare value.
    private static func metadataField(in line: Substring) -> SwimTextField? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard let kind = pickerMetadataKeys[key] else { return nil }
        var valueStart = line.index(after: colon)
        if valueStart < line.endIndex, line[valueStart] == " " {
            valueStart = line.index(after: valueStart)
        }
        var valueEnd = line.endIndex
        while valueEnd > valueStart, line[line.index(before: valueEnd)].isWhitespace {
            valueEnd = line.index(before: valueEnd)
        }
        let range = valueStart..<valueEnd
        return SwimTextField(range: range, kind: kind, currentRaw: String(line[range]))
    }

    // MARK: - Lines

    private static func forEachLine(_ text: String, _ body: (Substring) -> Void) {
        var start = text.startIndex
        while true {
            let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
            body(text[start..<end])
            if end == text.endIndex { break }
            start = text.index(after: end)
        }
    }

    private static func lineRange(in text: String, containing caret: String.Index) -> Range<String.Index>? {
        guard caret <= text.endIndex else { return nil }
        let start = text[..<caret].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let end = text[caret...].firstIndex(of: "\n") ?? text.endIndex
        return start..<end
    }
}
