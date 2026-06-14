// SPDX-License-Identifier: MIT

import Foundation

/// The exact prompts used to turn workout photos (and messy OCR text) into
/// SwimText. They live in the kit so headless harnesses (the `swimclaude`
/// tool) and any client exercise byte-for-byte the same instructions sent to
/// the model. Keep this the single source of truth for callers rather than
/// inlining prompts.
public enum PhotoImportPrompt {

    /// SwimText notation rules shared by the cleanup and vision prompts.
    public static let swimTextRules = """
        - One item per line. Set lines: [REPS x] DISTANCE [stroke] [activity] \
        [effort] [@SENDOFF or @S1/S2/S3 for multiple lanes] [rREST like r:20 or r1:00] \
        [(~:15 rest)] [| note]
        - Strokes: free back breast fly im imo rimo stroke choice. \
        Activities: swim kick pull drill scull. \
        Efforts: easy smooth moderate strong fast sprint max, build, descend, ns, vs.
        - Section headers: "== Name: distance" (Warmup, Main Set, Cool Down…). \
        When a section shows only a distance with no listed swims (e.g. \
        "Cool Down: 200"), keep that distance in the header — the parser expands \
        it into the swim. Never drop it.
        - Repeat blocks: "Nx {" then items then "}".
        - Title: "# Title" on the first line. A stated grand total goes near the \
        top as "total: NNNN". Pre-calculated totals and per-section distance \
        summaries are NOT swims — never emit them as a set or "| note".
        - Keep coach wording you cannot encode as "| note" suffixes. NEVER invent \
        sets that are not in the input. Remove obvious non-workout noise \
        (timestamps, chat UI, page headers).
        Output ONLY the SwimText — no commentary, and do not wrap it in markdown \
        code fences (no ```).
        """

    /// System instructions for reading a workout photo directly (vision path).
    public static let visionInstructions = """
        You transcribe photographs of swimming workouts (whiteboards, printed \
        sheets, handwriting) into SwimText notation. Read the page the way a \
        swimmer would: respect columns and arrows; parallel send-off columns \
        are lane groups (@S1/S2/S3). When a multiplier and bracket span a \
        GROUP of lines (e.g. "2x" beside a brace covering eight items), wrap \
        exactly those lines in a repeat block — "Nx {" on its own line, the \
        items, then "}" — never collapse a bracketed group onto one line. \
        Rules:
        \(swimTextRules)
        """

    /// System instructions for cleaning up local OCR text into SwimText.
    public static let cleanupInstructions = """
        You convert OCR text of swimming workouts into SwimText notation. Rules:
        \(swimTextRules)
        """

    /// The user-turn prompt sent alongside the photo.
    public static let transcribeUserPrompt = "Transcribe this workout photo into SwimText."
}
