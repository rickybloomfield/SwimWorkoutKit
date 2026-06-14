// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("WorkoutScaler")
struct WorkoutScalerTests {

    private func sampleWorkout() -> Workout {
        // 300 warmup + 3×(400) main + 200 cool = 1700
        Workout(
            title: "Sample",
            course: .scy,
            groups: [SpeedGroup(id: "A")],
            sections: [
                WorkoutSection(name: "Warmup", items: [
                    .set(SwimSet(reps: 3, distance: 100)),
                ]),
                WorkoutSection(name: "Main Set", statedDistance: 1200, items: [
                    .repeatBlock(RepeatBlock(rounds: 3, items: [
                        .set(SwimSet(reps: 4, distance: 75)),
                        .set(SwimSet(reps: 2, distance: 50)),
                    ])),
                ]),
                WorkoutSection(name: "Cool Down", items: [
                    .set(SwimSet(reps: 1, distance: 200)),
                ]),
            ],
            statedTotal: 1700
        )
    }

    @Test("Scaling up lands within one smallest-set distance of the target")
    func scaleUp() {
        let scaled = WorkoutScaler.scale(sampleWorkout(), toPrimaryTotal: 2500)
        let total = WorkoutCalculator.distance(of: scaled, group: "A")
        #expect(abs(total - 2500) <= 50, "Got \(total)")
        #expect(scaled.statedTotal == total)
    }

    @Test("Scaling down lands within tolerance and keeps reps positive")
    func scaleDown() {
        let scaled = WorkoutScaler.scale(sampleWorkout(), toPrimaryTotal: 1000)
        let total = WorkoutCalculator.distance(of: scaled, group: "A")
        #expect(abs(total - 1000) <= 50, "Got \(total)")
        var allPositive = true
        func walk(_ items: [WorkoutItem]) {
            for item in items {
                switch item {
                case .set(let set):
                    if set.reps < 1 || set.distance < 1 { allPositive = false }
                case .repeatBlock(let block):
                    if block.rounds < 1 { allPositive = false }
                    walk(block.items)
                case .rest, .note: break
                }
            }
        }
        for section in scaled.sections { walk(section.items) }
        #expect(allPositive)
    }

    @Test("Identity when target equals current")
    func identity() {
        let workout = sampleWorkout()
        let scaled = WorkoutScaler.scale(workout, toPrimaryTotal: 1700)
        #expect(scaled == workout)
    }

    @Test("Stated section distances refresh after scaling")
    func statedSectionsRefresh() {
        let scaled = WorkoutScaler.scale(sampleWorkout(), toPrimaryTotal: 2500)
        let main = scaled.sections[1]
        #expect(main.statedDistance == WorkoutCalculator.distance(of: main, group: "A", groups: scaled.groups))
    }

    @Test("Real fixture scales sanely (Friday Sprint 3200 → 2400)")
    func realFixture() throws {
        let text = """
        == Warmup: 300
        3x100 as swim/kick/pull
        == Main Set
        3x300 free descend to 80% @4:40/4:50/5:00
        100 kick easy r1:00
        4x200 free descend to 90% @3:10/3:20/3:30
        100 kick easy r1:00
        5x100 choice descend to 95% @1:30/1:40/1:50
        100 kick easy r1:00
        6x50 choice descend to 100% @1:00/1:10
        == Cool Down
        100 choice easy
        """
        let workout = SwimTextParser.parse(text).document.workout
        let scaled = WorkoutScaler.scale(workout, toPrimaryTotal: 2400)
        let total = WorkoutCalculator.distance(of: scaled, group: "A")
        #expect(abs(total - 2400) <= 50, "Got \(total)")
        // Send-offs survive scaling.
        var sawSendoff = false
        for section in scaled.sections {
            for item in section.items {
                if case .set(let set) = item, set.interval?.sendoffs?.isEmpty == false {
                    sawSendoff = true
                }
            }
        }
        #expect(sawSendoff)
    }
}

@Suite("SwimTextLine")
struct SwimTextLineTests {

    @Test("Public line API parses and prints round-trip")
    func roundTrip() throws {
        let groups = [SpeedGroup(id: "A"), SpeedGroup(id: "B")]
        let set = try #require(SwimTextLine.parseSet("4x50 fly drill @1:00/1:10 (~:15 rest)", groups: groups))
        #expect(set.stroke == .fly)
        #expect(set.activity == .drill)
        let printed = SwimTextLine.printSet(set)
        let reparsed = try #require(SwimTextLine.parseSet(printed, groups: groups))
        #expect(SwimTextLine.printSet(reparsed) == printed)
    }

    @Test("Rejects non-set lines")
    func rejects() {
        #expect(SwimTextLine.parseSet("warm up easy", groups: []) == nil)
    }
}
