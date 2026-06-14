// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// Turns raw OCR line output into SwimText the parser can structure.
///
/// This is deliberately a *text* pass (no vision dependencies) so it is
/// unit-testable and shared by the app pipeline and the `swimocr` CLI.
/// It only rewrites what it is confident about; everything else passes
/// through untouched — the parser keeps unknown lines as notes, and the
/// review UI lets the swimmer fix the rest.
public enum OCRTextAssembler {

    public static func assembleSwimText(from rawLines: [String]) -> String {
        var output: [String] = []
        var sawTitle = false
        var sawContent = false
        var openRepeat = false
        var statedTotal: Int?

        func closeRepeatIfNeeded() {
            if openRepeat {
                output.append("}")
                openRepeat = false
            }
        }

        func process(_ line: String) {
            // Section header?
            if let (header, remainder) = sectionHeaderWithRemainder(from: line) {
                closeRepeatIfNeeded()
                // Two-column docs put the workout title on the first header
                // row ("Warmup: 300        Friday — Sprint").
                if let remainder, !sawTitle, !sawContent, isLikelyTitle(remainder) {
                    output.append("# \(remainder)")
                    sawTitle = true
                    output.append(header)
                    sawContent = true
                    return
                }
                output.append(header)
                sawContent = true
                if let remainder {
                    process(remainder)
                }
                return
            }
            // Bare repeat marker ("2x", "3 x", "8 x thru", "2x thru:")?
            if let rounds = repeatMarker(from: line) {
                closeRepeatIfNeeded()
                output.append("\(rounds)x {")
                openRepeat = true
                sawContent = true
                return
            }
            // Title: first short, letter-led line before any content.
            if !sawTitle, !sawContent, isLikelyTitle(line) {
                output.append("# \(line)")
                sawTitle = true
                return
            }
            sawContent = true
            output.append(line)
        }

        for rawLine in rawLines {
            let line = normalize(rawLine)
            if line.isEmpty { continue }

            // Stated total → hoisted to header metadata (the parser reads
            // metadata only before the first content line).
            if let (before, total) = extractTotal(from: line) {
                if let before, !before.isEmpty {
                    process(before)
                }
                statedTotal = statedTotal ?? total
                continue
            }

            process(line)
        }

        closeRepeatIfNeeded()
        if let statedTotal {
            let insertAt = output.first?.hasPrefix("# ") == true ? 1 : 0
            output.insert("total: \(statedTotal)", at: insertAt)
        }
        return output.joined(separator: "\n") + "\n"
    }

    // MARK: - Fragment ordering

    /// A recognized text fragment with its normalized bounding box
    /// (Vision convention: origin bottom-left, unit square).
    public struct Fragment: Sendable {
        public var text: String
        public var bounds: CGRect

        public init(text: String, bounds: CGRect) {
            self.text = text
            self.bounds = bounds
        }
    }

