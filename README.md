# SwimWorkoutKit

Reference implementation of the **Open Swim Workout** format (`.swimworkout`):
model types, SwimText parser/printer/lexer, totals & duration calculators,
validator, workout scaler/flattener/generator, swim-event clustering and stats —
plus the `swimtext`, `swimocr`, and `swimclaude` CLIs.

Spec, JSON Schema, and notation grammar: see [`Spec/`](Spec/). The package and
`Spec/` are MIT licensed and self-contained.

## Installation

Swift Package Manager — add to your `Package.swift`:

```swift
.package(url: "https://github.com/rickybloomfield/SwimWorkoutKit.git", from: "0.1.0")
```

then add the product(s) you need to a target:

```swift
.product(name: "SwimWorkoutKit", package: "SwimWorkoutKit"),    // core, UI-free
.product(name: "SwimWorkoutKitUI", package: "SwimWorkoutKit"),  // optional SwiftUI highlighting
```

In Xcode: **File → Add Package Dependencies…**, paste the repository URL, and
pick the products.

## Command-line tools

```sh
swift test                       # full test suite incl. a corpus of real swim workouts
swift build --product swimtext   # convert/validate SwimText ⇄ .swimworkout
swift build --product swimocr    # photo → SwimText (macOS 15+, Vision)
swift build --product swimclaude # photo → SwimText via the Anthropic API (needs ANTHROPIC_API_KEY)
```

## SwimText syntax highlighting — `SwimWorkoutKitUI`

The core library is UI-free. `SwimWorkoutKitUI` is an optional companion module
that colors SwimText with the same visual vocabulary the app uses on screen and
in deck sheets — strokes, activities, effort, send-offs, sections, and notes.

| Type | What it is |
|---|---|
| `SwimTextView` | A `UITextView` / `NSTextView` **subclass** that highlights live as the text changes — set `.text` and it colors itself; type into it and it re-highlights every keystroke. |
| `SwimTextEditor` | A SwiftUI `UIViewRepresentable` wrapping `SwimTextView` — a drop-in, highlighting replacement for `TextEditor`. |
| `SwimTextLabel` | A read-only SwiftUI view (renders into `Text`), so it works everywhere, including watchOS. |
| `SwimTextHighlighter` | The engine: turns SwimText into an `AttributedString` or `NSAttributedString`. |
| `SwimTextTheme` | The color palette. `.standard` is the built-in palette; build your own to retheme any element. |
| `SwimTextLexer` | The UI-free tokenizer (in the core library) the highlighter is built on — useful on its own. |

```swift
import SwiftUI
import SwimWorkoutKitUI

struct WorkoutEntry: View {
    @State private var text = "8x50 free fast @:45 r:10"
    var body: some View {
        SwimTextEditor(text: $text)   // editable, live syntax highlighting
    }
}

// Read-only display, any platform:
SwimTextLabel("3x300 free descend to 80% @4:40/4:50/5:00")

// Or get attributed text directly:
let attributed = SwimTextHighlighter.attributedString("100 fly sprint @1:30")
```

The palette is color-blind-safe and pairs color with weight, so highlighted
SwimText stays legible in black & white. Pass a custom `SwimTextTheme` to any of
the views to restyle.

## Website

A static site documenting the format lives in [`docs/`](docs/); serve it with
GitHub Pages (**Settings → Pages → Deploy from branch → `main` / `docs`**).

## License

MIT — see [LICENSE](LICENSE). The format spec under [`Spec/`](Spec/) is MIT too.
