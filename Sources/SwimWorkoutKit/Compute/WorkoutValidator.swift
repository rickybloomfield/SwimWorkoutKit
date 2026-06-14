// SPDX-License-Identifier: MIT

import Foundation

public struct ValidationIssue: Sendable, Equatable, CustomStringConvertible {
    public enum Severity: String, Sendable {
        case error
        case warning
    }

    public var severity: Severity
    public var code: String
    public var message: String
    /// Human path like `sections[1].items[3]`.
    public var path: String

    public init(severity: Severity, code: String, message: String, path: String) {
        self.severity = severity
        self.code = code
        self.message = message
        self.path = path
    }

    public var description: String { "[\(severity.rawValue)] \(code) at \(path): \(message)" }
}

/// Structural and arithmetic checks. Totals reconciliation doubles as the
/// OCR checksum: printed workouts state their totals.
public enum WorkoutValidator {

    public static func validate(_ document: SwimWorkoutDocument, paceModel: PaceModel = .default) -> [ValidationIssue] {
        validate(document.workout, paceModel: paceModel)
    }

    public static func validate(_ workout: Workout, paceModel: PaceModel = .default) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        validateGroups(workout, &issues)
        for (sectionIndex, section) in workout.sections.enumerated() {
            let path = "sections[\(sectionIndex)]"
            validateSection(section, workout: workout, path: path, &issues)
        }
        validateStatedTotal(workout, &issues)
        return issues
    }

    // MARK: - Groups

    private static func validateGroups(_ workout: Workout, _ issues: inout [ValidationIssue]) {
        var seen = Set<String>()
        for group in workout.groups {
            if !seen.insert(group.id).inserted {
                issues.append(.init(
                    severity: .error, code: "duplicate-group",
                    message: "Duplicate group id '\(group.id)'", path: "groups"
                ))
            }
        }
        let known = Set(workout.groups.map { $0.id })
        guard !known.isEmpty else { return }
        walkSets(workout) { set, path in
            let referenced = Set(set.interval?.sendoffs?.keys ?? [:].keys)
                .union(set.perGroup?.keys ?? [:].keys)
                .union(set.groupFilter ?? [])
            for id in referenced where !known.contains(id) {
                issues.append(.init(
                    severity: .error, code: "unknown-group",
                    message: "Reference to undefined group '\(id)'", path: path
                ))
            }
        }
    }

    // MARK: - Sections & sets

    private static func validateSection(
        _ section: WorkoutSection,
        workout: Workout,
        path: String,
        _ issues: inout [ValidationIssue]
    ) {
        for (itemIndex, item) in section.items.enumerated() {
            validateItem(item, workout: workout, path: "\(path).items[\(itemIndex)]", &issues)
        }
        if let stated = section.statedDistance {
            let computed = groupDistances(in: workout) { groupID in
                WorkoutCalculator.distance(of: section, group: groupID, groups: workout.groups)
            }
            if !computed.values.contains(stated) {
                issues.append(.init(
                    severity: .warning, code: "section-total-mismatch",
                    message: "Stated \(stated) but computed \(describe(computed))",
                    path: path
                ))
            }
        }
    }

    private static func validateItem(
        _ item: WorkoutItem,
        workout: Workout,
        path: String,
        _ issues: inout [ValidationIssue]
    ) {
        switch item {
        case .set(let set):
            validateSet(set, workout: workout, path: path, &issues)
        case .repeatBlock(let block):
            if block.rounds <= 0 {
                issues.append(.init(
                    severity: .error, code: "invalid-rounds",
                    message: "Rounds must be positive", path: path
                ))
            }
            for (childIndex, child) in block.items.enumerated() {
                validateItem(child, workout: workout, path: "\(path).items[\(childIndex)]", &issues)
            }
        case .rest, .note:
            break
        }
    }

    private static func validateSet(
        _ set: SwimSet,
        workout: Workout,
        path: String,
        _ issues: inout [ValidationIssue]
    ) {
        if set.reps <= 0 {
            issues.append(.init(
                severity: .error, code: "invalid-reps",
                message: "Reps must be positive", path: path
            ))
        }
        if set.distance <= 0 {
            issues.append(.init(
                severity: .error, code: "invalid-distance",
                message: "Distance must be positive", path: path
            ))
        }
        if set.distance > 0, set.distance % workout.course.length != 0 {
            issues.append(.init(
                severity: .warning, code: "distance-course-mismatch",
                message: "\(set.distance) is not a multiple of the \(workout.course.label) course length \(workout.course.length)",
                path: path
            ))
        }
        if let segments = set.segments, !segments.isEmpty {
            let sum = segments.reduce(0) { $0 + $1.distance }
            if sum != set.distance {
                issues.append(.init(
                    severity: .error, code: "segment-sum-mismatch",
                    message: "Segments sum to \(sum), set distance is \(set.distance)",
                    path: path
                ))
            }
        }
        // Send-off plausibility, when we can estimate.
        if let sendoffs = set.interval?.sendoffs {
            for (groupID, sendoff) in sendoffs {
                guard let group = workout.groups.first(where: { $0.id == groupID }),
                      let estimate = PaceModel.default.estimateSeconds(
                        distance: set.distance, stroke: set.stroke,
                        activity: set.activity, basePace100: group.basePace100
                      )
                else { continue }
                if sendoff.seconds < Int(Double(estimate) * 0.75) {
                    issues.append(.init(
                        severity: .warning, code: "implausible-sendoff",
                        message: "Send-off \(sendoff) for group \(groupID) is well under estimated swim time \(SwimTime(seconds: estimate))",
                        path: path
                    ))
                }
            }
        }
    }

    // MARK: - Totals

    private static func validateStatedTotal(_ workout: Workout, _ issues: inout [ValidationIssue]) {
        guard let stated = workout.statedTotal else { return }
        let computed = groupDistances(in: workout) { groupID in
            WorkoutCalculator.distance(of: workout, group: groupID)
        }
        if !computed.values.contains(stated) {
            issues.append(.init(
                severity: .warning, code: "workout-total-mismatch",
                message: "Stated total \(stated) but computed \(describe(computed))",
                path: "workout"
            ))
        }
    }

    // MARK: - Helpers

    private static func groupDistances(
        in workout: Workout,
        compute: (String?) -> Int
    ) -> [String: Int] {
        if workout.groups.isEmpty {
            return ["*": compute(nil)]
        }
        var result: [String: Int] = [:]
        for group in workout.groups {
            result[group.id] = compute(group.id)
        }
        return result
    }

    private static func describe(_ distances: [String: Int]) -> String {
        let unique = Set(distances.values)
        if unique.count == 1, let only = unique.first {
            return "\(only)"
        }
        return distances.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    private static func walkSets(_ workout: Workout, _ visit: (SwimSet, String) -> Void) {
        func walk(_ items: [WorkoutItem], path: String) {
            for (index, item) in items.enumerated() {
                let itemPath = "\(path)[\(index)]"
                switch item {
                case .set(let set): visit(set, itemPath)
                case .repeatBlock(let block): walk(block.items, path: "\(itemPath).items")
                case .rest, .note: break
                }
            }
        }
        for (sectionIndex, section) in workout.sections.enumerated() {
            walk(section.items, path: "sections[\(sectionIndex)].items")
        }
    }
}
