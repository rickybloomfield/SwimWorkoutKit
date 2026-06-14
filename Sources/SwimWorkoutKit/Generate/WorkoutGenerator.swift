// SPDX-License-Identifier: MIT

import Foundation

/// Deterministic seeded RNG (SplitMix64) so generation is reproducible:
/// same request + same seed → identical workout. "Shuffle" = new seed.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public struct GeneratorRequest: Sendable {
    public var course: Course
    public var targetDistance: Int
    public var category: WorkoutCategory
    /// Optional stroke focus (stroke/IM categories use it heavily).
    public var strokeEmphasis: Stroke?
    /// Lane groups; groups with a base pace get computed send-offs.
    public var groups: [SpeedGroup]
    public var equipment: Set<Equipment>
    public var seed: UInt64
    public var title: String?

    public init(
        course: Course = .scy,
        targetDistance: Int = 3000,
        category: WorkoutCategory = .basic,
        strokeEmphasis: Stroke? = nil,
        groups: [SpeedGroup] = [],
        equipment: Set<Equipment> = [],
        seed: UInt64 = 1,
        title: String? = nil
    ) {
        self.course = course
        self.targetDistance = targetDistance
        self.category = category
        self.strokeEmphasis = strokeEmphasis
        self.groups = groups
        self.equipment = equipment
        self.seed = seed
        self.title = title
    }
}

/// Template-based workout generation. Instant, offline, deterministic —
/// the structural patterns mirror the real coach corpus (sprint ladders with
/// easy kick between, distance blocks with short rest, IM rotations…).
/// Totals land exactly on the target.
public enum WorkoutGenerator {

    public static func generate(_ request: GeneratorRequest) -> Workout {
        var ctx = Context(request: request)

        // Budget split (multiples of 100; cooldown absorbs nothing — main does).
        let target = max(600, (request.targetDistance / 50) * 50)
        var warmupBudget = clamp(((Int(0.18 * Double(target)) / 100) * 100), 300, 1000)
        var cooldownBudget = clamp(((Int(0.07 * Double(target)) / 100) * 100), 100, 300)
        if target <= 1200 {
            warmupBudget = 200
            cooldownBudget = 100
        }
        let mainBudget = target - warmupBudget - cooldownBudget

        let warmup = buildWarmup(budget: warmupBudget, ctx: &ctx)
        let main = buildMain(budget: mainBudget, ctx: &ctx)
        let cooldown = buildCooldown(budget: cooldownBudget, ctx: &ctx)

        var workout = Workout(
            title: request.title ?? defaultTitle(request: request, target: target),
            course: request.course,
            categories: [request.category.rawValue],
            groups: request.groups,
            sections: [
                WorkoutSection(name: "Warmup", statedDistance: warmupBudget, items: warmup),
                WorkoutSection(name: "Main Set", statedDistance: mainBudget, items: main),
                WorkoutSection(name: "Cool Down", statedDistance: cooldownBudget, items: cooldown),
            ],
            source: WorkoutSource(kind: .generated, attribution: "SwimWorkoutKit generator"),
            statedTotal: target
        )
        workout.notes = nil
        return workout
    }

    private static func defaultTitle(request: GeneratorRequest, target: Int) -> String {
        let category: String
        switch request.category {
        case .im: category = "IM"
        case .openWater: category = "Open Water"
        case .lowVolume: category = "Low Volume"
        default: category = request.category.rawValue.capitalized
        }
        if let emphasis = request.strokeEmphasis, request.category == .stroke {
            return "\(emphasis.rawValue.capitalized) Stroke \(target.formatted())"
        }
        return "\(category) \(target.formatted())"
    }

    // MARK: - Context

    private struct Context {
        let request: GeneratorRequest
        var rng: SeededGenerator
        let paceModel = PaceModel.default

        init(request: GeneratorRequest) {
            self.request = request
            self.rng = SeededGenerator(seed: request.seed)
        }

