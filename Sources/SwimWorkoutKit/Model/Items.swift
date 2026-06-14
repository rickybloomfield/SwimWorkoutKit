// SPDX-License-Identifier: MIT

import Foundation

/// One element of a section: a set, a nested repeat block, an explicit rest, or a note.
/// Encoded with a `"type"` discriminator: `set` | `repeat` | `rest` | `note`.
public enum WorkoutItem: Codable, Sendable, Equatable {
    case set(SwimSet)
    case repeatBlock(RepeatBlock)
    case rest(RestItem)
    case note(NoteItem)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum Kind: String, Codable {
        case set
        case repeatBlock = "repeat"
        case rest
        case note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .set: self = .set(try SwimSet(from: decoder))
        case .repeatBlock: self = .repeatBlock(try RepeatBlock(from: decoder))
        case .rest: self = .rest(try RestItem(from: decoder))
        case .note: self = .note(try NoteItem(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .set(let value):
            try container.encode(Kind.set, forKey: .type)
            try value.encode(to: encoder)
        case .repeatBlock(let value):
            try container.encode(Kind.repeatBlock, forKey: .type)
            try value.encode(to: encoder)
        case .rest(let value):
            try container.encode(Kind.rest, forKey: .type)
            try value.encode(to: encoder)
        case .note(let value):
            try container.encode(Kind.note, forKey: .type)
            try value.encode(to: encoder)
        }
    }
}

/// The workhorse: `reps × distance` with stroke/activity/effort/interval and
/// optional intra-rep segments, per-rep and per-group variations.
public struct SwimSet: Codable, Sendable, Equatable {
    public var reps: Int
    /// Distance of one rep, in course units.
    public var distance: Int
    public var stroke: Stroke?
    public var activity: Activity?
    /// Named drill ("scull", "RIMO drill", "IM transitions", "uwdk"…)
    public var drillName: String?
    public var equipment: [Equipment]?
    public var effort: Effort?
    public var breath: Breath?
    public var interval: Interval?
    /// Intra-rep structure: "75 as 25 kick / 25 drill / 25 swim". Distances must sum to `distance`.
    public var segments: [Segment]?
    /// Per-rep variations: odds/evens, "#1 …", "desc 1-4".
    public var perRep: [PerRep]?
    /// Per-group overrides of reps/distance/interval (covers "600 or 800", "4 or 3x" volume splits).
    public var perGroup: [String: GroupOverride]?
    /// If present, this item applies only to the listed group ids (covers "G2"-only lines).
    public var groupFilter: [String]?
    public var label: String?
    public var note: String?
    /// Verbatim original line (OCR or import); never lost.
    public var sourceText: String?

    public init(
        reps: Int,
        distance: Int,
        stroke: Stroke? = nil,
        activity: Activity? = nil,
        drillName: String? = nil,
        equipment: [Equipment]? = nil,
        effort: Effort? = nil,
        breath: Breath? = nil,
        interval: Interval? = nil,
        segments: [Segment]? = nil,
        perRep: [PerRep]? = nil,
        perGroup: [String: GroupOverride]? = nil,
        groupFilter: [String]? = nil,
        label: String? = nil,
        note: String? = nil,
        sourceText: String? = nil
    ) {
        self.reps = reps
        self.distance = distance
        self.stroke = stroke
        self.activity = activity
        self.drillName = drillName
        self.equipment = equipment
        self.effort = effort
        self.breath = breath
        self.interval = interval
        self.segments = segments
        self.perRep = perRep
        self.perGroup = perGroup
        self.groupFilter = groupFilter
        self.label = label
        self.note = note
        self.sourceText = sourceText
    }

    /// The activity worth surfacing in text and displays: any explicit non-swim
    /// activity, or an explicit `swim` only when no stroke is set.
    ///
    /// A strokeless "swim" is a meaningful choice the swimmer typed (swim, stroke
    /// unspecified) and should round-trip; "free swim" is redundant, and the
    /// generator pairs `swim` with a stroke as the implicit default — suppressing
    /// that keeps ordinary sets clean. `.mixed` is never surfaced here (it's
    /// resolved per segment/rep).
    public var significantActivity: Activity? {
        guard let activity, activity != .mixed else { return nil }
        if activity == .swim, stroke != nil { return nil }
        return activity
    }
}

public struct Segment: Codable, Sendable, Equatable {
    public var distance: Int
    public var stroke: Stroke?
    public var activity: Activity?
    public var effortLevel: EffortLevel?
    public var note: String?

    public init(
        distance: Int,
        stroke: Stroke? = nil,
        activity: Activity? = nil,
        effortLevel: EffortLevel? = nil,
        note: String? = nil
    ) {
        self.distance = distance
        self.stroke = stroke
        self.activity = activity
        self.effortLevel = effortLevel
        self.note = note
    }
}

/// Effort descriptor. Shape (progression) and level (intensity) are independent;
/// percent expresses "% effort" notation, optionally as a range.
public struct Effort: Codable, Sendable, Equatable {
    public var shape: EffortShape?
    public var level: EffortLevel?
    public var percent: Int?
    public var percentMax: Int?
    /// Free-form detail: "desc 1-4", "by 25", "build to MAX".
    public var detail: String?

