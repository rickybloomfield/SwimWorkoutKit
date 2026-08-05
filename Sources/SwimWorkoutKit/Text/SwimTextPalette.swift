// SPDX-License-Identifier: MIT

import Foundation

/// A semantic slot in the SwimText visual vocabulary.
///
/// This is the *decision* half of theming, kept apart from the *values* half on
/// purpose. Which slot a warmup heading, a `free` token or a `sprint` belongs to
/// is a property of the notation and is the same everywhere; what colour that
/// slot is drawn in belongs to the platform, because `Color.primary` on Apple
/// platforms and `MaterialTheme.colorScheme.onSurface` on Android are the same
/// intent expressed in two vocabularies, and neither can be written as the
/// other's literal.
///
/// So a renderer maps `SwimTextRole` to whatever its own design system calls
/// that slot. `SwimWorkoutKitUI`'s ``SwimTextTheme`` does it for SwiftUI; a
/// Compose or web renderer does the same with its own values, and all of them
/// agree about *which* slot applies because they all ask ``SwimTextPalette``.
public enum SwimTextRole: Sendable, Hashable {
    case plain
    case title
    case repsDistance
    case sendoff
    case rest
    case time
    case note
    case structure
    case metadataKey
    case metadataValue
    case effortShape
    case percent
    case equipment

    case sectionWarmup
    case sectionCooldown
    case sectionDefault

    case stroke(Stroke)
    case activity(Activity)
    case effortLevel(EffortLevel)
}

/// The notation's own view of how SwimText should read.
///
/// Everything here is pure logic over model types — no colours, no platform
/// types — so it compiles anywhere the core does and gives every renderer the
/// same answers. The alternative is each platform re-deriving rules like "a
/// section called *Loosen* is a warmup", which is precisely how two apps that
/// claim to show the same workout start disagreeing about it.
public enum SwimTextPalette {

    // MARK: - Sections

    /// Classifies a section heading.
    ///
    /// Substring matching, not equality: coaches write *Warmup*, *Warm-up*,
    /// *Warm up*, *Loosen*, *Pre-set*, *Cool Down*, *Cooldown*, *Warm Down*.
    /// The list is deliberately generous — a section that reads as a warmup and
    /// is drawn as one is right far more often than it is wrong.
    public static func sectionRole(for name: String) -> SwimTextRole {
        let lower = name.lowercased()
        if lower.contains("warm") || lower.contains("loosen") || lower.contains("pre") {
            // "warm down" is a cool-down that happens to contain "warm", so the
            // down-check has to win over the warm-check for it.
            if lower.contains("down") { return .sectionCooldown }
            return .sectionWarmup
        }
        if lower.contains("cool") || lower.contains("down") {
            return .sectionCooldown
        }
        return .sectionDefault
    }

    // MARK: - Axes

    public static func role(for stroke: Stroke) -> SwimTextRole { .stroke(stroke) }
    public static func role(for activity: Activity) -> SwimTextRole { .activity(activity) }
    public static func role(for level: EffortLevel) -> SwimTextRole { .effortLevel(level) }

    // MARK: - Tokens

    /// The slot a lexer token is drawn in.
    public static func role(for kind: SwimTextTokenKind) -> SwimTextRole {
        switch kind {
        case .title: return .title
        case .section(let name): return sectionRole(for: name)
        case .metadataKey: return .metadataKey
        case .metadataValue: return .metadataValue
        case .repsDistance: return .repsDistance
        case .stroke(let stroke): return .stroke(stroke)
        case .activity(let activity): return .activity(activity)
        case .effortLevel(let level): return .effortLevel(level)
        case .effortShape: return .effortShape
        case .percent: return .percent
        case .equipment: return .equipment
        case .sendoff: return .sendoff
        case .rest: return .rest
        case .time: return .time
        case .note: return .note
        case .structure: return .structure
        }
    }

    /// Whether a token reads with emphasis (heavier weight) when highlighted.
    ///
    /// The four that carry the set: what it is, how far, how many, and on what.
    public static func isEmphasized(_ kind: SwimTextTokenKind) -> Bool {
        switch kind {
        case .title, .section, .repsDistance, .sendoff: return true
        default: return false
        }
    }
}

/// A platform-neutral colour intent.
///
/// Not an RGB value: the standard palette leans on system colours that adapt to
/// light and dark and to accessibility contrast settings, and freezing those
/// into numbers would ship one appearance to every context. A hue names the
/// *family* — "breaststroke reads green" — and each platform picks its own
/// green. That is the level at which two apps can agree without one of them
/// wearing the other's design system.
public enum SwimTextHue: String, Sendable, Codable, Hashable, CaseIterable {
    /// Highest-contrast foreground — Apple's `.primary`, Material's `onSurface`.
    case primary
    /// Muted foreground — Apple's `.secondary`, Material's `onSurfaceVariant`.
    case secondary
    case blue
    case teal
    case green
    case purple
    case orange
    case indigo
    case pink
    case brown
    case mint
    case yellow
    case red
    case gray
}

extension SwimTextRole {

    /// The built-in hue for this slot.
    ///
    /// Colour is never the only cue — labels, weight and shape carry the same
    /// information — so the palette stays legible in black and white and to
    /// colour-blind readers. Effort deliberately runs a green → yellow → red
    /// ramp because that ordering is the one readers already know.
    public var defaultHue: SwimTextHue {
        switch self {
        case .plain, .title, .repsDistance: return .primary
        case .sendoff, .structure: return .blue
        case .rest, .time, .note, .metadataKey, .metadataValue,
             .effortShape, .percent, .equipment: return .secondary

        case .sectionWarmup: return .green
        case .sectionCooldown: return .gray
        case .sectionDefault: return .blue

        case .stroke(let stroke):
            switch stroke {
            case .free: return .blue
            case .back: return .teal
            case .breast: return .green
            case .fly: return .purple
            case .im, .imo, .rimo: return .orange
            case .stroke: return .indigo
            case .choice, .mixed: return .secondary
            }

        case .activity(let activity):
            switch activity {
            case .swim: return .blue
            case .kick: return .orange
            case .pull: return .brown
            case .drill: return .pink
            case .scull: return .mint
            case .mixed: return .secondary
            }

        case .effortLevel(let level):
            switch level {
            case .easy, .smooth: return .green
            case .moderate, .strong: return .yellow
            case .fast, .sprint, .max, .race: return .red
            }
        }
    }
}

// MARK: - Wire form

extension SwimTextRole {

    /// A stable identifier for crossing a language boundary.
    ///
    /// Used by the Android bridge, where the renderer is Kotlin and the role has
    /// to arrive as a string. Stable across releases: these are read by code
    /// that is not compiled with this package.
    public var wireName: String {
        switch self {
        case .plain: return "plain"
        case .title: return "title"
        case .repsDistance: return "repsDistance"
        case .sendoff: return "sendoff"
        case .rest: return "rest"
        case .time: return "time"
        case .note: return "note"
        case .structure: return "structure"
        case .metadataKey: return "metadataKey"
        case .metadataValue: return "metadataValue"
        case .effortShape: return "effortShape"
        case .percent: return "percent"
        case .equipment: return "equipment"
        case .sectionWarmup: return "sectionWarmup"
        case .sectionCooldown: return "sectionCooldown"
        case .sectionDefault: return "sectionDefault"
        case .stroke(let stroke): return "stroke.\(stroke.rawValue)"
        case .activity(let activity): return "activity.\(activity.rawValue)"
        case .effortLevel(let level): return "effort.\(level.rawValue)"
        }
    }
}
