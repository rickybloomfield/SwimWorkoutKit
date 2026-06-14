// SPDX-License-Identifier: MIT

import Foundation
import SwimWorkoutKit
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Headless Claude-vision import harness — the API counterpart to `swimocr`.
///
///   swimclaude <image> [--raw]
///   swimclaude --batch <imagesDir> --out <outDir>
///
/// Sends each photo to the Anthropic Messages API using the SAME system prompt,
/// user prompt, image sizing (long edge ≤ 2048, JPEG q0.85), model, and
/// thinking settings the shipping app uses, then runs the returned SwimText
/// through the real `SwimTextParser` + `fillEmptyStatedSections` + validator —
/// the same post-processing the import pipeline applies. Lets us measure the
/// Claude import path against a directory of workout photos without a
/// simulator.
///
/// Requires `ANTHROPIC_API_KEY` in the environment. Optional overrides:
/// `CLAUDE_MODEL` (default matches the app), `CLAUDE_MAX_TOKENS`.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - Config

let defaultModel = "claude-sonnet-4-6"
let env = ProcessInfo.processInfo.environment
// Required only for the API modes; the offline `--reparse` path needs no key.
let apiKey = env["ANTHROPIC_API_KEY"] ?? ""
let model = env["CLAUDE_MODEL"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel
let maxTokens = env["CLAUDE_MAX_TOKENS"].flatMap { Int($0) } ?? 16000
// Mirror the app's photo-read path: default to low effort (fast transcription).
// Override with CLAUDE_EFFORT (low|medium|high|max), or CLAUDE_EFFORT=none for
// the raw API default (high). CLAUDE_THINKING (adaptive|disabled) overrides the
// thinking mode; defaults to adaptive.
let effortRaw = env["CLAUDE_EFFORT"].flatMap { $0.isEmpty ? nil : $0 } ?? "low"
let effort = effortRaw.lowercased() == "none" ? nil : effortRaw
let thinkingType = env["CLAUDE_THINKING"].flatMap { $0.isEmpty ? nil : $0 } ?? "adaptive"

// MARK: - Image → vision JPEG (matches UIImage.visionAPIJPEG)

#if canImport(ImageIO) && canImport(CoreGraphics)
/// Long edge capped at 2048 px with the EXIF orientation baked in, re-encoded
/// as JPEG q0.85 — the same bytes the app uploads via `visionAPIJPEG`.
func visionJPEG(at url: URL, maxPixel: Int = 2048, quality: CGFloat = 0.85) -> Data? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
    }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}
#else
func visionJPEG(at url: URL, maxPixel: Int = 2048, quality: CGFloat = 0.85) -> Data? {
    try? Data(contentsOf: url)
}
#endif

// MARK: - Anthropic Messages client (mirror of the app's ClaudeClient)

struct StreamEvent: Decodable {
    struct Delta: Decodable {
        let type: String?
        let text: String?
        let stopReason: String?
        enum CodingKeys: String, CodingKey {
            case type, text
            case stopReason = "stop_reason"
        }
    }
    struct APIError: Decodable { let type: String?; let message: String? }
    let type: String
    let delta: Delta?
    let error: APIError?
}

enum ClaudeError: Error, CustomStringConvertible {
    case message(String)
    var description: String { if case .message(let m) = self { return m }; return "error" }
}

