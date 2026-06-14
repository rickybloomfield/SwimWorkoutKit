// SPDX-License-Identifier: MIT

import Foundation

/// Result of parsing SwimText. Lines that could not be understood become
/// note items *and* are reported here for review UIs.
public struct SwimTextParseResult: Sendable {
    public var document: SwimWorkoutDocument
    public var unparsedLines: [UnparsedLine]

    public struct UnparsedLine: Sendable, Equatable {
        public var lineNumber: Int
        public var text: String
    }
}

/// Parser for the SwimText notation (see `Spec/notation.md`).
///
/// Document shape:
/// ```
/// # Friday — Sprint
/// date: 2026-06-05
/// course: scy
/// categories: sprint
/// groups: A "Lanes 1-2" 1:15; B "Lanes 3-4" 1:25; C "Lanes 5-6" 1:40
/// total: 2800
///
/// == Warmup: 300
/// 3x100 as swim/kick/pull
/// == Main Set: 2400
/// 2x {
///   6x25 choice sprint @:35
///   100 kick easy r1:00
/// }
/// == Cool Down: 100
/// 100 choice easy
/// ```
public enum SwimTextParser {

    public static func parse(_ text: String) -> SwimTextParseResult {
        var workout = Workout()
        var unparsed: [SwimTextParseResult.UnparsedLine] = []

        var sections: [WorkoutSection] = []
        var currentSection: WorkoutSection?
        // Stack of open repeat blocks (supports nesting).
        var repeatStack: [RepeatBlock] = []
        var sawAnyContent = false

        func appendItem(_ item: WorkoutItem) {
            if !repeatStack.isEmpty {
                repeatStack[repeatStack.count - 1].items.append(item)
            } else {
                if currentSection == nil {
                    currentSection = WorkoutSection(name: "Workout")
                }
                currentSection?.items.append(item)
            }
        }

        func closeSection() {
            if let section = currentSection {
                sections.append(section)
                currentSection = nil
            }
        }

        let lines = text.components(separatedBy: .newlines)
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Models sometimes wrap their reply in a markdown code fence despite
            // the "output only SwimText" instruction. A stray ``` would become a
            // note item and — worse — defeat stated-only section filling by
            // making a trailing section look non-empty. Drop it before anything.
            if line.hasPrefix("```") { continue }
            let lineNumber = index + 1

            // Title
            if line.hasPrefix("# ") {
                workout.title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Section header
            if line.hasPrefix("==") {
                closeSection()
                var header = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                var stated: Int?
                if let colon = header.lastIndex(of: ":") {
                    let after = header[header.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if let value = Int(after.replacingOccurrences(of: ",", with: "")) {
                        stated = value
                        header = String(header[..<colon]).trimmingCharacters(in: .whitespaces)
                    }
                }
                currentSection = WorkoutSection(name: header, statedDistance: stated)
                sawAnyContent = true
                continue
            }

            // Section header without the "==" marker ("Cool Down: 200", "Warmup").
            // Recognized only for known section names so metadata and set lines
            // are unaffected; mirrors the photo-import normalization.
            if let bare = bareSectionHeader(line) {
                closeSection()
                currentSection = WorkoutSection(name: bare.name, statedDistance: bare.stated)
                sawAnyContent = true
                continue
            }

            // A stated total is a pre-calculated summary, never workout content.
            // Coaches often write it last ("total: 3000" under the cool down),
            // so hoist it to metadata wherever it lands — otherwise it falls to
            // the note fallback and gets stuck inside the trailing section.
            if let (key, value) = metadataLine(line), key == "total" {
                applyMetadata(key: key, value: value, to: &workout)
                continue
            }

            // Other metadata is only meaningful before content; afterwards lines may be sets/notes.
            if !sawAnyContent, let (key, value) = metadataLine(line) {
                applyMetadata(key: key, value: value, to: &workout)
                continue
            }

            // Repeat open: "3x {", "2 x {", "4/3x {"
            if let block = repeatOpen(line) {
                repeatStack.append(block)
                sawAnyContent = true
                continue
            }

            // Repeat close: "}" with optional "| note"
            if line.hasPrefix("}") {
                if var block = repeatStack.popLast() {
                    let remainder = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                    if remainder.hasPrefix("|") {
                        let note = String(remainder.dropFirst()).trimmingCharacters(in: .whitespaces)
                        block.note = block.note.map { "\($0); \(note)" } ?? note
                    }
                    appendItem(.repeatBlock(block))
                } else {
                    unparsed.append(.init(lineNumber: lineNumber, text: rawLine))
                }
                continue
            }

            // Per-round annotation inside a repeat: "round 2: Back and Free"
            if !repeatStack.isEmpty, let perRound = perRoundLine(line) {
                repeatStack[repeatStack.count - 1].perRound =
                    (repeatStack[repeatStack.count - 1].perRound ?? []) + [perRound]
                continue
            }

            // Standalone rest: "rest 1:00"
            if let rest = restLine(line) {
                appendItem(.rest(rest))
                sawAnyContent = true
                continue
            }

            // Explicit note
            if line.hasPrefix(">") {
                appendItem(.note(NoteItem(text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces))))
                sawAnyContent = true
                continue
            }

            // Rep-ladder: "6-4-2 x 50 stroke @:45-:50-:55" — descending rep
            // counts. Inside a repeat block whose round count matches the ladder
            // length, the counts are per-round (round 1 does 6×50, round 2 does
            // 4×50, …): collapse to the mean rep so the block multiplier lands
            // the right total. Standalone, expand into sequential sets.
            if let ladder = RepLadder.parse(line) {
                if let rounds = repeatStack.last?.rounds, rounds == ladder.counts.count {
                    let mean = Int((Double(ladder.counts.reduce(0, +)) / Double(ladder.counts.count)).rounded())
                    let synth = ladder.line(reps: max(1, mean), sendoffIndex: nil,
                                            extraNote: "reps \(ladder.countsText) by round")
                    if let set = SetLineParser.parse(synth, groups: workout.groups) {
                        appendItem(.set(set))
                        sawAnyContent = true
                        continue
                    }
                } else {
                    for (offset, count) in ladder.counts.enumerated() {
                        let synth = ladder.line(reps: count, sendoffIndex: offset, extraNote: nil)
                        if let set = SetLineParser.parse(synth, groups: workout.groups) {
                            appendItem(.set(set))
                        }
                    }
                    sawAnyContent = true
                    continue
                }
            }

            // Set line
            if let set = SetLineParser.parse(line, groups: workout.groups) {
                appendItem(.set(set))
                sawAnyContent = true
                continue
            }

            // Fallback: keep as note, report as unparsed.
            appendItem(.note(NoteItem(text: line)))
            unparsed.append(.init(lineNumber: lineNumber, text: rawLine))
            sawAnyContent = true
        }

        // Close any dangling repeats (tolerate missing "}").
        while var block = repeatStack.popLast() {
            if repeatStack.isEmpty {
                if currentSection == nil { currentSection = WorkoutSection(name: "Workout") }
                currentSection?.items.append(.repeatBlock(block))
            } else {
                let inner = block
                block = repeatStack.removeLast()
                block.items.append(.repeatBlock(inner))
                repeatStack.append(block)
            }
        }
        closeSection()

        workout.sections = sections
        // Auto-create groups when send-offs imply more groups than declared,
        // then drop any send-off that still points past the resolved lanes (a
        // per-rep ladder's extra times) so it can't reference a phantom group.
        ensureGroups(&workout)
        trimOrphanSendoffs(&workout)
        return SwimTextParseResult(document: SwimWorkoutDocument(workout: workout), unparsedLines: unparsed)
    }

