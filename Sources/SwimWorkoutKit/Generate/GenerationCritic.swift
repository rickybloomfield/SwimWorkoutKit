// SPDX-License-Identifier: MIT

import Foundation

/// Deterministic quality checks on generated workouts — the things a small
/// on-device model reliably gets wrong, caught before a swimmer sees them.
public enum GenerationCritic {

    /// Pulls a stated total distance out of free text ("3,200 yards", "3000",
    /// "2.5k"). Numbers under 800 are ignored (those are rep distances).
    public static func targetDistance(in prompt: String) -> Int? {
        // "2.5k" / "3k"
        if let match = prompt.firstMatch(of: /(\d+(?:\.\d+)?)\s*[kK]\b/),
           let value = Double(match.1) {
            let meters = Int(value * 1000)
            if (800...10000).contains(meters) { return meters }
        }
        // "3,200" / "3200" (optionally followed by yd/m/yards/meters)
        for match in prompt.matches(of: /(\d[\d,]{2,5})(?:\s*(?:yd|yards|m|meters))?\b/) {
            let digits = String(match.1).replacingOccurrences(of: ",", with: "")
            if let value = Int(digits), (800...10000).contains(value) {
                return value
            }
        }
        return nil
    }

    public struct Critique: Sendable, Equatable {
        public var isMonotonous: Bool
        public var distinctWorkSignatures: Int
        public var hasAnyShapeOrSegments: Bool

        public var complaint: String? {
            guard isMonotonous else { return nil }
            var parts = ["The main sets are too repetitive (only \(distinctWorkSignatures) distinct set shapes)."]
            if !hasAnyShapeOrSegments {
                parts.append("No set builds, descends, or mixes work.")
            }
            parts.append("Vary the rep distances across blocks (mix 25s/50s/75s/100s/200s), include a kick or drill set, and use descend or build on at least one quality set.")
            return parts.joined(separator: " ")
        }
    }

    /// A workout is monotonous when its work sets collapse into too few
    /// distinct shapes (reps×distance×stroke×activity), with no progression
    /// shapes anywhere. Recoveries don't count toward variety.
    public static func critique(_ workout: Workout) -> Critique {
        var signatures = Set<String>()
        var hasShape = false

        for step in WorkoutFlattener.steps(for: workout, group: workout.groups.first?.id) {
            guard case .set(let set) = step.kind else { continue }
            let isRecovery = set.effort?.level == .easy || set.effort?.level == .smooth
            if set.effort?.shape != nil || set.segments?.isEmpty == false {
                hasShape = true
            }
            guard !isRecovery else { continue }
            signatures.insert(
                "\(set.distance)|\(set.stroke?.rawValue ?? "-")|\(set.activity?.rawValue ?? "-")|\(set.effort?.shape?.rawValue ?? "-")"
            )
        }

        let monotonous = signatures.count < 3 || (!hasShape && signatures.count < 5)
        return Critique(
            isMonotonous: monotonous,
            distinctWorkSignatures: signatures.count,
            hasAnyShapeOrSegments: hasShape
        )
    }
}
