// SPDX-License-Identifier: MIT

import SwiftUI
import SwimWorkoutKit

/// The semantic color vocabulary for SwimText — the single visual language
/// shared by the on-screen renderer, PDF deck sheets, and syntax highlighting.
///
/// Colors carry redundant cues elsewhere (labels, weight, shape), so the palette
/// stays legible in black & white and for color-blind readers. ``standard`` is
/// the built-in palette; construct your own to retheme any element.
public struct SwimTextTheme: Sendable {

    // Scalar token colors.
    public var plain: Color
    public var title: Color
    public var repsDistance: Color
    public var sendoff: Color
    public var rest: Color
    public var time: Color
    public var note: Color
    public var structure: Color
    public var metadataKey: Color
    public var metadataValue: Color
    public var effortShape: Color
    public var percent: Color
    public var equipment: Color

    // Section colors, chosen by name (warmup / cool-down / everything else).
    public var sectionWarmup: Color
    public var sectionCooldown: Color
    public var sectionDefault: Color

    // Axis color maps. A missing key falls back to ``plain``.
    public var strokeColors: [Stroke: Color]
    public var activityColors: [Activity: Color]
    public var effortLevelColors: [EffortLevel: Color]

    public init(
        plain: Color,
        title: Color,
        repsDistance: Color,
        sendoff: Color,
        rest: Color,
        time: Color,
        note: Color,
        structure: Color,
        metadataKey: Color,
        metadataValue: Color,
        effortShape: Color,
        percent: Color,
        equipment: Color,
        sectionWarmup: Color,
        sectionCooldown: Color,
        sectionDefault: Color,
        strokeColors: [Stroke: Color],
        activityColors: [Activity: Color],
        effortLevelColors: [EffortLevel: Color]
    ) {
        self.plain = plain
        self.title = title
        self.repsDistance = repsDistance
        self.sendoff = sendoff
        self.rest = rest
        self.time = time
        self.note = note
        self.structure = structure
        self.metadataKey = metadataKey
        self.metadataValue = metadataValue
        self.effortShape = effortShape
        self.percent = percent
        self.equipment = equipment
        self.sectionWarmup = sectionWarmup
        self.sectionCooldown = sectionCooldown
        self.sectionDefault = sectionDefault
        self.strokeColors = strokeColors
        self.activityColors = activityColors
        self.effortLevelColors = effortLevelColors
    }

    // MARK: - Lookups

    public func color(for stroke: Stroke) -> Color { strokeColors[stroke] ?? plain }
    public func color(for activity: Activity) -> Color { activityColors[activity] ?? plain }
    public func color(for level: EffortLevel) -> Color { effortLevelColors[level] ?? plain }

    /// Section color by name: warmups read green, cool-downs gray, the rest blue.
    public func sectionColor(for name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("warm") || lower.contains("loosen") || lower.contains("pre") {
            return sectionWarmup
        }
        if lower.contains("cool") || lower.contains("down") {
            return sectionCooldown
        }
        return sectionDefault
    }

    /// The color for a lexer token.
    public func color(for kind: SwimTextTokenKind) -> Color {
        switch kind {
        case .title: return title
        case .section(let name): return sectionColor(for: name)
        case .metadataKey: return metadataKey
        case .metadataValue: return metadataValue
        case .repsDistance: return repsDistance
        case .stroke(let stroke): return color(for: stroke)
        case .activity(let activity): return color(for: activity)
        case .effortLevel(let level): return color(for: level)
        case .effortShape: return effortShape
        case .percent: return percent
        case .equipment: return equipment
        case .sendoff: return sendoff
        case .rest: return rest
        case .time: return time
        case .note: return note
        case .structure: return structure
        }
    }

    /// Whether a token reads with emphasis (heavier weight) when highlighted.
    public func isEmphasized(_ kind: SwimTextTokenKind) -> Bool {
        switch kind {
        case .title, .section, .repsDistance, .sendoff: return true
        default: return false
        }
    }

    // MARK: - Standard palette

    /// The built-in palette — identical to the colors the app uses on screen and
    /// in deck sheets.
    public static let standard = SwimTextTheme(
        plain: .primary,
        title: .primary,
        repsDistance: .primary,
        sendoff: .blue,
        rest: .secondary,
        time: .secondary,
        note: .secondary,
        structure: .blue,
        metadataKey: .secondary,
        metadataValue: .secondary,
        effortShape: .secondary,
        percent: .secondary,
        equipment: .secondary,
        sectionWarmup: .green,
        sectionCooldown: .gray,
        sectionDefault: .blue,
        strokeColors: [
            .free: .blue,
            .back: .teal,
            .breast: .green,
            .fly: .purple,
            .im: .orange, .imo: .orange, .rimo: .orange,
            .stroke: .indigo,
            .choice: .secondary, .mixed: .secondary,
        ],
        activityColors: [
            .swim: .blue,
            .kick: .orange,
            .pull: .brown,
            .drill: .pink,
            .scull: .mint,
            .mixed: .secondary,
        ],
        effortLevelColors: [
            .easy: .green, .smooth: .green,
            .moderate: .yellow, .strong: .yellow,
            .fast: .red, .sprint: .red,
            .max: .red, .race: .red,
        ]
    )
}