func transcribe(imageJPEG: Data) async throws -> String {
    guard !apiKey.isEmpty else {
        throw ClaudeError.message("ANTHROPIC_API_KEY is not set. Export your Anthropic key and re-run.")
    }
    let url = URL(string: "https://api.anthropic.com/v1/messages")!
    var body: [String: Any] = [
        "model": model,
        "max_tokens": maxTokens,
        "stream": true,
        "system": PhotoImportPrompt.visionInstructions,
        "thinking": ["type": thinkingType],
        "messages": [[
            "role": "user",
            "content": [
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": imageJPEG.base64EncodedString(),
                    ],
                ],
                ["type": "text", "text": PhotoImportPrompt.transcribeUserPrompt],
            ],
        ]],
    ]
    if let effort { body["output_config"] = ["effort": effort] }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.timeoutInterval = 120

    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw ClaudeError.message("no HTTP response")
    }
    guard http.statusCode == 200 else {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > 64_000 { break }
        }
        let detail = String(data: data, encoding: .utf8) ?? ""
        throw ClaudeError.message("HTTP \(http.statusCode): \(detail)")
    }

    var text = ""
    var stopReason: String?
    for try await line in bytes.lines {
        guard line.hasPrefix("data: ") else { continue }
        let payload = Data(line.dropFirst("data: ".count).utf8)
        guard let event = try? JSONDecoder().decode(StreamEvent.self, from: payload) else { continue }
        switch event.type {
        case "content_block_delta":
            if event.delta?.type == "text_delta", let chunk = event.delta?.text { text += chunk }
        case "message_delta":
            stopReason = event.delta?.stopReason ?? stopReason
        case "error":
            throw ClaudeError.message("stream error: \(event.error?.message ?? "unknown")")
        default:
            break
        }
    }
    if stopReason == "max_tokens" {
        throw ClaudeError.message("response truncated at max_tokens")
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ClaudeError.message("empty response") }
    return text
}

// MARK: - Parse + report (mirror of swimocr)

struct Summary {
    let name: String
    let title: String
    let sections: Int
    let stated: Int?
    let primaryTotal: Int
    let unparsed: Int
    let errors: Int
    let warnings: Int
    let failure: String?
    var elapsed: Double? = nil
}

func report(for swimText: String) -> (text: String, summary: Summary, name: String) {
    let result = SwimTextParser.parse(swimText)
    let workout = OCRTextAssembler.fillEmptyStatedSections(result.document.workout)
    var out = "===== Report =====\n"
    out += "title: \(workout.title ?? "—")\n"
    out += "sections: \(workout.sections.count)\n"
    if let stated = workout.statedTotal { out += "stated total: \(stated)\n" }
    let totals = WorkoutCalculator.totals(of: workout)
    for total in totals {
        out += "group \(total.groupID ?? "—"): \(total.distance)\n"
    }
    if !result.unparsedLines.isEmpty {
        out += "unparsed lines (\(result.unparsedLines.count)):\n"
        for line in result.unparsedLines { out += "  \(line.lineNumber): \(line.text)\n" }
    }
    let issues = WorkoutValidator.validate(workout)
    for issue in issues { out += "\(issue)\n" }

    let primary = WorkoutCalculator.distance(of: workout, group: workout.groups.first?.id)
    let errorCount = issues.filter { "\($0)".lowercased().contains("error") }.count
    let summary = Summary(
        name: "",
        title: workout.title ?? "—",
        sections: workout.sections.count,
        stated: workout.statedTotal,
        primaryTotal: primary,
        unparsed: result.unparsedLines.count,
        errors: errorCount,
        warnings: max(issues.count - errorCount, 0),
        failure: nil
    )
    return (out, summary, workout.title ?? "—")
}

// MARK: - Modes

let arguments = CommandLine.arguments

func runSingle(imagePath: String, rawOnly: Bool) async {
    let url = URL(fileURLWithPath: imagePath)
    guard let jpeg = visionJPEG(at: url) else { fail("cannot read image: \(url.path)") }
    let swimText: String
    do {
        swimText = try await transcribe(imageJPEG: jpeg)
    } catch {
        fail("Claude read failed: \(error)")
    }
    if rawOnly {
        print(swimText)
        return
    }
    print("===== SwimText =====")
    print(swimText)
    let (reportText, _, _) = report(for: swimText)
    print(reportText, terminator: "")
}

