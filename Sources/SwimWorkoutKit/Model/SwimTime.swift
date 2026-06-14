// SPDX-License-Identifier: MIT

import Foundation

/// A duration used for send-offs, rests, and paces. Stored as whole seconds.
///
/// Parses and prints coach notation: `1:30`, `:35`, `35`, `2:00`.
/// Sub-minute values print with a leading colon (`:35`), matching deck convention.
public struct SwimTime: Hashable, Sendable, Comparable {
    public var seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }

    public init(minutes: Int, seconds: Int) {
        self.seconds = minutes * 60 + seconds
    }

    /// Parses `"1:30"`, `":35"`, `"35"`, `"1:05"`. Returns nil for malformed input.
    public init?(parsing string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard let s = Int(parts[0]), s >= 0 else { return nil }
            self.seconds = s
        case 2:
            let minutePart = parts[0].isEmpty ? "0" : String(parts[0])
            guard let m = Int(minutePart), let s = Int(parts[1]), m >= 0, s >= 0, s < 60 else { return nil }
            self.seconds = m * 60 + s
        default:
            return nil
        }
    }

    public var minutesComponent: Int { seconds / 60 }
    public var secondsComponent: Int { seconds % 60 }

    /// Canonical notation: `1:30` for 90s, `:35` for 35s, `12:00` for 720s.
    public var notation: String {
        let m = minutesComponent
        let s = secondsComponent
        if m == 0 {
            return String(format: ":%02d", s)
        }
        return String(format: "%d:%02d", m, s)
    }

    public static func < (lhs: SwimTime, rhs: SwimTime) -> Bool {
        lhs.seconds < rhs.seconds
    }

    public static func + (lhs: SwimTime, rhs: SwimTime) -> SwimTime {
        SwimTime(seconds: lhs.seconds + rhs.seconds)
    }

    public static func * (lhs: SwimTime, rhs: Int) -> SwimTime {
        SwimTime(seconds: lhs.seconds * rhs)
    }
}

extension SwimTime: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            guard let time = SwimTime(parsing: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid time notation: \(string)"
                )
            }
            self = time
        } else {
            // Tolerate bare integer seconds.
            let s = try container.decode(Int.self)
            self.init(seconds: s)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(notation)
    }
}

extension SwimTime: CustomStringConvertible {
    public var description: String { notation }
}
