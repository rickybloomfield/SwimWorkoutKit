// SPDX-License-Identifier: MIT

import SwiftUI
import SwimWorkoutKit

/// A read-only SwiftUI view that renders SwimText with syntax highlighting.
///
/// Works on every platform (it draws into a `Text`), so it's the right choice
/// for display contexts — previews, watchOS, share sheets. For an editable field
/// use ``SwimTextEditor``.
public struct SwimTextLabel: View {
    private let text: String
    private let theme: SwimTextTheme
    private let font: Font

    public init(
        _ text: String,
        theme: SwimTextTheme = .standard,
        font: Font = .system(.callout, design: .monospaced)
    ) {
        self.text = text
        self.theme = theme
        self.font = font
    }

    public var body: some View {
        Text(SwimTextHighlighter.attributedString(text, theme: theme, font: font))
    }
}

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// An editable SwiftUI text editor that live-highlights SwimText — a drop-in,
/// coach-friendly replacement for `TextEditor` backed by ``SwimTextView``.
///
/// ```swift
/// SwimTextEditor(text: $workoutText)
/// ```
public struct SwimTextEditor: UIViewRepresentable {
    @Binding private var text: String
    private let theme: SwimTextTheme
    private let isEditable: Bool

    public init(text: Binding<String>, theme: SwimTextTheme = .standard, isEditable: Bool = true) {
        self._text = text
        self.theme = theme
        self.isEditable = isEditable
    }

    public func makeUIView(context: Context) -> SwimTextView {
        let view = SwimTextView()
        view.swimTheme = theme
        view.delegate = context.coordinator
        view.isEditable = isEditable
        view.isScrollEnabled = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.text = text
        // A context-bar swap edits the text programmatically, which doesn't fire
        // the delegate — push the result to the binding ourselves.
        view.onSwap = { [weak coordinator = context.coordinator] newText in
            coordinator?.setText(newText)
        }
        return view
    }

    public func updateUIView(_ uiView: SwimTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            uiView.refreshContextBar()
        }
        uiView.isEditable = isEditable
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func setText(_ newText: String) {
            text.wrappedValue = newText
        }

        public func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            (textView as? SwimTextView)?.refreshContextBar()
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? SwimTextView)?.refreshContextBar()
        }

        public func textViewDidBeginEditing(_ textView: UITextView) {
            (textView as? SwimTextView)?.refreshContextBar()
        }
    }
}
#endif