func runBatch(imagesDir: String, outDir: String) async {
    let fm = FileManager.default
    let inURL = URL(fileURLWithPath: imagesDir, isDirectory: true)
    let outURL = URL(fileURLWithPath: outDir, isDirectory: true)
    try? fm.createDirectory(at: outURL, withIntermediateDirectories: true)

    let exts: Set<String> = ["jpg", "jpeg", "png", "heic"]
    guard let entries = try? fm.contentsOfDirectory(at: inURL, includingPropertiesForKeys: nil) else {
        fail("cannot list images in: \(inURL.path)")
    }
    let images = entries
        .filter { exts.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !images.isEmpty else { fail("no images found in: \(inURL.path)") }

    note("swimclaude: \(images.count) images, model=\(model), thinking=\(thinkingType), effort=\(effort ?? "default(high)")")
    var summaries: [Summary] = []
    for (index, image) in images.enumerated() {
        let name = image.deletingPathExtension().lastPathComponent
        note("[\(index + 1)/\(images.count)] \(name) …")
        guard let jpeg = visionJPEG(at: image) else {
            note("  ! cannot encode \(name)")
            summaries.append(Summary(name: name, title: "—", sections: 0, stated: nil,
                                     primaryTotal: 0, unparsed: 0, errors: 0, warnings: 0,
                                     failure: "encode failed"))
            continue
        }
        do {
            let started = Date()
            let swimText = try await transcribe(imageJPEG: jpeg)
            let elapsed = Date().timeIntervalSince(started)
            try? swimText.write(to: outURL.appending(path: "\(name).swimtext"), atomically: true, encoding: .utf8)
            let (reportText, summary0, _) = report(for: swimText)
            let summary = Summary(name: name, title: summary0.title, sections: summary0.sections,
                                  stated: summary0.stated, primaryTotal: summary0.primaryTotal,
                                  unparsed: summary0.unparsed, errors: summary0.errors,
                                  warnings: summary0.warnings, failure: nil, elapsed: elapsed)
            let perImage = "===== SwimText =====\n\(swimText)\n\(reportText)"
            try? perImage.write(to: outURL.appending(path: "\(name).txt"), atomically: true, encoding: .utf8)
            summaries.append(summary)
            let statedStr = summary.stated.map(String.init) ?? "—"
            note("  ✓ \(String(format: "%.0fs", elapsed)) · total \(summary.primaryTotal) / stated \(statedStr), \(summary.unparsed) unparsed, \(summary.errors)E \(summary.warnings)W")
        } catch {
            note("  ✗ \(error)")
            try? "ERROR: \(error)\n".write(to: outURL.appending(path: "\(name).txt"), atomically: true, encoding: .utf8)
            summaries.append(Summary(name: name, title: "—", sections: 0, stated: nil,
                                     primaryTotal: 0, unparsed: 0, errors: 0, warnings: 0,
                                     failure: "\(error)"))
        }
    }

    // Summary table
    var md = "# Claude Photo-Import Audit — \(images.count) images\n\n"
    md += "Model: `\(model)` · thinking `\(thinkingType)` · effort `\(effort ?? "default (high)")` · "
    md += "system + user prompt + image sizing identical to the app's vision path; SwimText run "
    md += "through the real parser + `fillEmptyStatedSections` + validator.\n\n"
    md += "| Image | Secs | Title | Sections | Computed | Stated | Unparsed | Err | Warn | Notes |\n"
    md += "|---|---|---|---|---|---|---|---|---|---|\n"
    for summary in summaries {
        let stated = summary.stated.map(String.init) ?? "—"
        let secs = summary.elapsed.map { String(format: "%.0f", $0) } ?? "—"
        let flag: String
        if let failure = summary.failure {
            flag = failure
        } else if let stated = summary.stated, abs(stated - summary.primaryTotal) > 25 {
            flag = "stated≠computed"
        } else {
            flag = ""
        }
        md += "| \(summary.name) | \(secs) | \(summary.title) | \(summary.sections) | \(summary.primaryTotal) | \(stated) | \(summary.unparsed) | \(summary.errors) | \(summary.warnings) | \(flag) |\n"
    }
    let okCount = summaries.filter { $0.failure == nil && $0.errors == 0 && $0.unparsed == 0 }.count
    let timed = summaries.compactMap { $0.elapsed }
    let avg = timed.isEmpty ? 0 : timed.reduce(0, +) / Double(timed.count)
    md += "\nClean (0 unparsed, 0 errors): **\(okCount)/\(summaries.count)**. "
    md += "Failures: **\(summaries.filter { $0.failure != nil }.count)**. "
    md += "Avg read: **\(String(format: "%.0fs", avg))** (effort `\(effort ?? "default")`).\n"
    try? md.write(to: outURL.appending(path: "summary.md"), atomically: true, encoding: .utf8)
    note("swimclaude: wrote \(summaries.count) reports + summary.md to \(outURL.path)")
}

/// Offline: re-run the parse + fill + validate pipeline over already-saved
/// `.swimtext` transcripts (no API calls), so parser changes can be measured
/// against the captured Claude reads. Reuses the exact `report(for:)` path.
func runReparse(swimtextDir: String, outDir: String) {
    let fm = FileManager.default
    let inURL = URL(fileURLWithPath: swimtextDir, isDirectory: true)
    let outURL = URL(fileURLWithPath: outDir, isDirectory: true)
    try? fm.createDirectory(at: outURL, withIntermediateDirectories: true)
    guard let entries = try? fm.contentsOfDirectory(at: inURL, includingPropertiesForKeys: nil) else {
        fail("cannot list: \(inURL.path)")
    }
    let files = entries.filter { $0.pathExtension.lowercased() == "swimtext" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !files.isEmpty else { fail("no .swimtext files in: \(inURL.path)") }

    var summaries: [Summary] = []
    for file in files {
        let name = file.deletingPathExtension().lastPathComponent
        guard let swimText = try? String(contentsOf: file, encoding: .utf8) else { continue }
        let (reportText, summary0, _) = report(for: swimText)
        let summary = Summary(name: name, title: summary0.title, sections: summary0.sections,
                              stated: summary0.stated, primaryTotal: summary0.primaryTotal,
                              unparsed: summary0.unparsed, errors: summary0.errors,
                              warnings: summary0.warnings, failure: nil)
        summaries.append(summary)
        try? "===== SwimText =====\n\(swimText)\n\(reportText)".write(
            to: outURL.appending(path: "\(name).txt"), atomically: true, encoding: .utf8)
        let statedStr = summary.stated.map(String.init) ?? "—"
        note("\(name): total \(summary.primaryTotal) / stated \(statedStr), \(summary.unparsed) unparsed, \(summary.errors)E \(summary.warnings)W")
    }

    var md = "# Reparse — \(files.count) saved transcripts (offline)\n\n"
    md += "| Image | Title | Sections | Computed | Stated | Unparsed | Err | Warn | Notes |\n"
    md += "|---|---|---|---|---|---|---|---|---|\n"
    for summary in summaries {
        let stated = summary.stated.map(String.init) ?? "—"
        let flag = (summary.stated.map { abs($0 - summary.primaryTotal) > 25 } ?? false) ? "stated≠computed" : ""
        md += "| \(summary.name) | \(summary.title) | \(summary.sections) | \(summary.primaryTotal) | \(stated) | \(summary.unparsed) | \(summary.errors) | \(summary.warnings) | \(flag) |\n"
    }
    let clean = summaries.filter { $0.errors == 0 && $0.unparsed == 0 }.count
    md += "\nClean (0 unparsed, 0 errors): **\(clean)/\(summaries.count)**.\n"
    try? md.write(to: outURL.appending(path: "summary.md"), atomically: true, encoding: .utf8)
    note("wrote \(summaries.count) reports + summary.md to \(outURL.path)")
}

// MARK: - Entry

if arguments.contains("--reparse") {
    guard let rIndex = arguments.firstIndex(of: "--reparse"), rIndex + 1 < arguments.count,
          let oIndex = arguments.firstIndex(of: "--out"), oIndex + 1 < arguments.count
    else { fail("usage: swimclaude --reparse <swimtextDir> --out <outDir>") }
    runReparse(swimtextDir: arguments[rIndex + 1], outDir: arguments[oIndex + 1])
} else if arguments.contains("--batch") {
    guard let bIndex = arguments.firstIndex(of: "--batch"), bIndex + 1 < arguments.count,
          let oIndex = arguments.firstIndex(of: "--out"), oIndex + 1 < arguments.count
    else { fail("usage: swimclaude --batch <imagesDir> --out <outDir>") }
    await runBatch(imagesDir: arguments[bIndex + 1], outDir: arguments[oIndex + 1])
} else {
    guard arguments.count >= 2 else {
        fail("usage: swimclaude <image> [--raw]  |  swimclaude --batch <imagesDir> --out <outDir>")
    }
    await runSingle(imagePath: arguments[1], rawOnly: arguments.contains("--raw"))
}