    // MARK: - Metadata

    private static let metadataKeys: Set<String> = [
        "date", "author", "team", "course", "categories", "tags", "total", "groups", "notes",
    ]

    /// Section names recognized even when the coach omits the "==" marker — so a
    /// typed line like "Cool Down: 200" becomes a section, not a dropped note.
    /// Shared with ``OCRTextAssembler`` so typed and scanned workouts match.
    static let knownSectionNames: Set<String> = [
        "warmup", "warm up", "warm-up",
        "main set", "mainset",
        "cooldown", "cool down", "cool-down",
        "warmdown", "warm down", "warm-down",
        "preset", "pre set", "pre-set",
        "postset", "post set", "post-set",
        "stroke work", "kick set", "pull set", "sprint set", "test set",
    ]

    /// A section header written without the leading "==": "Cool Down: 200",
    /// "Warmup". Returns nil unless the name is a recognized section name and any
    /// value after the colon is numeric (so "course: scy" stays metadata).
    private static func bareSectionHeader(_ line: String) -> (name: String, stated: Int?)? {
        var name = line
        var stated: Int?
        if let colon = line.firstIndex(of: ":") {
            name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let after = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: "")
            if !after.isEmpty {
                // "200", "600 or 800" → first number; reject non-numeric values.
                let firstToken = after.split(separator: " ").first.map(String.init) ?? after
                guard let value = Int(firstToken) else { return nil }
                stated = value
            }
        }
        guard knownSectionNames.contains(name.lowercased()) else { return nil }
        return (name, stated)
    }

    private static func metadataLine(_ line: String) -> (key: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
        guard metadataKeys.contains(key) else { return nil }
        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func applyMetadata(key: String, value: String, to workout: inout Workout) {
        // An empty value (a placeholder like "date:" the user hasn't filled in)
        // leaves the field unset rather than storing an empty string.
        switch key {
        case "date": workout.date = value.isEmpty ? nil : value
        case "author": workout.author = value.isEmpty ? nil : value
        case "team": workout.team = value.isEmpty ? nil : value
        case "notes":
            guard !value.isEmpty else { break }
            workout.notes = workout.notes.map { "\($0)\n\(value)" } ?? value
        case "course":
            if let course = Course(label: value) {
                workout.course = course
            }
        case "categories":
            workout.categories = splitList(value)
        case "tags":
            workout.tags = splitList(value)
        case "total":
            let digits = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            workout.statedTotal = digits.first
        case "groups":
            workout.groups = parseGroups(value)
        default:
            break
        }
    }

    private static func splitList(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// `A "Lanes 1-2" 1:15; B "Lanes 3-4" 1:25; C`
    private static func parseGroups(_ value: String) -> [SpeedGroup] {
        value.split(separator: ";").compactMap { chunk -> SpeedGroup? in
            var rest = chunk.trimmingCharacters(in: .whitespaces)
            guard !rest.isEmpty else { return nil }
            // id = first whitespace-delimited token
            guard let idEnd = rest.firstIndex(where: { $0.isWhitespace }) else {
                return SpeedGroup(id: rest)
            }
            let id = String(rest[..<idEnd])
            rest = String(rest[idEnd...]).trimmingCharacters(in: .whitespaces)
            var label: String?
            if rest.hasPrefix("\"") {
                if let close = rest.dropFirst().firstIndex(of: "\"") {
                    label = String(rest[rest.index(after: rest.startIndex)..<close])
                    rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            let pace = rest.isEmpty ? nil : SwimTime(parsing: rest)
            return SpeedGroup(id: id, label: label, basePace100: pace)
        }
    }

    /// Declares groups A, B, C… when send-off lists imply more lanes than
    /// declared. A list with one time *per rep* is a per-rep interval ladder
    /// ("5x100 @1:40/1:45/1:50/1:55/2:00 ascend") — five intervals for one
    /// swimmer, not five lanes — so a set whose send-off arity equals its rep
    /// count is ignored for lane inference; everything else (e.g. `5x100`
    /// across three lane times) declares its lanes.
    private static func ensureGroups(_ workout: inout Workout) {
        var maxArity = workout.groups.count
        func scan(_ items: [WorkoutItem]) {
            for item in items {
                switch item {
                case .set(let set):
                    guard let count = set.interval?.sendoffs?.count, count >= 2,
                          count != set.reps
                    else { break }
                    maxArity = max(maxArity, count)
                case .repeatBlock(let block):
                    scan(block.items)
                case .rest, .note:
                    break
                }
            }
        }
        for section in workout.sections { scan(section.items) }
        guard maxArity > workout.groups.count else { return }
        let defaultIDs = ["A", "B", "C", "D", "E", "F", "G", "H"]
        for index in workout.groups.count..<min(maxArity, defaultIDs.count) {
            workout.groups.append(SpeedGroup(id: defaultIDs[index]))
        }
    }

    /// Removes send-off entries that reference groups which don't exist — the
    /// surplus times of a per-rep interval ladder (`5x100 @1:40/.../2:00`) whose
    /// arity was (correctly) not promoted to lanes. Without this they'd validate
    /// as references to undefined groups; the note keeps the original line.
    private static func trimOrphanSendoffs(_ workout: inout Workout) {
        let known = Set(workout.groups.map { $0.id })
        guard !known.isEmpty else { return }
        func fix(_ items: inout [WorkoutItem]) {
            for index in items.indices {
                switch items[index] {
                case .set(var set):
                    if let sendoffs = set.interval?.sendoffs,
                       sendoffs.keys.contains(where: { !known.contains($0) }) {
                        let kept = sendoffs.filter { known.contains($0.key) }
                        set.interval?.sendoffs = kept.isEmpty ? nil : kept
                        items[index] = .set(set)
                    }
                case .repeatBlock(var block):
                    fix(&block.items)
                    items[index] = .repeatBlock(block)
                case .rest, .note:
                    break
                }
            }
        }
        for section in workout.sections.indices { fix(&workout.sections[section].items) }
    }

    // MARK: - Structural lines

    /// `3x {`, `2 x {`, `4/3x {` (per-group rounds), `3.5x {` (fractional →
    /// nearest), `4 or 3x {` / `3-5x {` (alternatives → first count).
    private static func repeatOpen(_ line: String) -> RepeatBlock? {
        // Token = everything before "x {", starting with a digit and free of
        // any `x`/brace so a set line can never be mistaken for a repeat.
        let pattern = /^(\d[^x×{]*?)\s*[x×]\s*\{\s*(?:\|\s*(.*))?$/.ignoresCase()
        guard let match = line.firstMatch(of: pattern),
              let count = parseRoundCount(String(match.1).trimmingCharacters(in: .whitespaces))
        else { return nil }
        var block = RepeatBlock(rounds: count.rounds, items: [])
        block.roundsPerGroup = count.perGroup
        if let note = match.2, !note.isEmpty {
            block.note = String(note)
        }
        block.sourceText = line
        return block
    }

    /// Reads a repeat-block round count: `4/3` (per group), `3.5` (fractional →
    /// nearest int), `4 or 3` / `3-5` (alternatives → first), or plain `3`.
    private static func parseRoundCount(_ token: String) -> (rounds: Int, perGroup: [String: Int]?)? {
        // Per-group rounds: "4/3" → A does 4, B does 3 (digits and slashes only).
        if token.contains("/"), token.allSatisfy({ $0.isNumber || $0 == "/" }) {
            let counts = token.split(separator: "/").compactMap { Int($0) }
            guard let first = counts.first else { return nil }
            guard counts.count > 1 else { return (first, nil) }
            let defaultIDs = ["A", "B", "C", "D", "E", "F", "G", "H"]
            var perGroup: [String: Int] = [:]
            for (index, count) in counts.enumerated() where index < defaultIDs.count {
                perGroup[defaultIDs[index]] = count
            }
            return (first, perGroup)
        }
        // Fractional rounds: "3.5" → nearest whole round.
        if token.firstMatch(of: /^\d+\.\d+$/) != nil, let value = Double(token) {
            return (max(1, Int(value.rounded())), nil)
        }
        // Alternatives/ranges ("4 or 3", "3-5") or plain "3": take the first count.
        let ints = token.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let first = ints.first, first >= 1, first <= 99 else { return nil }
        return (first, nil)
    }

    /// `round 2: Back and Free` / `rounds 1-2: drill focus`
    private static func perRoundLine(_ line: String) -> PerRound? {
        let pattern = /^rounds?\s+(\d+(?:-\d+)?|odd|even)\s*:\s*(.+)$/.ignoresCase()
        guard let match = line.firstMatch(of: pattern) else { return nil }
        let selector = String(match.1).lowercased()
        let text = String(match.2).trimmingCharacters(in: .whitespaces)
        let stroke = KeywordTables.stroke[text.lowercased()]
        return PerRound(selector: selector, stroke: stroke, note: stroke == nil ? text : nil)
    }

    /// `rest 1:00`, `rest :30 | between rounds`
    private static func restLine(_ line: String) -> RestItem? {
        let pattern = /^rest\s+(\S+)\s*(?:\|\s*(.*))?$/.ignoresCase()
        guard let match = line.firstMatch(of: pattern) else { return nil }
        guard let time = SwimTime(parsing: String(match.1)) else { return nil }
        let note = match.2.map(String.init)?.trimmingCharacters(in: .whitespaces)
        return RestItem(duration: time, note: note?.isEmpty == true ? nil : note)
    }
}

// MARK: - Rep ladder

/// A descending-rep ladder like `6-4-2 x 50 stroke @:45-:50-:55`: rep counts
/// `6,4,2`, distance `50`, the descriptor body (`stroke`), an optional matching
/// send-off ladder, and a trailing note. Rebuilt into ordinary set lines by the
/// parser so the deterministic set parser handles strokes/efforts/intervals.
struct RepLadder {
    var counts: [Int]
    var distance: Int
    var body: String
    var sendoffs: [String]
    var note: String?

    var countsText: String { counts.map(String.init).joined(separator: "-") }

    static func parse(_ line: String) -> RepLadder? {
        guard let match = line.firstMatch(of: /^(\d+(?:-\d+)+)\s*[x×]\s*(\d+)\b\s*(.*)$/) else {
            return nil
        }
        let counts = match.1.split(separator: "-").compactMap { Int($0) }
        // Rep counts are small; larger numbers mean this is a distance range
        // ("100-200 x 4"), not a rep ladder — leave it for the set parser.
        guard counts.count >= 2, counts.allSatisfy({ $0 >= 1 && $0 <= 30 }),
              let distance = Int(match.2)
        else { return nil }

        var remainder = String(match.3)
        var note: String?
        if let bar = remainder.firstIndex(of: "|") {
            note = String(remainder[remainder.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
            remainder = String(remainder[..<bar])
        }
        var sendoffs: [String] = []
        if let at = remainder.firstMatch(of: /@\s*([0-9:+\/sLane-]+)/.ignoresCase()) {
            sendoffs = String(at.1).split(separator: "-").map(String.init)
            remainder.removeSubrange(at.range)
        }
        let body = remainder.trimmingCharacters(in: .whitespaces)
        return RepLadder(counts: counts, distance: distance, body: body, sendoffs: sendoffs, note: note)
    }

    /// Rebuilds one ordinary set line. `sendoffIndex` picks the matching send-off
    /// when the ladder carries one per position; pass nil to omit it.
    func line(reps: Int, sendoffIndex: Int?, extraNote: String?) -> String {
        var parts = ["\(reps) x \(distance)"]
        if !body.isEmpty { parts.append(body) }
        if let index = sendoffIndex, !sendoffs.isEmpty {
            let sendoff = sendoffs.count == counts.count ? sendoffs[index] : sendoffs[0]
            parts.append("@\(sendoff)")
        }
        var result = parts.joined(separator: " ")
        let notes = [note, extraNote].compactMap { $0 }.filter { !$0.isEmpty }
        if !notes.isEmpty { result += " | " + notes.joined(separator: "; ") }
        return result
    }
}

// MARK: - Keyword tables

enum KeywordTables {
    static let stroke: [String: Stroke] = [
        "free": .free, "fr": .free, "freestyle": .free,
        "back": .back, "bk": .back, "backstroke": .back,
        "breast": .breast, "br": .breast, "brst": .breast, "breaststroke": .breast,
        "fly": .fly, "fl": .fly, "butterfly": .fly,
        "im": .im, "imo": .imo, "rimo": .rimo,
        "stroke": .stroke, "stk": .stroke,
        "choice": .choice, "ch": .choice,
    ]

    static let activity: [String: Activity] = [
        "swim": .swim, "sw": .swim,
        "kick": .kick, "k": .kick,
        "pull": .pull, "pu": .pull,
        "drill": .drill, "dr": .drill,
        "scull": .scull, "skull": .scull,
    ]

    static let equipment: [String: Equipment] = [
        "fins": .fins, "w/fins": .fins,
        "paddles": .paddles, "pdl": .paddles,
        "buoy": .buoy,
        "snorkel": .snorkel,
        "board": .board,
    ]

    static let level: [String: EffortLevel] = [
        "easy": .easy, "ez": .easy,
        "smooth": .smooth,
        "moderate": .moderate,
        "strong": .strong,
        "fast": .fast,
        "sprint": .sprint,
        "max": .max, "all-out": .max, "allout": .max, "blast": .max, "asap": .max,
        "race": .race,
    ]

    static let shape: [String: EffortShape] = [
        "steady": .steady,
        "build": .build,
        "descend": .descend, "desc": .descend, "desc.": .descend,
        "ascend": .ascend,
        "ns": .negativeSplit, "negative-split": .negativeSplit,
        "vs": .variableSprint, "variable-sprint": .variableSprint,
    ]
}

// MARK: - Set line parser

enum SetLineParser {

    /// Parses one set line; returns nil when the line does not start with a distance.
    static func parse(_ line: String, groups: [SpeedGroup]) -> SwimSet? {
        var working = line

        // 1. Trailing "| note"
        var noteParts: [String] = []
        if let bar = working.firstIndex(of: "|") {
            let note = String(working[working.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
            if !note.isEmpty { noteParts.append(note) }
            working = String(working[..<bar])
        }

        // 2. Leading reps x distance
        guard let lead = working.firstMatch(of: /^\s*(?:(\d+)\s*[x×]\s*)?(\d+)(?=$|[\s,;(@])/) else {
            return nil
        }
        let reps = lead.1.flatMap { Int($0) } ?? 1
        guard let distance = Int(lead.2) else { return nil }
        working = String(working[lead.range.upperBound...])

        var set = SwimSet(reps: reps, distance: distance)
        set.sourceText = line

        // 3. Parentheticals: segments, rest hints, send-off offsets
        var interval = Interval(mode: .open)
        var pendingOffsets: [SwimTime] = []
        while let parenMatch = working.firstMatch(of: /\(([^)]*)\)/) {
            let content = String(parenMatch.1).trimmingCharacters(in: .whitespaces)
            working.removeSubrange(parenMatch.range)
            if let hint = restHint(content) {
                if hint.isMax {
                    interval.maxRest = hint.time
                } else {
                    interval.targetRest = hint.time
                }
            } else if content.hasPrefix("+"), let offset = SwimTime(parsing: String(content.dropFirst())) {
                pendingOffsets.append(offset)
            } else if let segments = segmentList(content, repDistance: distance) {
                set.segments = segments
            } else if !content.isEmpty {
                noteParts.append(content)
            }
        }

        // 4. Send-off "@1:30/1:45/2:00+" (also "@:35", "@35/40s")
        if let atMatch = working.firstMatch(of: /@\s*([0-9:+\/sLane]+)/.ignoresCase()) {
            let token = String(atMatch.1)
            working.removeSubrange(atMatch.range)
            if token.lowercased().contains("lane") {
                interval.note = "send-off by lane"
                interval.mode = .sendoff
            } else {
                var spec = token
                if spec.hasSuffix("+") {
                    interval.openEnded = true
                    spec.removeLast()
                }
                let parts = spec.split(separator: "/").map { part -> SwimTime? in
                    var p = String(part)
                    if p.hasSuffix("s") { p.removeLast() }
                    return SwimTime(parsing: p)
                }
                let times = parts.compactMap { $0 }
                if !times.isEmpty {
                    interval.mode = .sendoff
                    var sendoffs: [String: SwimTime] = [:]
                    let ids = groupIDs(count: max(times.count, times.count + pendingOffsets.count), declared: groups)
                    for (index, time) in times.enumerated() where index < ids.count {
                        sendoffs[ids[index]] = time
                    }
                    // Offsets extend the listed send-offs cumulatively: "@1:30 (+1:00)"
                    if let last = times.last, !pendingOffsets.isEmpty {
                        var running = last
                        for (offsetIndex, offset) in pendingOffsets.enumerated() {
                            let position = times.count + offsetIndex
                            guard position < ids.count else { break }
                            running = running + offset
                            sendoffs[ids[position]] = running
                        }
                    }
                    interval.sendoffs = sendoffs
                }
            }
        }

        // 5. Rest tokens: "r:20", "r20s", "r1m", "r1:00", "r1:00m"
        if let restMatch = working.firstMatch(of: /\br((?:\d+:\d+)|(?::\d+)|(?:\d+))(m|s)?\b/.ignoresCase()) {
            let body = String(restMatch.1)
            let suffix = restMatch.2.map { String($0).lowercased() }
            working.removeSubrange(restMatch.range)
            var time = SwimTime(parsing: body)
            if let t = time, suffix == "m", !body.contains(":") {
                time = SwimTime(seconds: t.seconds * 60)
            }
            if let time {
                if interval.mode == .sendoff {
                    // Rest noted alongside a send-off is the designed rest.
                    if interval.targetRest == nil { interval.targetRest = time }
                } else {
                    interval.mode = .rest
                    interval.rest = time
                }
            }
        }

        // 6. "as a/b/c" clause → perRep (count == reps) or equal segments.
        //    Extracted after interval/rest tokens so it cannot swallow them.
        if let asMatch = working.firstMatch(of: /\bas[:\s]\s*(.+)$/.ignoresCase()) {
            let clause = String(asMatch.1)
            working.removeSubrange(asMatch.range)
            applyAsClause(clause, to: &set, noteParts: &noteParts)
        }

        // 7. Keyword scan over the remainder
        scanKeywords(working, into: &set, noteParts: &noteParts)

        if interval.mode != .open || interval.targetRest != nil || interval.maxRest != nil || interval.note != nil {
            set.interval = interval
        }
        if !noteParts.isEmpty {
            set.note = noteParts.joined(separator: "; ")
        }
        if set.effort?.isEmpty == true {
            set.effort = nil
        }
        return set
    }

    // MARK: Helpers

    private static func groupIDs(count: Int, declared: [SpeedGroup]) -> [String] {
        if declared.count >= count {
            return declared.map { $0.id }
        }
        var ids = declared.map { $0.id }
        let defaults = ["A", "B", "C", "D", "E", "F", "G", "H"]
        while ids.count < count, ids.count < defaults.count {
            // Use default letters not already taken.
            if let next = defaults.first(where: { !ids.contains($0) }) {
                ids.append(next)
            } else {
                break
            }
        }
        return ids
    }

    private struct RestHint {
        var time: SwimTime
        var isMax: Bool
    }

    /// "(~:15 rest)", "(ideally 15s rest)", "(max 30s rest)", "(pick an interval with 10s rest)"
    private static func restHint(_ content: String) -> RestHint? {
        let lower = content.lowercased()
        guard lower.contains("rest") else { return nil }
        guard let timeMatch = lower.firstMatch(of: /(?:~\s*)?((?:\d+:\d+)|(?::\d+)|(?:\d+))\s*s?(?:ec)?\b/) else {
            return nil
        }
        guard let time = SwimTime(parsing: String(timeMatch.1)) else { return nil }
        return RestHint(time: time, isMax: lower.contains("max"))
    }

    /// "(25 kick/25 drill/25 swim)" → segments. All chunks must lead with a
    /// distance. A pattern that divides the rep distance evenly is tiled:
    /// "500 (50 free/50 drill/25 kick)" repeats the 125 pattern four times.
    private static func segmentList(_ content: String, repDistance: Int) -> [Segment]? {
        let chunks = content.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard chunks.count >= 2 else { return nil }
        var segments: [Segment] = []
        for chunk in chunks {
            guard let match = chunk.firstMatch(of: /^(\d+)\s*(.*)$/) else { return nil }
            guard let segDistance = Int(match.1) else { return nil }
            var segment = Segment(distance: segDistance)
            let descriptor = String(match.2).trimmingCharacters(in: .whitespaces)
            applyDescriptor(descriptor, to: &segment)
            segments.append(segment)
        }
        let sum = segments.reduce(0) { $0 + $1.distance }
        if sum > 0, sum != repDistance, repDistance % sum == 0 {
            let repetitions = repDistance / sum
            segments = Array(repeating: segments, count: repetitions).flatMap { $0 }
        }
        return segments
    }

    private static func applyDescriptor(_ descriptor: String, to segment: inout Segment) {
        guard !descriptor.isEmpty else { return }
        var unmatched: [String] = []
        for word in descriptor.split(whereSeparator: { $0 == " " || $0 == "," }) {
            let token = String(word).lowercased()
            if let stroke = KeywordTables.stroke[token] {
                segment.stroke = stroke
            } else if let activity = KeywordTables.activity[token] {
                segment.activity = activity
            } else if let level = KeywordTables.level[token] {
                segment.effortLevel = level
            } else {
                unmatched.append(String(word))
            }
        }
        if !unmatched.isEmpty {
            segment.note = unmatched.joined(separator: " ")
        }
    }

    /// "as swim/kick/pull" (perRep when count == reps) or "as drill/build/fast"
    /// (segments when the distance divides evenly).
    private static func applyAsClause(_ clause: String, to set: inout SwimSet, noteParts: inout [String]) {
        let parts = clause
            .split(whereSeparator: { $0 == "/" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else {
            noteParts.append("as \(clause)")
            return
        }
        if parts.count == set.reps {
            set.perRep = parts.enumerated().map { index, part in
                var perRep = PerRep(selector: "\(index + 1)")
                let token = part.lowercased()
                if let stroke = KeywordTables.stroke[token] {
                    perRep.stroke = stroke
                } else if let activity = KeywordTables.activity[token] {
                    perRep.activity = activity
                } else if let level = KeywordTables.level[token] {
                    perRep.effortLevel = level
                } else {
                    perRep.note = part
                }
                return perRep
            }
            if set.perRep?.allSatisfy({ $0.activity != nil }) == true {
                set.activity = .mixed
            } else if set.perRep?.allSatisfy({ $0.stroke != nil }) == true {
                set.stroke = .mixed
            }
        } else if set.distance % parts.count == 0 {
            let segDistance = set.distance / parts.count
            set.segments = parts.map { part in
                var segment = Segment(distance: segDistance)
                applyDescriptor(part, to: &segment)
                return segment
            }
        } else {
            noteParts.append("as \(clause)")
        }
    }

    private static func scanKeywords(_ text: String, into set: inout SwimSet, noteParts: inout [String]) {
        var effort = set.effort ?? Effort()
        var breath = set.breath
        var unmatched: [String] = []

        let separators = CharacterSet(charactersIn: " ,;")
        let tokens = text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var index = 0
        while index < tokens.count {
            let raw = tokens[index]
            let token = raw.lowercased()
            defer { index += 1 }

            // Percent: "90%", "75-80%"
            if let match = token.firstMatch(of: /^(\d+)(?:-(\d+))?%$/) {
                effort.percent = Int(match.1)
                effort.percentMax = match.2.flatMap { Int($0) }
                continue
            }
            // Breath: "bp" + pattern, "be3", "be 3-5"
            if token == "bp", index + 1 < tokens.count {
                breath = Breath(pattern: tokens[index + 1])
                index += 1
                continue
            }
            if let match = token.firstMatch(of: /^be(\d+(?:-\d+)?)$/) {
                breath = Breath(pattern: String(match.1))
                continue
            }
            // Equipment, attached ("w/fins", "w/paddles") or bare ("fins").
            // The printer emits "w/<equipment>" for every kind, so strip a
            // leading "w/" before the table lookup or only fins would round-trip.
            let equipmentToken = token.hasPrefix("w/") ? String(token.dropFirst(2)) : token
            if let equipment = KeywordTables.equipment[equipmentToken] {
                set.equipment = (set.equipment ?? []) + [equipment]
                continue
            }
            if token == "w" || token == "with", index + 1 < tokens.count,
               let equipment = KeywordTables.equipment[tokens[index + 1].lowercased()] {
                set.equipment = (set.equipment ?? []) + [equipment]
                index += 1
                continue
            }
            if let stroke = KeywordTables.stroke[token] {
                if set.stroke == nil { set.stroke = stroke } else { unmatched.append(raw) }
                continue
            }
            if let activity = KeywordTables.activity[token] {
                if set.activity == nil { set.activity = activity } else { unmatched.append(raw) }
                continue
            }
            if token == "all", index + 1 < tokens.count, tokens[index + 1].lowercased() == "out" {
                effort.level = .max
                index += 1
                continue
            }
            if let level = KeywordTables.level[token] {
                if effort.level == nil { effort.level = level } else { unmatched.append(raw) }
                continue
            }
            if let shape = KeywordTables.shape[token] {
                if effort.shape == nil { effort.shape = shape } else { unmatched.append(raw) }
                // "desc 1-4" / "descend to 90%" detail capture
                if index + 1 < tokens.count {
                    let next = tokens[index + 1].lowercased()
                    if next.firstMatch(of: /^\d+-\d+$/) != nil {
                        effort.detail = tokens[index + 1]
                        index += 1
                    } else if next == "to", index + 2 < tokens.count,
                              let match = tokens[index + 2].firstMatch(of: /^(\d+)(?:-(\d+))?%$/) {
                        effort.percent = Int(match.1)
                        effort.percentMax = match.2.flatMap { Int($0) }
                        index += 2
                    } else if next == "by", index + 2 < tokens.count {
                        effort.detail = "by \(tokens[index + 2])"
                        index += 2
                    }
                }
                continue
            }
            unmatched.append(raw)
        }

        if !effort.isEmpty {
            set.effort = effort
        }
        if let breath {
            set.breath = breath
        }
        if !unmatched.isEmpty {
            noteParts.append(unmatched.joined(separator: " "))
        }
    }
}
