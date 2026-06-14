// SPDX-License-Identifier: MIT

import Testing
@testable import SwimWorkoutKit

@Suite("WorkoutGenerator")
struct GeneratorTests {

    private let groups = [
        SpeedGroup(id: "A", label: "Lanes 1–2", basePace100: SwimTime(parsing: "1:15")),
        SpeedGroup(id: "B", label: "Lanes 3–4", basePace100: SwimTime(parsing: "1:30")),
        SpeedGroup(id: "C", label: "Lanes 5–6", basePace100: SwimTime(parsing: "1:45")),
    ]

    private static let categories: [WorkoutCategory] = [
        .sprint, .distance, .im, .stroke, .kick, .basic, .triathlon, .openWater, .lowVolume,
    ]
    private static let targets = [1500, 2000, 2500, 3000, 4000, 5000]
    private static let seeds: [UInt64] = [1, 7, 42]

    @Test("Every category × target × seed hits the target exactly and validates",
          arguments: categories, targets)
    func hitsTargets(category: WorkoutCategory, target: Int) {
        for seed in Self.seeds {
            let request = GeneratorRequest(
                course: .scy, targetDistance: target, category: category,
                groups: groups, equipment: [.fins, .buoy, .board], seed: seed
            )
            let workout = WorkoutGenerator.generate(request)
            let distance = WorkoutCalculator.distance(of: workout, group: "A")
            #expect(
                distance == target,
                "\(category.rawValue) \(target) seed \(seed): got \(distance)"
            )
            let errors = WorkoutValidator.validate(workout).filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(category.rawValue) \(target) seed \(seed): \(errors)")
            #expect(workout.statedTotal == target)
            #expect(workout.sections.count == 3)
        }
    }

    @Test("Send-offs are generated from base paces and are plausible")
    func sendoffsFromPaces() {
        let request = GeneratorRequest(
            targetDistance: 3000, category: .sprint, groups: groups, seed: 5
        )
        let workout = WorkoutGenerator.generate(request)
        var sendoffSets = 0
        for step in WorkoutFlattener.steps(for: workout, group: "A") {
            guard case .set(let set) = step.kind,
                  let sendoffs = set.interval?.sendoffs, !sendoffs.isEmpty
            else { continue }
            sendoffSets += 1
            // Slower lanes never get faster send-offs.
            if let a = sendoffs["A"], let c = sendoffs["C"] {
                #expect(a.seconds <= c.seconds)
            }
            // Send-off exceeds a plausible swim time for the fastest lane.
            if let a = sendoffs["A"] {
                let estimate = PaceModel.default.estimateSeconds(
                    distance: set.distance, stroke: set.stroke,
                    activity: set.activity, basePace100: groups[0].basePace100
                )
                if let estimate {
                    #expect(a.seconds >= estimate, "send-off \(a) under estimate \(estimate)")
                }
            }
        }
        #expect(sendoffSets >= 2, "Expected pace-derived send-offs")
    }

    @Test("Without base paces, work sets fall back to rest-based intervals")
    func restFallback() {
        let request = GeneratorRequest(targetDistance: 2500, category: .distance, seed: 3)
        let workout = WorkoutGenerator.generate(request)
        var sawRest = false
        for step in WorkoutFlattener.steps(for: workout, group: nil) {
            if case .set(let set) = step.kind, set.interval?.mode == .rest {
                sawRest = true
            }
            if case .set(let set) = step.kind {
                #expect(set.interval?.sendoffs == nil)
            }
        }
        #expect(sawRest)
    }

    @Test("Same seed reproduces; different seeds vary")
    func determinism() {
        let base = GeneratorRequest(targetDistance: 3000, category: .sprint, groups: groups, seed: 11)
        let first = WorkoutGenerator.generate(base)
        let second = WorkoutGenerator.generate(base)
        #expect(first == second)

        var other = base
        other.seed = 12
        let third = WorkoutGenerator.generate(other)
        #expect(first != third, "Different seeds should usually differ")
    }

    @Test("Stroke emphasis is honored")
    func emphasis() {
        let request = GeneratorRequest(
            targetDistance: 2500, category: .stroke, strokeEmphasis: .fly,
            groups: groups, seed: 9
        )
        let workout = WorkoutGenerator.generate(request)
        var flySets = 0
        for step in WorkoutFlattener.steps(for: workout, group: "A") {
            if case .set(let set) = step.kind, set.stroke == .fly {
                flySets += 1
            }
        }
        #expect(flySets >= 2)
        #expect(workout.title?.contains("Fly") == true)
    }

    @Test("All distances fit the course")
    func courseFit() {
        for course in [Course.scy, .scm, .lcm] {
            let request = GeneratorRequest(
                course: course, targetDistance: 3000, category: .basic, seed: 2
            )
            let workout = WorkoutGenerator.generate(request)
            let issues = WorkoutValidator.validate(workout)
            if course == .lcm {
                // 25/50/75-based templates may warn in a 50m pool; errors never.
                #expect(!issues.contains { $0.severity == .error })
            } else {
                #expect(!issues.contains { $0.code == "distance-course-mismatch" }, "\(issues)")
            }
        }
    }
}
