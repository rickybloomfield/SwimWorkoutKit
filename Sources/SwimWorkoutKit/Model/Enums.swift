// SPDX-License-Identifier: MIT

import Foundation

/// What is swum: the stroke axis. Orthogonal to ``Activity``.
public enum Stroke: String, Codable, Sendable, CaseIterable, Hashable {
    case free
    case back
    case breast
    case fly
    case im              // all four, IM order, within one rep
    case imo             // IM order rotating across reps/rounds
    case rimo            // reverse IM order rotating across reps/rounds
    case stroke          // "stroke" = swimmer's non-free specialty
    case choice
    case mixed           // differs per segment/rep; see segments/perRep
}

/// How it is swum: the activity axis. Orthogonal to ``Stroke``.
public enum Activity: String, Codable, Sendable, CaseIterable, Hashable {
    case swim
    case kick
    case pull
    case drill
    case scull
    case mixed           // differs per segment/rep; see segments/perRep
}

public enum Equipment: String, Codable, Sendable, CaseIterable, Hashable {
    case fins
    case paddles
    case buoy
    case snorkel
    case board
}

/// Effort progression across a set (or within a rep, for `build`/`negativeSplit`).
public enum EffortShape: String, Codable, Sendable, CaseIterable, Hashable {
    case steady
    case build               // within each rep: start easy, finish fast
    case descend             // rep 1 → rep N get faster
    case ascend              // rep 1 → rep N get slower (start fast)
    case negativeSplit = "negative-split"
    case variableSprint = "variable-sprint"
}

public enum EffortLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case easy
    case smooth
    case moderate
    case strong
    case fast
    case sprint
    case max
    case race
}

/// Recommended workout categories. `Workout.categories` is an open string list
/// for forward compatibility; these are the known values.
public enum WorkoutCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case sprint
    case distance
    case im
    case stroke
    case kick
    case basic
    case triathlon
    case openWater = "openwater"
    case lowVolume = "lowvolume"
    case test
}

public enum SourceKind: String, Codable, Sendable, CaseIterable, Hashable {
    case manual
    case ocr
    case generated   // parametric generator
    case ai          // Apple Intelligence / LLM
    case imported    // file or text import
}
