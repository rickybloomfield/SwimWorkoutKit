// SPDX-License-Identifier: MIT

import Foundation

/// Estimates swim time for a distance from a group's base pace per 100.
///
/// v0.1 uses coarse multipliers; the app refines these over time from
/// HealthKit history. Estimates round up to the nearest 5 seconds.
public struct PaceModel: Sendable {
    public var strokeMultipliers: [Stroke: Double]
    public var activityMultipliers: [Activity: Double]

    public init(
        strokeMultipliers: [Stroke: Double]? = nil,
        activityMultipliers: [Activity: Double]? = nil
    ) {
        self.strokeMultipliers = strokeMultipliers ?? Self.defaultStrokeMultipliers
        self.activityMultipliers = activityMultipliers ?? Self.defaultActivityMultipliers
    }

    public static let `default` = PaceModel()

    public static let defaultStrokeMultipliers: [Stroke: Double] = [
        .free: 1.0,
        .back: 1.10,
        .breast: 1.20,
        .fly: 1.15,
        .im: 1.12,
        .imo: 1.12,
        .rimo: 1.12,
        .stroke: 1.12,
        .choice: 1.05,
        .mixed: 1.10,
    ]

    public static let defaultActivityMultipliers: [Activity: Double] = [
        .swim: 1.0,
        .kick: 1.45,
        .pull: 1.05,
        .drill: 1.30,
        .scull: 1.55,
        .mixed: 1.20,
    ]

    /// Estimated seconds to swim `distance` at `basePace100` per 100 with the
    /// given stroke/activity, rounded up to :05. Returns nil without a base pace.
    public func estimateSeconds(
        distance: Int,
        stroke: Stroke?,
        activity: Activity?,
        basePace100: SwimTime?
    ) -> Int? {
        guard let base = basePace100, distance > 0 else { return nil }
        let strokeFactor = strokeMultipliers[stroke ?? .free] ?? 1.0
        let activityFactor = activityMultipliers[activity ?? .swim] ?? 1.0
        let raw = Double(base.seconds) * (Double(distance) / 100.0) * strokeFactor * activityFactor
        return Int((raw / 5.0).rounded(.up)) * 5
    }

    /// Suggested send-off: estimated swim time plus target rest, rounded up to :05.
    public func suggestedSendoff(
        distance: Int,
        stroke: Stroke?,
        activity: Activity?,
        basePace100: SwimTime?,
        targetRest: SwimTime
    ) -> SwimTime? {
        guard let swim = estimateSeconds(
            distance: distance, stroke: stroke, activity: activity, basePace100: basePace100
        ) else { return nil }
        let total = swim + targetRest.seconds
        return SwimTime(seconds: Int((Double(total) / 5.0).rounded(.up)) * 5)
    }
}
