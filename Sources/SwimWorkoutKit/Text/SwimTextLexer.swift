// SPDX-License-Identifier: MIT

import Foundation

/// A semantic span of SwimText: a range of the source string plus what it means.
///
/// Produced by ``SwimTextLexer`` and consumed by syntax highlighters (see
/// `SwimWorkoutKitUI`). The lexer is UI-free on purpose — it only recognizes
/// *what* a span is; rendering decides how it looks.
public struct SwimTextToken: Sendable, Equatable {
    public let range: Range<String.Index>
    public let kind: SwimTextTokenKind

    public init(range: Range<String.Index>, kind: SwimTextTokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// What a ``SwimTextToken`` represents. Mirrors the elements the
/// ``SwimTextParser`` recognizes, so highlighting and parsing stay in step.
public enum SwimTextTokenKind: Sendable, Equatable {
    case title                       // "# Friday — Sprint"
    case section(name: String)       // "== Warmup: 300" (name drives section color)
    case metadataKey                 // "course:" in "course: scy"
    case metadataValue               // "scy" in "course: scy"
    case repsDistance                // "4x50", "8 x 25", "300"
    case stroke(Stroke)              // free, back, fly, im…
    case activity(Activity)          // kick, pull, drill…
    case effortLevel(EffortLevel)    // easy, fast, sprint, max…
    case effortShape(EffortShape)    // build, descend, ascend…
    case percent                     // "90%", "75-80%"
    case equipment(Equipment)        // fins, paddles, buoy…
    case sendoff                     // "@1:30/1:45/2:00"
    case rest                        // "r:20", "r1:00"
    case time                        // a bare clock value, e.g. ":40" in a hint
    case note                        // "| free text", "> remember your fins"
    case structure                   // repeat markers "3x {", "}", "round 2:", "rest"
}

/// Tokenizes SwimText into colorable spans without ever rejecting input.
///
/// `SwimTextLexer` is intentionally line-oriented and forgiving: it recognizes
/// the SwimText vocabulary a coach actually writes (see `Spec/notation.md`) and
/// leaves everything it doesn't understand untouched, so a highlighter can dim
/// it as plain text. It shares the keyword tables with ``SwimTextParser`` so the
/// two never drift.
///
/// ```swift
/// let tokens = SwimTextLexer.tokens(in: "4x50 free fast @:40")
/// // → repsDistance "4x50", stroke "free", effortLevel "fast", sendoff "@:40"
/// ```
public enum SwimTextLexer {

    /// All tokens in `text`, in source order, with ranges valid for `text`.
    public static func tokens(in text: String) -> [SwimTextToken] {
        var tokens: [SwimTextToken] = []
        var lineStart = text.startIndex
        while true {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            tokenizeLine(text[lineStart..<lineEnd], into: &tokens)
            if lineEnd == text.endIndex { break }
            lineStart = text.index(after: lineEnd)
        }
        return tokens
    }

    // MARK: - Line classification

    private static let metadataKeys: Set<String> = [
        "date", "author", "team", "course", "categories", "tags", "total", "groups", "notes",
    ]

    private static func tokenizeLine(_ line: Substring, into tokens: inout [SwimTextToken]) {
        guard let first = line.firstIndex(where: { !$0.isWhitespace }),
              let lastNonSpace = line.lastIndex(where: { !$0.isWhitespace })
        else { return }
        let body = line[first..<line.index(after: lastNonSpace)]
        // ```fences and code markers the parser drops — render as plain text.
        if body.hasPrefix("```") { return }

        // Title: "# …"
        if body.hasPrefix("#") {
            tokens.append(.init(range: body.startIndex..<body.endIndex, kind: .title))
            return
        }

        // Section: "== Warmup: 300"
        if body.hasPrefix("==") {
            var name = body.drop(while: { $0 == "=" }).trimmingCharacters(in: .whitespaces)
            if let colon = name.lastIndex(of: ":"),
               Int(name[name.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: "")) != nil {
                name = String(name[..<colon]).trimmingCharacters(in: .whitespaces)
            }
            tokens.append(.init(range: body.startIndex..<body.endIndex, kind: .section(name: name)))
            return
        }

        // Section header without the "==" marker ("Cool Down: 200"), matching
        // the parser so typed sections highlight the same as marked ones.
        if let name = bareSectionName(body) {
            tokens.append(.init(range: body.startIndex..<body.endIndex, kind: .section(name: name)))
            return
        }

        // Explicit note: "> …"
        if body.hasPrefix(">") {
            tokens.append(.init(range: body.startIndex..<body.endIndex, kind: .note))
            return
        }

        // Metadata: "course: scy" — only the recognized keys.
        if let colon = body.firstIndex(of: ":") {
            let key = body[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if metadataKeys.contains(key) {
                tokens.append(.init(range: body.startIndex..<colon, kind: .metadataKey))
                let valueStart = body.index(after: colon)
                if let v = body[valueStart...].firstIndex(where: { !$0.isWhitespace }) {
                    tokens.append(.init(range: v..<body.endIndex, kind: .metadataValue))
                }
                return
            }
        }

        // Repeat open: "3x {", "4/3x {", "2 x { | note"
        if body.first?.isNumber == true, let brace = body.firstMatch(of: /^\d[^{]*[x×]\s*\{/) {
            tokens.append(.init(range: brace.range, kind: .structure))
            scanRemainderForNote(body[brace.range.upperBound...], into: &tokens)
            return
        }

        // Repeat close: "}", "} | note"
        if body.hasPrefix("}") {
            let close = body.index(after: body.startIndex)
            tokens.append(.init(range: body.startIndex..<close, kind: .structure))
            scanRemainderForNote(body[close...], into: &tokens)
            return
        }

        // Per-round: "round 2: back and free"
        if let round = body.firstMatch(of: /^rounds?\s+(?:\d+(?:-\d+)?|odd|even)\s*:/.ignoresCase()) {
            tokens.append(.init(range: round.range, kind: .structure))
            scanGeneric(body[round.range.upperBound...], into: &tokens)
            return
        }

        // Standalone rest: "rest 1:00 | between sets"
        if let rest = body.firstMatch(of: /^rest\b/.ignoresCase()) {
            tokens.append(.init(range: rest.range, kind: .structure))
            scanGeneric(body[rest.range.upperBound...], into: &tokens)
            return
        }

        // Set line (or anything else): emit a leading reps×distance, then scan.
        var remainder = body
        if let lead = body.firstMatch(of: /^(?:\d+\s*[x×]\s*)?\d+(?=$|[\s,;(@])/) {
            tokens.append(.init(range: lead.range, kind: .repsDistance))
            remainder = body[lead.range.upperBound...]
        }
        scanGeneric(remainder, into: &tokens)
    }

    /// After "}" or "Nx {", a trailing "| note" is the only thing left to color.
    private static func scanRemainderForNote(_ s: Substring, into tokens: inout [SwimTextToken]) {
        guard let bar = s.firstIndex(of: "|") else { return }
        tokens.append(.init(range: bar..<s.endIndex, kind: .note))
    }

    // MARK: - Word-level scan

    private static func scanGeneric(_ s: Substring, into tokens: inout [SwimTextToken]) {
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]

            // "| note" — everything to end of line.
            if c == "|" {
                tokens.append(.init(range: i..<s.endIndex, kind: .note))
                return
            }

            // Separators carry no color.
            if c.isWhitespace || ",;/(){}".contains(c) {
                i = s.index(after: i)
                continue
            }

            // Send-off: "@1:30/1:45", "@:35", "@Lane".
            if c == "@" {
                var j = s.index(after: i)
                while j < s.endIndex, isSendoffChar(s[j]) { j = s.index(after: j) }
                tokens.append(.init(range: i..<j, kind: .sendoff))
                i = j
                continue
            }

            // Rest token: "r" directly followed by a clock value — "r:20", "r1:00", "r20s".
            if c == "r" || c == "R" {
                let next = s.index(after: i)
                if next < s.endIndex, s[next].isNumber || s[next] == ":" {
                    var j = next
                    while j < s.endIndex, s[j].isNumber || s[j] == ":" { j = s.index(after: j) }
                    if j < s.endIndex, s[j] == "m" || s[j] == "s" { j = s.index(after: j) }
                    tokens.append(.init(range: i..<j, kind: .rest))
                    i = j
                    continue
                }
            }

            // A word run — classify against the SwimText vocabulary.
            var j = i
            while j < s.endIndex, isWordChar(s[j]) { j = s.index(after: j) }
            if j == i {
                i = s.index(after: i)   // lone symbol (+, %, …) — skip
                continue
            }
            if let kind = classify(s[i..<j]) {
                tokens.append(.init(range: i..<j, kind: kind))
            }
            i = j
        }
    }

    /// The section name if `body` is a header written without "==" — e.g.
    /// "Cool Down: 200" or "Warmup". Mirrors `SwimTextParser.bareSectionHeader`.
    private static func bareSectionName(_ body: Substring) -> String? {
        var name = String(body)
        if let colon = body.firstIndex(of: ":") {
            name = String(body[..<colon]).trimmingCharacters(in: .whitespaces)
            let after = body[body.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: "")
            if !after.isEmpty {
                let firstToken = after.split(separator: " ").first.map(String.init) ?? after
                guard Int(firstToken) != nil else { return nil }
            }
        }
        guard SwimTextParser.knownSectionNames.contains(name.lowercased()) else { return nil }
        return name
    }

    private static func isSendoffChar(_ c: Character) -> Bool {
        c.isNumber || ":+/.".contains(c) || "sSLlAaNnEe".contains(c)
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || "%-:.".contains(c)
    }

    private static func classify(_ word: Substring) -> SwimTextTokenKind? {
        let lower = word.lowercased()
        if let stroke = KeywordTables.stroke[lower] { return .stroke(stroke) }
        if let activity = KeywordTables.activity[lower] { return .activity(activity) }
        if let level = KeywordTables.level[lower] { return .effortLevel(level) }
        if let shape = KeywordTables.shape[lower] { return .effortShape(shape) }
        if let equipment = KeywordTables.equipment[lower] { return .equipment(equipment) }
        if word.wholeMatch(of: /\d+(?:-\d+)?%/) != nil { return .percent }
        if word.wholeMatch(of: /:?\d{1,2}:\d{2}|:\d{2}/) != nil { return .time }
        return nil
    }
}
