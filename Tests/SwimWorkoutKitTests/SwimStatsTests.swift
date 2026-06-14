// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import SwimWorkoutKit

@Suite("SwimStats")
struct SwimStatsTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    /// June 2026: the 1st is a Monday (UTC).
    private func date(_ day: Int, _ month: Int = 6, hour: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func swim(_ day: Int, month: Int = 6, meters: Double = 2000, kcal: Double = 400, minutes: Double = 45) -> RecordedSwim {
        RecordedSwim(
            id: UUID(),
            start: date(day, month),
            end: date(day, month).addingTimeInterval(minutes * 60),
            distanceMeters: meters,
            activeEnergyKcal: kcal,
            sourceBundleID: "test", sourceName: "Test"
        )
    }

    @Test("Summary adds up")
    func summary() {
        let result = SwimStats.summary(of: [swim(1), swim(2, meters: 1500, kcal: 300)])
        #expect(result.count == 2)
        #expect(result.distanceMeters == 3500)
        #expect(result.activeEnergyKcal == 700)
        #expect(result.duration == 90 * 60)
    }

    @Test("Day buckets cover the whole range, empty days included")
    func dayBuckets() {
        let range = DateInterval(start: date(1, hour: 0), end: date(8, hour: 0))
        let buckets = SwimStats.buckets(
            of: [swim(2), swim(2, meters: 1000), swim(5)],
            unit: .day, in: range, calendar: calendar
        )
        #expect(buckets.count == 7)
        #expect(buckets[1].summary.count == 2)
        #expect(buckets[1].summary.distanceMeters == 3000)
        #expect(buckets[4].summary.count == 1)
        #expect(buckets[0].summary == .zero)
        #expect(buckets[6].summary == .zero)
    }

    @Test("Month buckets across a year")
    func monthBuckets() {
        let range = DateInterval(
            start: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!,
            end: calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        )
        let buckets = SwimStats.buckets(
            of: [swim(10, month: 2), swim(11, month: 2), swim(3, month: 6)],
            unit: .month, in: range, calendar: calendar
        )
        #expect(buckets.count == 12)
        #expect(buckets[1].summary.count == 2)
        #expect(buckets[5].summary.count == 1)
        #expect(buckets[7].summary == .zero)
    }

    @Test("Weekly streak counts back from now; current week is grace")
    func streak() {
        // Swims in the weeks of Jun 1, Jun 8, Jun 15 — checked on Jun 17 (week of Jun 15).
        let swims = [swim(2), swim(9), swim(16)]
        #expect(SwimStats.weeklyStreak(of: swims, asOf: date(17), calendar: calendar) == 3)
        // Checked during the NEXT week (Jun 22–28) with no swim yet: streak holds at 3.
        #expect(SwimStats.weeklyStreak(of: swims, asOf: date(24), calendar: calendar) == 3)
        // A gap week (no swim Jun 8 week) breaks it.
        let gappy = [swim(2), swim(16)]
        #expect(SwimStats.weeklyStreak(of: gappy, asOf: date(17), calendar: calendar) == 1)
        // No swims at all.
        #expect(SwimStats.weeklyStreak(of: [], asOf: date(17), calendar: calendar) == 0)
    }
}
