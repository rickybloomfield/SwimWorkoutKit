// SPDX-License-Identifier: MIT

import Foundation

/// Emits canonical SwimText from a document. The printer targets the subset the
/// parser understands, so `parse(print(parse(x)))` is stable.
public enum SwimTextPrinter {

    public static func print(_ document: SwimWorkoutDocument) -> String {
        print(document.workout)
    }

    /// Canonical SwimText. With `metadataPlaceholders`, optional metadata fields
    /// that are unset are still emitted as empty `key:` lines — so a scaffold
    /// like "date:" survives a print → edit → print round-trip instead of
    /// silently disappearing.
    public static func print(_ workout: Workout, metadataPlaceholders: Bool = false) -> String {
        var lines: [String] = []

        if let title = workout.title {
            lines.append("# \(title)")
        }
        appendMetadata("date", workout.date, to: &lines, placeholder: metadataPlaceholders)
        appendMetadata("author", workout.author, to: &lines, placeholder: metadataPlaceholders)
        appendMetadata("team", workout.team, to: &lines, placeholder: metadataPlaceholders)
        if let description = workout.description {
            for descriptionLine in description.components(separatedBy: .newlines) {
                lines.append("description: \(descriptionLine)")
            }
        } else if metadataPlaceholders {
            lines.append("description:")
        }
        lines.append("course: \(workout.course.label.lowercased())")
        appendMetadata("categories", workout.categories.isEmpty ? nil : workout.categories.joined(separator: ", "),
                       to: &lines, placeholder: metadataPlaceholders)
        appendMetadata("tags", workout.tags.isEmpty ? nil : workout.tags.joined(separator: ", "),
                       to: &lines, placeholder: metadataPlaceholders)
        if !workout.groups.isEmpty {
            let groups = workout.groups.map { group -> String in
                var parts = [group.id]
                if let label = group.label { parts.append("\"\(label)\"") }
                if let pace = group.basePace100 { parts.append(pace.notation) }
                return parts.joined(separator: " ")
            }
            lines.append("groups: \(groups.joined(separator: "; "))")
        } else if metadataPlaceholders {
            lines.append("groups:")
        }
        if let total = workout.statedTotal {
            lines.append("total: \(total)")
        }
        if let notes = workout.notes {
            for noteLine in notes.components(separatedBy: .newlines) {
                lines.append("notes: \(noteLine)")
            }
        }

        for section in workout.sections {
            lines.append("")
            var header = "== \(section.name)"
            if let stated = section.statedDistance {
                header += ": \(stated)"
            }
            lines.append(header)
            if let note = section.note {
                lines.append("> \(note)")
            }
            for item in section.items {
                lines.append(contentsOf: printItem(item, indent: 0))
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Emits "key: value" when set, or a bare "key:" placeholder when unset and
    /// `placeholder` is true; otherwise nothing.
    private static func appendMetadata(
        _ key: String, _ value: String?, to lines: inout [String], placeholder: Bool
    ) {
        if let value {
            lines.append("\(key): \(value)")
        } else if placeholder {
            lines.append("\(key):")
        }
    }

    // MARK: - Items

    private static func printItem(_ item: WorkoutItem, indent: Int) -> [String] {
        let pad = String(repeating: "  ", count: indent)
        switch item {
        case .set(let set):
            return [pad + printSet(set)]
        case .repeatBlock(let block):
            var lines: [String] = []
            var open = "\(roundsToken(block))x {"
            if let note = block.note {
                open += " | \(note)"
            }
            lines.append(pad + open)
            for round in block.perRound ?? [] {
                var text = "round \(round.selector): "
                if let stroke = round.stroke {
                    text += strokeToken(stroke)
                    if let note = round.note { text += " | \(note)" }
                } else {
                    text += round.note ?? ""
                }
                lines.append(pad + "  " + text)
            }
            for child in block.items {
                lines.append(contentsOf: printItem(child, indent: indent + 1))
            }
            lines.append(pad + "}")
            return lines
        case .rest(let rest):
            var line = "rest \(rest.duration?.notation ?? ":30")"
            if let note = rest.note { line += " | \(note)" }
            return [pad + line]
        case .note(let note):
            return [pad + "> \(note.text)"]
        }
    }

    private static func roundsToken(_ block: RepeatBlock) -> String {
        guard let perGroup = block.roundsPerGroup, !perGroup.isEmpty else {
            return "\(block.rounds)"
        }
        // Emit in group-id order (A, B, C…) as "4/3".
        let ordered = perGroup.sorted { $0.key < $1.key }.map { "\($0.value)" }
        return ordered.joined(separator: "/")
    }

    // MARK: - Sets

    static func printSet(_ set: SwimSet) -> String {
        var parts: [String] = []

        if set.reps == 1 {
            parts.append("\(set.distance)")
        } else {
            parts.append("\(set.reps)x\(set.distance)")
        }

        if let segments = set.segments, !segments.isEmpty {
            let body = segments.map { segment -> String in
                var bits = ["\(segment.distance)"]
                if let stroke = segment.stroke { bits.append(strokeToken(stroke)) }
                if let activity = segment.activity { bits.append(activity.rawValue) }
                if let level = segment.effortLevel { bits.append(level.rawValue) }
                if let note = segment.note { bits.append(note) }
                return bits.joined(separator: " ")
            }.joined(separator: "/")
            parts.append("(\(body))")
        }

        if let stroke = set.stroke, stroke != .mixed {
            parts.append(strokeToken(stroke))
        }
        if let activity = set.significantActivity {
            parts.append(activity.rawValue)
        }
        if let drill = set.drillName {
            parts.append(drill)
        }
        for equipment in set.equipment ?? [] {
            parts.append("w/\(equipment.rawValue)")
        }

        if let perRep = set.perRep, !perRep.isEmpty,
           perRep.enumerated().allSatisfy({ index, rep in rep.selector == "\(index + 1)" }) {
            let body = perRep.map { rep -> String in
                if let stroke = rep.stroke { return strokeToken(stroke) }
                if let activity = rep.activity { return activity.rawValue }
                if let level = rep.effortLevel { return level.rawValue }
                return rep.note ?? "?"
            }.joined(separator: "/")
            parts.append("as \(body)")
        }

        if let effort = set.effort {
            if let shape = effort.shape, shape != .steady {
                parts.append(shapeToken(shape))
                if let detail = effort.detail {
                    parts.append(detail)
                }
                if let percent = effort.percent {
                    var token = "to \(percent)"
                    if let max = effort.percentMax { token += "-\(max)" }
                    parts.append(token + "%")
                }
            } else if let percent = effort.percent {
                var token = "\(percent)"
                if let max = effort.percentMax { token += "-\(max)" }
                parts.append(token + "%")
            }
            if let level = effort.level {
                parts.append(level.rawValue)
            }
        }

        if let breath = set.breath {
            if let pattern = breath.pattern {
                if pattern.contains("/") {
                    parts.append("bp \(pattern)")
                } else {
                    parts.append("be\(pattern)")
                }
            } else if let every = breath.every {
                parts.append("be\(every)")
            }
        }

        if let interval = set.interval {
            switch interval.mode {
            case .sendoff:
                if let sendoffs = interval.sendoffs, !sendoffs.isEmpty {
                    let ordered = sendoffs.sorted { $0.key < $1.key }.map { $0.value.notation }
                    var token = "@" + ordered.joined(separator: "/")
                    if interval.openEnded == true { token += "+" }
                    parts.append(token)
                } else if interval.note == "send-off by lane" {
                    parts.append("@Lane")
                }
            case .rest:
                if let rest = interval.rest {
                    parts.append("r\(rest.notation)")
                }
            case .open:
                break
            }
            if let target = interval.targetRest {
                parts.append("(~\(target.notation) rest)")
            }
            if let max = interval.maxRest {
                parts.append("(max \(max.notation) rest)")
            }
        }

        var line = parts.joined(separator: " ")
        if let note = set.note {
            line += " | \(note)"
        }
        return line
    }

    private static func strokeToken(_ stroke: Stroke) -> String {
        stroke.rawValue
    }

    private static func shapeToken(_ shape: EffortShape) -> String {
        switch shape {
        case .negativeSplit: return "ns"
        case .variableSprint: return "vs"
        default: return shape.rawValue
        }
    }
}
