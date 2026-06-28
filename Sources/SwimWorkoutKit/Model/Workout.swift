// SPDX-License-Identifier: MIT

import Foundation

/// Top-level Open Swim Workout document. See `Spec/SPEC.md`.
public struct SwimWorkoutDocument: Codable, Sendable, Equatable {
    public static let formatIdentifier = "open-swim-workout"
    public static let currentVersion = "0.2"

    public var format: String
    public var version: String
    public var workout: Workout

    public init(workout: Workout) {
        self.format = Self.formatIdentifier
        self.version = Self.currentVersion
        self.workout = workout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let format = try container.decode(String.self, forKey: .format)
        let version = try container.decode(String.self, forKey: .version)
        guard format == Self.formatIdentifier else {
            throw DecodingError.dataCorruptedError(
                forKey: .format, in: container,
                debugDescription: "Unknown format identifier: \(format)"
            )
        }
        guard version.split(separator: ".").first == Self.currentVersion.split(separator: ".").first else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container,
                debugDescription: "Unsupported major version: \(version)"
            )
        }
        self.format = format
        self.version = version
        self.workout = try container.decode(Workout.self, forKey: .workout)
    }
}

public struct Workout: Codable, Sendable, Equatable {
    public var title: String?
    /// ISO-8601 calendar date (no time), e.g. "2026-06-10".
    public var date: String?
    public var author: String?
    public var team: String?
    /// A coach-authored description of the workout (its focus, intent, or the
    /// day's theme). Distinct from ``notes``, which carries incidental
    /// annotations such as "remember your fins".
    public var description: String?
    /// Where the workout took place (pool / facility). Optional coordinates.
    public var location: WorkoutLocation?
    public var course: Course
    /// Open list; recommended values in ``WorkoutCategory``.
    public var categories: [String]
    public var tags: [String]
    /// Speed groups, ordered fastest → slowest. Empty means a single unnamed group.
    public var groups: [SpeedGroup]
    public var sections: [WorkoutSection]
    public var notes: String?
    public var source: WorkoutSource?
    /// Total distance as stated on the original (used for reconciliation).
    public var statedTotal: Int?

    public init(
        title: String? = nil,
        date: String? = nil,
        author: String? = nil,
        team: String? = nil,
        description: String? = nil,
        course: Course = .scy,
        categories: [String] = [],
        tags: [String] = [],
        groups: [SpeedGroup] = [],
        sections: [WorkoutSection] = [],
        notes: String? = nil,
        source: WorkoutSource? = nil,
        statedTotal: Int? = nil,
        location: WorkoutLocation? = nil
    ) {
        self.title = title
        self.date = date
        self.author = author
        self.team = team
        self.description = description
        self.location = location
        self.course = course
        self.categories = categories
        self.tags = tags
        self.groups = groups
        self.sections = sections
        self.notes = notes
        self.source = source
        self.statedTotal = statedTotal
    }
}

/// Where a workout took place. `name` is required (e.g. a pool or facility
/// name); coordinates and address are optional — a manually typed name has none.
public struct WorkoutLocation: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var latitude: Double?
    public var longitude: Double?
    public var address: String?

    public init(name: String, latitude: Double? = nil, longitude: Double? = nil, address: String? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
    }

    /// True when both coordinates are present and can be mapped.
    public var hasCoordinates: Bool {
        latitude != nil && longitude != nil
    }
}

/// Pool course. SCY (25 yd), SCM (25 m), or LCM (50 m) — or any custom length.
public struct Course: Codable, Sendable, Equatable, Hashable {
    public enum Unit: String, Codable, Sendable, CaseIterable {
        case yards = "yd"
        case meters = "m"
    }

    public var length: Int
    public var unit: Unit

    public init(length: Int, unit: Unit) {
        self.length = length
        self.unit = unit
    }

    public static let scy = Course(length: 25, unit: .yards)
    public static let scm = Course(length: 25, unit: .meters)
    public static let lcm = Course(length: 50, unit: .meters)

    /// Short label: "SCY", "SCM", "LCM", or e.g. "33⅓m" custom → "33m".
    public var label: String {
        switch (length, unit) {
        case (25, .yards): return "SCY"
        case (25, .meters): return "SCM"
        case (50, .meters): return "LCM"
        default: return "\(length)\(unit.rawValue)"
        }
    }

    public init?(label: String) {
        switch label.lowercased() {
        case "scy": self = .scy
        case "scm": self = .scm
        case "lcm": self = .lcm
        default: return nil
        }
    }
}

/// A speed group ("lane"): the unit of interval variation within one workout.
public struct SpeedGroup: Codable, Sendable, Equatable, Identifiable {
    /// Short stable id used in send-off maps: "A", "B", …
    public var id: String
    /// Human label: "Lanes 1–2", "Blue", …
    public var label: String?
    /// Base pace per 100 (free, swim) used for estimates and interval tools.
    public var basePace100: SwimTime?
    public var note: String?

    public init(id: String, label: String? = nil, basePace100: SwimTime? = nil, note: String? = nil) {
        self.id = id
        self.label = label
        self.basePace100 = basePace100
        self.note = note
    }
}

public struct WorkoutSection: Codable, Sendable, Equatable {
    public var name: String
    public var note: String?
    /// Distance as stated on the original (per the fastest/primary group when groups differ).
    public var statedDistance: Int?
    public var items: [WorkoutItem]

    public init(name: String, note: String? = nil, statedDistance: Int? = nil, items: [WorkoutItem] = []) {
        self.name = name
        self.note = note
        self.statedDistance = statedDistance
        self.items = items
    }
}

public struct WorkoutSource: Codable, Sendable, Equatable {
    public var kind: SourceKind
    public var attribution: String?
    /// Reference to an attached original image (filename within the app container / archive).
    public var imageRef: String?

    public init(kind: SourceKind, attribution: String? = nil, imageRef: String? = nil) {
        self.kind = kind
        self.attribution = attribution
        self.imageRef = imageRef
    }
}