    public init(
        shape: EffortShape? = nil,
        level: EffortLevel? = nil,
        percent: Int? = nil,
        percentMax: Int? = nil,
        detail: String? = nil
    ) {
        self.shape = shape
        self.level = level
        self.percent = percent
        self.percentMax = percentMax
        self.detail = detail
    }

    public var isEmpty: Bool {
        shape == nil && level == nil && percent == nil && percentMax == nil && detail == nil
    }
}

/// Breathing prescription: a per-25 pattern ("3/4/4/5") or "breathe every N".
public struct Breath: Codable, Sendable, Equatable {
    public var pattern: String?
    public var every: Int?

    public init(pattern: String? = nil, every: Int? = nil) {
        self.pattern = pattern
        self.every = every
    }
}

/// Interval prescription for a set.
///
/// - `sendoff`: leave on a clock time ("@1:30"); per-group times in `sendoffs`.
/// - `rest`: rest a fixed time between reps ("r:20").
/// - `open`: no clock (e.g. cool down).
public struct Interval: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable {
        case sendoff
        case rest
        case open
    }

    public var mode: Mode
    /// Send-off per group id. May be sparse; resolution falls back to the
    /// nearest faster (earlier-listed) specified group, then nearest slower.
    public var sendoffs: [String: SwimTime]?
    /// Rest between reps (mode `rest`).
    public var rest: SwimTime?
    /// "ideally :15 rest" — the rest the send-off is designed to yield.
    public var targetRest: SwimTime?
    /// "max :30 rest".
    public var maxRest: SwimTime?
    /// Slowest listed send-off is a floor, not exact ("@1:25+").
    public var openEnded: Bool?
    public var note: String?

    public init(
        mode: Mode,
        sendoffs: [String: SwimTime]? = nil,
        rest: SwimTime? = nil,
        targetRest: SwimTime? = nil,
        maxRest: SwimTime? = nil,
        openEnded: Bool? = nil,
        note: String? = nil
    ) {
        self.mode = mode
        self.sendoffs = sendoffs
        self.rest = rest
        self.targetRest = targetRest
        self.maxRest = maxRest
        self.openEnded = openEnded
        self.note = note
    }

    public static func sendoff(_ time: SwimTime, group: String) -> Interval {
        Interval(mode: .sendoff, sendoffs: [group: time])
    }

    public static func rest(_ time: SwimTime) -> Interval {
        Interval(mode: .rest, rest: time)
    }
}

/// A per-rep variation. `selector` is `"odd"`, `"even"`, a rep number (`"3"`),
/// or an inclusive range (`"1-4"`).
public struct PerRep: Codable, Sendable, Equatable {
    public var selector: String
    public var stroke: Stroke?
    public var activity: Activity?
    public var effortLevel: EffortLevel?
    public var note: String?

    public init(
        selector: String,
        stroke: Stroke? = nil,
        activity: Activity? = nil,
        effortLevel: EffortLevel? = nil,
        note: String? = nil
    ) {
        self.selector = selector
        self.stroke = stroke
        self.activity = activity
        self.effortLevel = effortLevel
        self.note = note
    }
}

/// Per-group overrides on a set.
public struct GroupOverride: Codable, Sendable, Equatable {
    public var reps: Int?
    public var distance: Int?
    public var sendoff: SwimTime?

    public init(reps: Int? = nil, distance: Int? = nil, sendoff: SwimTime? = nil) {
        self.reps = reps
        self.distance = distance
        self.sendoff = sendoff
    }
}

/// A nested repeat: "3x { … }". Round count may vary per group ("4 or 3x").
public struct RepeatBlock: Codable, Sendable, Equatable {
    public var rounds: Int
    /// Per-group round counts; groups not listed use `rounds`.
    public var roundsPerGroup: [String: Int]?
    public var items: [WorkoutItem]
    public var perRound: [PerRound]?
    public var note: String?
    public var sourceText: String?

    public init(
        rounds: Int,
        roundsPerGroup: [String: Int]? = nil,
        items: [WorkoutItem],
        perRound: [PerRound]? = nil,
        note: String? = nil,
        sourceText: String? = nil
    ) {
        self.rounds = rounds
        self.roundsPerGroup = roundsPerGroup
        self.items = items
        self.perRound = perRound
        self.note = note
        self.sourceText = sourceText
    }
}

/// A per-round variation. `selector` like ``PerRep/selector``.
public struct PerRound: Codable, Sendable, Equatable {
    public var selector: String
    public var stroke: Stroke?
    public var note: String?

    public init(selector: String, stroke: Stroke? = nil, note: String? = nil) {
        self.selector = selector
        self.stroke = stroke
        self.note = note
    }
}

/// Standalone rest between items ("2 minutes rest between sets").
public struct RestItem: Codable, Sendable, Equatable {
    public var duration: SwimTime?
    public var note: String?

    public init(duration: SwimTime? = nil, note: String? = nil) {
        self.duration = duration
        self.note = note
    }
}

/// Free-text annotation that is part of the workout flow (footnotes, reminders).
public struct NoteItem: Codable, Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}