        mutating func pickEmphasis() -> Stroke {
            request.strokeEmphasis ?? pick([.fly, .back, .breast])
        }

        mutating func pick<T>(_ options: [T]) -> T {
            options[Int(rng.next() % UInt64(options.count))]
        }

        var hasPaces: Bool {
            request.groups.contains { $0.basePace100 != nil }
        }

        /// Send-off interval per lane for a work set; rest-based fallback.
        mutating func interval(
            distance: Int, stroke: Stroke?, activity: Activity?, targetRest: Int
        ) -> Interval {
            guard hasPaces else {
                return Interval(mode: .rest, rest: SwimTime(seconds: max(10, targetRest)))
            }
            var sendoffs: [String: SwimTime] = [:]
            for group in request.groups {
                if let sendoff = paceModel.suggestedSendoff(
                    distance: distance, stroke: stroke, activity: activity,
                    basePace100: group.basePace100,
                    targetRest: SwimTime(seconds: targetRest)
                ) {
                    sendoffs[group.id] = sendoff
                }
            }
            guard !sendoffs.isEmpty else {
                return Interval(mode: .rest, rest: SwimTime(seconds: max(10, targetRest)))
            }
            return Interval(
                mode: .sendoff, sendoffs: sendoffs,
                targetRest: SwimTime(seconds: targetRest)
            )
        }
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), high)
    }

    // MARK: - Warmup

    private static func buildWarmup(budget: Int, ctx: inout Context) -> [WorkoutItem] {
        var items: [WorkoutItem] = []
        var remaining = budget

        // Opening straight swim: ~40-50% of the warmup, rounded to 100.
        let opener = clamp((budget * 4 / 10) / 100 * 100, 100, 500)
        if ctx.pick([true, false]) && opener >= 300 {
            items.append(.set(SwimSet(
                reps: 1, distance: opener, stroke: .free,
                note: "every 3rd length something different"
            )))
        } else {
            items.append(.set(SwimSet(reps: 1, distance: opener, stroke: .choice, note: "loosen")))
        }
        remaining -= opener

        // Kick/pull/drill middle in 100/200 chunks.
        if remaining >= 200 {
            let pull = remaining >= 400 ? 200 : 100
            items.append(.set(SwimSet(reps: 1, distance: pull, activity: .pull,
                                      equipment: ctx.request.equipment.contains(.buoy) ? [.buoy] : nil)))
            remaining -= pull
        }
        if remaining >= 200 {
            items.append(.set(SwimSet(reps: 4, distance: 50, stroke: ctx.pick([.choice, .imo]), activity: .kick)))
            remaining -= 200
        }
        while remaining >= 100 {
            items.append(.set(SwimSet(reps: 4, distance: 25, stroke: .choice, activity: .drill)))
            remaining -= 100
        }
        if remaining >= 50 {
            items.append(.set(SwimSet(reps: 1, distance: remaining, stroke: .choice)))
        }
        return items
    }

    // MARK: - Cool down

    private static func buildCooldown(budget: Int, ctx: inout Context) -> [WorkoutItem] {
        [.set(SwimSet(
            reps: 1, distance: budget, stroke: .choice,
            effort: Effort(level: .easy),
            note: ctx.pick(["smooth", "long and loose", "easy peasy"])
        ))]
    }

    // MARK: - Main set dispatch

    private static func buildMain(budget: Int, ctx: inout Context) -> [WorkoutItem] {
        switch ctx.request.category {
        case .sprint, .test:
            return sprintMain(budget: budget, ctx: &ctx)
        case .distance, .openWater:
            return distanceMain(budget: budget, ctx: &ctx)
        case .im:
            return imMain(budget: budget, ctx: &ctx)
        case .stroke:
            return strokeMain(budget: budget, ctx: &ctx)
        case .kick:
            return kickMain(budget: budget, ctx: &ctx)
        case .basic, .lowVolume, .triathlon:
            return basicMain(budget: budget, ctx: &ctx)
        }
    }

    /// Appends easy-50 filler to consume any sub-block remainder exactly.
    private static func filler(_ remaining: Int, ctx: inout Context) -> [WorkoutItem] {
        guard remaining > 0 else { return [] }
        var items: [WorkoutItem] = []
        if remaining >= 50 {
            let reps = remaining / 50
            items.append(.set(SwimSet(
                reps: reps, distance: 50, stroke: .choice,
                effort: Effort(level: .easy), note: "shake it out"
            )))
        }
        return items
    }

    /// Sprint: descend ladders with easy kick recoveries — the Friday pattern.
    private static func sprintMain(budget: Int, ctx: inout Context) -> [WorkoutItem] {
        var items: [WorkoutItem] = []
        var remaining = budget
        var menu: [(dist: Int, reps: ClosedRange<Int>, percent: Int, rest: Int)] = [
            (50, 4...8, 100, 20),
            (100, 3...6, 95, 20),
            (200, 2...4, 90, 30),
            (50, 2...4, 100, 25),
        ]
        menu.shuffle(using: &ctx.rng)
        var menuIndex = 0
        var misses = 0

        while remaining >= 300, misses < menu.count {
            let item = menu[menuIndex % menu.count]
            menuIndex += 1
            // An item whose minimum doesn't fit is skipped, never force-fit.
            let maxFit = (remaining - 100) / item.dist
            guard maxFit >= item.reps.lowerBound else {
                misses += 1
                continue
            }
            misses = 0
            let reps = min(maxFit, item.reps.upperBound)
            let interval = ctx.interval(
                distance: item.dist, stroke: .choice, activity: .swim, targetRest: item.rest
            )
            items.append(.set(SwimSet(
                reps: reps, distance: item.dist, stroke: .choice,
                effort: Effort(shape: .descend, percent: item.percent),
                interval: interval
            )))
            remaining -= reps * item.dist
            if remaining >= 100 {
                items.append(.set(SwimSet(
                    reps: 1, distance: 100, activity: .kick,
                    effort: Effort(level: .easy),
                    interval: .rest(SwimTime(seconds: 60))
                )))
                remaining -= 100
            }
        }
        items.append(contentsOf: filler(remaining, ctx: &ctx))
        return items
    }

    /// Distance: long free blocks on short rest, sparse recoveries.
    private static func distanceMain(budget: Int, ctx: inout Context) -> [WorkoutItem] {
        var items: [WorkoutItem] = []
        var remaining = budget
        var menu: [(dist: Int, reps: ClosedRange<Int>, percent: Int, rest: Int)] = [
            (300, 2...4, 80, 30),
            (200, 3...5, 85, 20),
            (400, 2...3, 80, 40),
            (100, 4...8, 90, 15),
        ]
        menu.shuffle(using: &ctx.rng)
        var menuIndex = 0
        var blocksSinceRecovery = 0
        var misses = 0

        while remaining >= 400, misses < menu.count {
            let item = menu[menuIndex % menu.count]
            menuIndex += 1
            let reserve = blocksSinceRecovery >= 1 ? 100 : 0
            let maxFit = (remaining - reserve) / item.dist
            guard maxFit >= item.reps.lowerBound else {
                misses += 1
                continue
            }
            misses = 0
            let reps = min(maxFit, item.reps.upperBound)
            items.append(.set(SwimSet(
                reps: reps, distance: item.dist, stroke: .free,
                effort: Effort(shape: ctx.pick([.descend, .steady]), percent: item.percent),
                breath: ctx.pick([nil, Breath(pattern: "3-5")]),
                interval: ctx.interval(distance: item.dist, stroke: .free, activity: .swim, targetRest: item.rest)
            )))
            remaining -= reps * item.dist
            blocksSinceRecovery += 1
            if blocksSinceRecovery >= 2, remaining >= 100 {
                items.append(.set(SwimSet(
                    reps: 1, distance: 100, stroke: .choice,
                    effort: Effort(level: .easy),
                    interval: .rest(SwimTime(seconds: 60))
                )))
                remaining -= 100
                blocksSinceRecovery = 0
            }
        }
        items.append(contentsOf: filler(remaining, ctx: &ctx))
        return items
    }

    /// IM: rounds of IMO work + IM swims — the Wednesday rotation.
    private static func imMain(budget: Int, ctx: inout Context) -> [WorkoutItem] {
        // Round bundle: 4×75 IMO (kick/drill/swim) + 100 IM + 4×50 stroke desc + 100 easy = 700.
        let bundle: [WorkoutItem] = [
            .set(SwimSet(
                reps: 4, distance: 75, stroke: .imo,
                interval: .rest(SwimTime(seconds: 20)),
                segments: [
                    Segment(distance: 25, activity: .kick),
                    Segment(distance: 25, activity: .drill),
                    Segment(distance: 25, activity: .swim),
                ]
            )),
            .set(SwimSet(
                reps: 1, distance: 100, stroke: .im,
                effort: Effort(level: .sprint),
                interval: ctx.interval(distance: 100, stroke: .im, activity: .swim, targetRest: 15)
            )),
            .set(SwimSet(
                reps: 4, distance: 50, stroke: .imo,
                effort: Effort(shape: .descend),
                interval: ctx.interval(distance: 50, stroke: .stroke, activity: .swim, targetRest: 15)
            )),
            .set(SwimSet(
                reps: 1, distance: 100, stroke: .choice,
                effort: Effort(level: .easy),
                interval: .rest(SwimTime(seconds: 60))
            )),
        ]
        let bundleCost = 700
        var items: [WorkoutItem] = []
        var remaining = budget
        let rounds = max(1, remaining / bundleCost)
        if rounds > 1 {
            items.append(.repeatBlock(RepeatBlock(rounds: rounds, items: bundle)))
        } else {
            items.append(contentsOf: bundle)
        }
        remaining -= rounds * bundleCost

        while remaining >= 100 {
            items.append(.set(SwimSet(
                reps: 1, distance: 100, stroke: .im,
                effort: Effort(level: .max),
                interval: .rest(SwimTime(seconds: 45))
            )))
            remaining -= 100
        }
        items.append(contentsOf: filler(remaining, ctx: &ctx))
        return items
    }

    /// Stroke: emphasis-stroke technique rounds with free recovery.
    private static func strokeMain(budget: Int, ctx: inout Context) -> [WorkoutItem] {
        let stroke = ctx.pickEmphasis()
        let fins = ctx.request.equipment.contains(.fins) && (stroke == .fly || stroke == .back)
        // Bundle: 2×75 kick/drill/kick + 4×50 desc + 100 free easy = 450.
        let bundle: [WorkoutItem] = [
            .set(SwimSet(
                reps: 2, distance: 75, stroke: stroke,
                equipment: fins ? [.fins] : nil,
                interval: ctx.interval(distance: 75, stroke: stroke, activity: .drill, targetRest: 20),
                segments: [
                    Segment(distance: 25, activity: .kick),
                    Segment(distance: 25, activity: .drill),
                    Segment(distance: 25, activity: .kick),
                ]
            )),
            .set(SwimSet(
                reps: 4, distance: 50, stroke: stroke,
                effort: Effort(shape: .descend, detail: "1-4"),
                interval: ctx.interval(distance: 50, stroke: stroke, activity: .swim, targetRest: 20)
            )),
            .set(SwimSet(
                reps: 1, distance: 100, stroke: .free,
                effort: Effort(level: .easy),
                interval: .rest(SwimTime(seconds: 30))
            )),
        ]
        let bundleCost = 450
        var items: [WorkoutItem] = []
        var remaining = budget
        let rounds = max(1, remaining / bundleCost)
        if rounds > 1 {
            items.append(.repeatBlock(RepeatBlock(rounds: rounds, items: bundle)))
        } else {
            items.append(contentsOf: bundle)
        }
        remaining -= rounds * bundleCost

        while remaining >= 100 {
            items.append(.set(SwimSet(
                reps: 4, distance: 25, stroke: stroke,
                effort: Effort(level: .sprint),
                interval: ctx.interval(distance: 25, stroke: stroke, activity: .swim, targetRest: 20)
            )))
            remaining -= 100
        }
        items.append(contentsOf: filler(remaining, ctx: &ctx))
        return items
    }

    /// Kick: board/fins ladders with swim recovery.
    private static func kickMain(budget: Int, ctx: inout Context) -> [WorkoutItem] {
        var items: [WorkoutItem] = []
        var remaining = budget
        let fins = ctx.request.equipment.contains(.fins)
        let board = ctx.request.equipment.contains(.board)
        var menu: [(dist: Int, reps: ClosedRange<Int>, rest: Int)] = [
            (50, 4...8, 15),
            (100, 3...5, 20),
            (25, 4...8, 15),
        ]
        menu.shuffle(using: &ctx.rng)
        var menuIndex = 0
        var misses = 0

        while remaining >= 300, misses < menu.count {
            let item = menu[menuIndex % menu.count]
            menuIndex += 1
            let maxFit = (remaining - 100) / item.dist
            guard maxFit >= item.reps.lowerBound else {
                misses += 1
                continue
            }
            misses = 0
            let reps = min(maxFit, item.reps.upperBound)
            items.append(.set(SwimSet(
                reps: reps, distance: item.dist, stroke: .choice, activity: .kick,
                equipment: fins ? [.fins] : (board ? [.board] : nil),
                effort: Effort(shape: .descend),
                interval: ctx.interval(distance: item.dist, stroke: .choice, activity: .kick, targetRest: item.rest)
            )))
            remaining -= reps * item.dist
            if remaining >= 100 {
                items.append(.set(SwimSet(
                    reps: 1, distance: 100, stroke: .free,
                    effort: Effort(level: .smooth),
                    interval: .rest(SwimTime(seconds: 30))
                )))
                remaining -= 100
            }
        }
        items.append(contentsOf: filler(remaining, ctx: &ctx))
        return items
    }

    /// Basic / triathlon / low-volume: balanced free + technique halves.
    private static func basicMain(budget: Int, ctx: inout Context) -> [WorkoutItem] {
        var items: [WorkoutItem] = []
        var remaining = budget

        // Half 1: steady free quality block(s).
        let freeBudget = (budget * 6 / 10) / 100 * 100
        var freeRemaining = freeBudget
        let unit = ctx.pick([100, 150, 200])
        while freeRemaining >= unit {
            let reps = clamp(freeRemaining / unit, 1, ctx.request.category == .triathlon ? 6 : 4)
            items.append(.set(SwimSet(
                reps: reps, distance: unit, stroke: .free,
                effort: Effort(
                    shape: ctx.pick([.descend, .steady]),
                    percent: ctx.request.category == .triathlon ? 85 : 90
                ),
                interval: ctx.interval(distance: unit, stroke: .free, activity: .swim, targetRest: 15)
            )))
            freeRemaining -= reps * unit
        }
        remaining -= (freeBudget - freeRemaining)

        // Recovery between halves.
        if remaining >= 100 {
            items.append(.set(SwimSet(
                reps: 1, distance: 100, stroke: .choice,
                effort: Effort(level: .easy),
                interval: .rest(SwimTime(seconds: 60))
            )))
            remaining -= 100
        }

        // Half 2: technique 50s.
        while remaining >= 200 {
            items.append(.set(SwimSet(
                reps: 4, distance: 50, stroke: .choice,
                interval: ctx.interval(distance: 50, stroke: .choice, activity: .drill, targetRest: 15),
                segments: [
                    Segment(distance: 25, activity: .drill),
                    Segment(distance: 25, activity: .swim, effortLevel: .strong),
                ]
            )))
            remaining -= 200
        }
        items.append(contentsOf: filler(remaining, ctx: &ctx))
        return items
    }
}
