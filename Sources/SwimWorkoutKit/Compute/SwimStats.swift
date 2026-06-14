// SPDX-License-Identifier: MIT

import Foundation

/// Aggregations over recorded swims (the deduplicated representatives — the
/// caller decides which swims count; this just adds them up honestly).
public enum SwimStats {

    public struct Summary: Sendable, Equatable {
        public var distanceMeters: Double
        public var activeEnergyKcal: Double
        public var duration: TimeInterval
        public var count: Int

        public static let zero = Summary(distanceMeters: 0, activeEnergyKcal: 0, duration: 0, count: 0)
    }

    public struct Bucket: Sendable, Equatable, Identifiable {
        public var start: Date
        public var summary: Summary
        public var id: Date { start }
    }

    public static func summary(of swims: [RecordedSwim]) -> Summary {
        swims.reduce(into: .zero) { result, swim in
            result.distanceMeters += swim.distanceMeters ?? 0
            result.activeEnergyKcal += swim.activeEnergyKcal ?? 0
            result.duration += swim.duration
            result.count += 1
        }
    }

    /// Sums swims into calendar buckets (`.day`, `.month`, or `.year`) over
    /// `range`, including empty buckets so charts have a continuous axis.
    public static func buckets(
        of swims: [RecordedSwim],
        unit: Calendar.Component,
        in range: DateInterval,
        calendar: Calendar
    ) -> [Bucket] {
        var sums: [Date: Summary] = [:]
        for swim in swims where range.contains(swim.start) {
            guard let bucketStart = calendar.dateInterval(of: unit, for: swim.start)?.start else { continue }
            var entry = sums[bucketStart] ?? .zero
            entry.distanceMeters += swim.distanceMeters ?? 0
            entry.activeEnergyKcal += swim.activeEnergyKcal ?? 0
            entry.duration += swim.duration
            entry.count += 1
            sums[bucketStart] = entry
        }

        // Walk the range to emit a bucket per unit, filled or empty.
        var buckets: [Bucket] = []
        var cursor = calendar.dateInterval(of: unit, for: range.start)?.start ?? range.start
        while cursor < range.end {
            buckets.append(Bucket(start: cursor, summary: sums[cursor] ?? .zero))
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return buckets
    }

    /// Consecutive weeks with at least one swim, counting backward from the
    /// week containing `asOf`. The current week counts even without a swim
    /// yet (a Tuesday shouldn't break a streak).
    public static func weeklyStreak(
        of swims: [RecordedSwim],
        asOf: Date,
        calendar: Calendar
    ) -> Int {
        let weekStarts: Set<Date> = Set(swims.compactMap {
            calendar.dateInterval(of: .weekOfYear, for: $0.start)?.start
        })
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: asOf)?.start else { return 0 }

        var streak = 0
        var isCurrentWeek = true
        while true {
            if weekStarts.contains(cursor) {
                streak += 1
            } else if !isCurrentWeek {
                break
            }
            isCurrentWeek = false
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
