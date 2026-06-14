// SPDX-License-Identifier: MIT

import Foundation

/// JSON wire format for `AIDraft`, for model providers that emit JSON
/// (Claude structured outputs today; any OpenAI-compatible or future Apple
/// Private Cloud Compute provider tomorrow). The on-device FoundationModels
/// path uses `@Generable` constrained decoding instead and never touches this.
///
/// Numeric ranges live in the field *descriptions*, not schema constraints —
/// hosted structured-output implementations commonly reject `minimum`/
/// `maximum`, and `AIDraftConverter` sanitizes values regardless.
public enum AIDraftWire {

    public struct Workout: Codable, Sendable, Equatable {
        public var title: String
        public var sections: [Section]

        public init(title: String, sections: [Section]) {
            self.title = title
            self.sections = sections
        }
    }

    public struct Section: Codable, Sendable, Equatable {
        public var name: String
        public var blocks: [Block]

        public init(name: String, blocks: [Block]) {
            self.name = name
            self.blocks = blocks
        }
    }

    public struct Block: Codable, Sendable, Equatable {
        public var rounds: Int
        public var sets: [SetItem]

        public init(rounds: Int, sets: [SetItem]) {
            self.rounds = rounds
            self.sets = sets
        }
    }

    public struct SetItem: Codable, Sendable, Equatable {
        public var reps: Int
        public var distance: Int
        public var stroke: String?
        public var activity: String?
        public var effort: String?
        public var shape: String?
        public var restSeconds: Int?
        public var note: String?

        public init(
            reps: Int, distance: Int,
            stroke: String? = nil, activity: String? = nil,
            effort: String? = nil, shape: String? = nil,
            restSeconds: Int? = nil, note: String? = nil
        ) {
            self.reps = reps
            self.distance = distance
            self.stroke = stroke
            self.activity = activity
            self.effort = effort
            self.shape = shape
            self.restSeconds = restSeconds
            self.note = note
        }
    }

    // MARK: - Conversion

    public static func draft(from wire: Workout) -> AIDraft {
        AIDraft(
            title: wire.title,
            sections: wire.sections.map { section in
                AIDraft.DraftSection(
                    name: section.name,
                    blocks: section.blocks.map { block in
                        AIDraft.DraftBlock(
                            rounds: block.rounds,
                            sets: block.sets.map { set in
                                AIDraft.DraftSet(
                                    reps: set.reps, distance: set.distance,
                                    stroke: set.stroke, activity: set.activity,
                                    effort: set.effort, shape: set.shape,
                                    restSeconds: set.restSeconds, note: set.note
                                )
                            }
                        )
                    }
                )
            }
        )
    }

    public static func decodeDraft(fromJSON data: Data) throws -> AIDraft {
        draft(from: try JSONDecoder().decode(Workout.self, from: data))
    }

    // MARK: - JSON Schema

    /// JSON Schema for the wire format. Mirrors the on-device `@Guide`
    /// annotations so both paths generate from the same playbook.
    public static let jsonSchemaString = """
    {
      "type": "object",
      "description": "A swimming workout draft. The app computes all send-off times and scales to the exact target distance; design structure, not arithmetic.",
      "properties": {
        "title": {
          "type": "string",
          "description": "Short workout title, e.g. 'Fly Focus Friday'. No quotes."
        },
        "sections": {
          "type": "array",
          "description": "2 to 4 sections, in swim order: Warmup, optional Pre Set, Main Set, Cool Down.",
          "items": {
            "type": "object",
            "properties": {
              "name": {
                "type": "string",
                "description": "Section name: Warmup, Pre Set, Main Set, or Cool Down"
              },
              "blocks": {
                "type": "array",
                "description": "The blocks swum in this section, in order.",
                "items": {
                  "type": "object",
                  "properties": {
                    "rounds": {
                      "type": "integer",
                      "description": "How many times this block repeats, 1 to 4; 1 for a plain block."
                    },
                    "sets": {
                      "type": "array",
                      "description": "Sets inside this block, in order.",
                      "items": {
                        "type": "object",
                        "properties": {
                          "reps": {
                            "type": "integer",
                            "description": "Number of repetitions, 1 to 12; typical sets are 3-8 reps."
                          },
                          "distance": {
                            "type": "integer",
                            "description": "Distance per rep in course units: a multiple of 25, between 25 and 600."
                          },
                          "stroke": {
                            "type": "string",
                            "enum": ["free", "back", "breast", "fly", "im", "imo", "choice"],
                            "description": "Stroke"
                          },
                          "activity": {
                            "type": "string",
                            "enum": ["swim", "kick", "pull", "drill"],
                            "description": "Activity"
                          },
                          "effort": {
                            "type": "string",
                            "enum": ["easy", "smooth", "moderate", "strong", "fast", "sprint", "max"],
                            "description": "Effort level"
                          },
                          "shape": {
                            "type": "string",
                            "enum": ["steady", "build", "descend", "negative-split"],
                            "description": "Effort shape across reps"
                          },
                          "restSeconds": {
                            "type": "integer",
                            "description": "Intended rest between reps in seconds, 5 to 120."
                          },
                          "note": {
                            "type": "string",
                            "description": "Short coach note, only when it adds something."
                          }
                        },
                        "required": ["reps", "distance"],
                        "additionalProperties": false
                      }
                    }
                  },
                  "required": ["rounds", "sets"],
                  "additionalProperties": false
                }
              }
            },
            "required": ["name", "blocks"],
            "additionalProperties": false
          }
        }
      },
      "required": ["title", "sections"],
      "additionalProperties": false
    }
    """
}
