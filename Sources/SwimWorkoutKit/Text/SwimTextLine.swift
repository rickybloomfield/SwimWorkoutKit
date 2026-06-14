// SPDX-License-Identifier: MIT

import Foundation

/// Line-level SwimText: parse or print a single set line. Powers quick-entry
/// editing UIs ("type it like a coach") on top of the document-level parser.
public enum SwimTextLine {

    /// Parses one set line ("4x50 free desc 1-4 @1:00/1:10 | note").
    /// Returns nil when the line doesn't start with a distance.
    public static func parseSet(_ line: String, groups: [SpeedGroup]) -> SwimSet? {
        SetLineParser.parse(line.trimmingCharacters(in: .whitespaces), groups: groups)
    }

    /// Canonical SwimText for a single set.
    public static func printSet(_ set: SwimSet) -> String {
        SwimTextPrinter.printSet(set)
    }
}
