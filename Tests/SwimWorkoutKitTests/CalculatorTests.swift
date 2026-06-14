// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("Calculator")
struct CalculatorTests {

    private let groups = [
        SpeedGroup(id: "A", basePace100: SwimTime(seconds: 75)),
        SpeedGroup(id: "B", basePace100: SwimTime(seconds: 85)),
        SpeedGroup(id: "C"),
        SpeedGroup(id: "D"),
    ]

    @Test("Sparse send-off resolution: exact, faster-neighbor, slower-neighbor")
    func sendoffResolution() {
        let sendoffs: [String: SwimTime] = [
            "A": SwimTime(seconds: 90),
            "B": SwimTime(seconds: 105),
            "C": SwimTime(seconds: 120),
        ]
        #expect(WorkoutCalculator.resolveSendoff(sendoffs, groupID: "B", groups: groups)?.seconds == 105)
        // D missing → nearest faster listed group is C.
        #expect(WorkoutCalculator.resolveSendoff(sendoffs, groupID: "D", groups: groups)?.seconds == 120)
        // Only-slower-specified fallback.
        let lateOnly: [String: SwimTime] = ["C": SwimTime(seconds: 120)]
        #expect(WorkoutCalculator.resolveSendoff(lateOnly, groupID: "A", groups: groups)?.seconds == 120)
        // Unspecified group: first listed value in group order.
        #expect(WorkoutCalculator.resolveSendoff(sendoffs, groupID: nil, groups: groups)?.seconds == 90)
    }

    @Test("Distance with repeats, per-group overrides, and group filters")
    func distances() {
        let workout = Workout(
            course: .scy,
            groups: groups,
            sections: [
                WorkoutSection(name: "Main", items: [
                    .set(SwimSet(reps: 4, distance: 100)),
                    .set(SwimSet(reps: 4, distance: 50, perGroup: ["D": GroupOverride(reps: 3)])),
                    .set(SwimSet(reps: 2, distance: 100, groupFilter: ["A"])),
                    .repeatBlock(RepeatBlock(
                        rounds: 4,
                        roundsPerGroup: ["A": 4, "B": 3],
                        items: [.set(SwimSet(reps: 1, distance: 200))]
                    )),
                    .rest(RestItem(duration: SwimTime(seconds: 120))),
                ])
            ]
        )
        // A: 400 + 200 + 200 + 800 = 1600
        #expect(WorkoutCalculator.distance(of: workout, group: "A") == 1600)
        // B: 400 + 200 + 0 + 600 = 1200
        #expect(WorkoutCalculator.distance(of: workout, group: "B") == 1200)
        // C: roundsPerGroup sparse → B's 3 rounds: 400 + 200 + 600 = 1200
        #expect(WorkoutCalculator.distance(of: workout, group: "C") == 1200)
        // D: reps override 3×50: 400 + 150 + 600 = 1150
        #expect(WorkoutCalculator.distance(of: workout, group: "D") == 1150)
    }

    @Test("Duration: send-offs are exact; rest-based uses the pace model")
    func durations() {
        let workout = Workout(
            course: .scy,
            groups: groups,
            sections: [
                WorkoutSection(name: "Main", items: [
                    .set(SwimSet(
                        reps: 10, distance: 100,
                        interval: Interval(mode: .sendoff, sendoffs: [
                            "A": SwimTime(seconds: 90), "B": SwimTime(seconds: 100),
                        ])
                    )),
                    .rest(RestItem(duration: SwimTime(seconds: 60))),
                ])
            ]
        )
        let a = WorkoutCalculator.duration(of: workout, group: "A")
        #expect(a.seconds == 10 * 90 + 60)
        #expect(a.complete)
        let b = WorkoutCalculator.duration(of: workout, group: "B")
        #expect(b.seconds == 10 * 100 + 60)
    }

    @Test("Rest-based duration is incomplete without a base pace")
    func incompleteDuration() {
        let workout = Workout(
            groups: [SpeedGroup(id: "X")],
            sections: [
                WorkoutSection(name: "Main", items: [
                    .set(SwimSet(reps: 4, distance: 100, interval: .rest(SwimTime(seconds: 30))))
                ])
            ]
        )
        let result = WorkoutCalculator.duration(of: workout, group: "X")
        #expect(!result.complete)
    }

    @Test("Pace model estimates respect activity and stroke multipliers")
    func paceModel() {
        let model = PaceModel.default
        let base = SwimTime(seconds: 80)
        let free = model.estimateSeconds(distance: 100, stroke: .free, activity: .swim, basePace100: base)
        let kick = model.estimateSeconds(distance: 100, stroke: .free, activity: .kick, basePace100: base)
        #expect(free == 80)
        #expect(kick == 120) // 80 × 1.45 = 116 → rounds up to 120
        #expect(model.estimateSeconds(distance: 100, stroke: .free, activity: .swim, basePace100: nil) == nil)
    }

    @Test("Totals enumerate groups")
    func totals() {
        let workout = Workout(
            groups: [SpeedGroup(id: "A"), SpeedGroup(id: "B")],
            sections: [
                WorkoutSection(name: "Main", items: [.set(SwimSet(reps: 2, distance: 100))])
            ]
        )
        let totals = WorkoutCalculator.totals(of: workout)
        #expect(totals.count == 2)
        #expect(totals.allSatisfy { $0.distance == 200 })
    }
}