    /// Orders OCR fragments into reading order: rows top-to-bottom, fragments
    /// left-to-right within a row. Fragments whose vertical centers fall
    /// within half a typical line height are considered the same row
    /// (handles "Warmup: 300        Friday — Sprint" two-column headers).
    public static func orderLines(_ fragments: [Fragment]) -> [String] {
        guard !fragments.isEmpty else { return [] }
        let heights = fragments.map { $0.bounds.height }.sorted()
        let typicalHeight = heights[heights.count / 2]
        let tolerance = max(typicalHeight * 0.6, 0.004)

        let sorted = fragments.sorted { $0.bounds.midY > $1.bounds.midY }
        var rows: [[Fragment]] = []
        for fragment in sorted {
            if var lastRow = rows.last,
               let anchor = lastRow.first,
               abs(anchor.bounds.midY - fragment.bounds.midY) < tolerance {
                lastRow.append(fragment)
                rows[rows.count - 1] = lastRow
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            row.sorted { $0.bounds.minX < $1.bounds.minX }
                .map { $0.text }
                .joined(separator: " ")
        }
    }

    // MARK: - Normalization

    static func normalize(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        let replacements: [(String, String)] = [
            ("×", "x"), ("✕", "x"), ("✗", "x"),
            ("\u{2018}", "'"), ("\u{2019}", "'"),
            ("\u{201C}", "\""), ("\u{201D}", "\""),
            ("·", " "), ("•", " "),
            ("‚", ","),
        ]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        // OCR often reads "@ 1:30" with a space.
        text = text.replacingOccurrences(of: "@ ", with: "@")
        // Collapse runs of whitespace.
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text
    }

    // MARK: - Recognizers

    // Shared with the SwimText parser so typed and scanned workouts recognize
    // the same section names (see `SwimTextParser.knownSectionNames`).
    private static let sectionNames = SwimTextParser.knownSectionNames

    /// "Warmup: 800", "Main Set: 2100", "cool down", "Stroke Work (2000 yd, 40 min)"
    static func sectionHeader(from line: String) -> String? {
        sectionHeaderWithRemainder(from: line)?.header
    }

    /// Like `sectionHeader`, but preserves trailing text from shared OCR rows
    /// ("Warmup: 300 Friday — Sprint" → header + "Friday — Sprint").
    static func sectionHeaderWithRemainder(from line: String) -> (header: String, remainder: String?)? {
        var working = line
        // Strip a parenthetical qualifier: "Warm Up (1000 yd, 20 min)".
        var parenthetical: String?
        if let match = working.firstMatch(of: /\(([^)]*)\)/) {
            parenthetical = String(match.1)
            working.removeSubrange(match.range)
            working = working.trimmingCharacters(in: .whitespaces)
        }

        var name = working
        var stated: Int?
        var remainder: String?
        if let colon = working.firstIndex(of: ":") {
            let after = working[working.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: "")
            name = String(working[..<colon]).trimmingCharacters(in: .whitespaces)
            // "Warmup: 600 or 800" → first number; anything after the
            // numeric part ("300 Friday — Sprint") is a co-resident line.
            var parts = after.split(separator: " ").map(String.init)
            if let first = parts.first, let value = Int(first) {
                stated = value
                parts.removeFirst()
                // Swallow "or 800" alternatives; keep real remainders.
                if parts.first?.lowercased() == "or", parts.count >= 2, Int(parts[1]) != nil {
                    parts.removeFirst(2)
                }
                remainder = parts.isEmpty ? nil : parts.joined(separator: " ")
            } else if !after.isEmpty {
                return nil
            }
        }

        guard sectionNames.contains(name.lowercased()) else { return nil }
        // Pull a stated distance out of "(1000 yd, 20 min)" when present.
        if stated == nil, let parenthetical,
           let match = parenthetical.firstMatch(of: /(\d{2,5})\s*(?:yd|m|meters|yards)/) {
            stated = Int(match.1)
        }
        if let stated {
            return ("== \(name): \(stated)", remainder)
        }
        return ("== \(name)", remainder)
    }

    // MARK: - Post-parse fixups

    /// Deck convention: a stated-but-empty section ("Cool Down: 100" with no
    /// item lines) means "swim that distance, your choice."
    public static func fillEmptyStatedSections(_ workout: Workout) -> Workout {
        var result = workout
        for index in result.sections.indices {
            let section = result.sections[index]
            guard let stated = section.statedDistance, stated > 0 else { continue }
            // Fill when nothing in the section actually swims a distance — not
            // only when it is literally empty. A stray note (a leftover word, a
            // code fence the model emitted) would otherwise make the section
            // look populated and silently drop its stated yardage.
            let swum = WorkoutCalculator.distance(of: section, group: nil, groups: result.groups)
            guard swum == 0 else { continue }
            result.sections[index].items.append(
                .set(SwimSet(
                    reps: 1, distance: stated, stroke: .choice,
                    effort: Effort(level: .easy)
                ))
            )
        }
        return result
    }

    /// "Total: 2800", "Total: 3400 or 3600" — possibly trailing another line.
    static func extractTotal(from line: String) -> (before: String?, total: Int)? {
        guard let match = line.firstMatch(of: /(?i)\btotal\s*:?\s*(\d[\d,]{2,5})/) else {
            return nil
        }
        let digits = String(match.1).replacingOccurrences(of: ",", with: "")
        guard let total = Int(digits) else { return nil }
        let before = String(line[line.startIndex..<match.range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        return (before.isEmpty ? nil : before, total)
    }

    /// "2x", "3 x", "2x thru", "8 x thru:", "2x:" — a line that is only a
    /// repeat marker. (Brace placement is heuristic; the review UI fixes
    /// misjudged extents.)
    static func repeatMarker(from line: String) -> Int? {
        guard let match = line.firstMatch(of: /^(\d{1,2})\s*[x]\s*(?:thru|through)?\s*:?\s*$/.ignoresCase()) else {
            return nil
        }
        return Int(match.1)
    }

    static func isLikelyTitle(_ line: String) -> Bool {
        guard line.count <= 48 else { return false }
        guard let first = line.first, first.isLetter || first == "#" else { return false }
        // A set line starts with a count/distance; a title doesn't.
        if line.firstMatch(of: /^\d/) != nil { return false }
        // Metadata-looking lines aren't titles.
        let lower = line.lowercased()
        for key in ["course:", "date:", "author:", "team:", "total:", "groups:"] {
            if lower.hasPrefix(key) { return false }
        }
        return true
    }
}
