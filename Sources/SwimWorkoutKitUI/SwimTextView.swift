// SPDX-License-Identifier: MIT

import SwimWorkoutKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// A `UITextView` subclass that syntax-highlights SwimText as it changes.
///
/// Drop it in anywhere a workout is typed, pasted, or shown: set `text` and the
/// view colors strokes, send-offs, sections, and the rest of the SwimText
/// vocabulary using a ``SwimTextTheme`` — re-highlighting live on every edit.
/// For SwiftUI, use ``SwimTextEditor`` (editable) or ``SwimTextLabel`` (display).
///
/// Highlighting runs in the text-storage delegate callback and only on character
/// edits, so attribute updates never re-enter it — no flicker, no recursion.
public final class SwimTextView: UITextView {

    /// The color vocabulary. Setting it re-highlights immediately.
    public var swimTheme: SwimTextTheme = .standard {
        didSet { applyHighlighting() }
    }

    /// The base (regular-weight) monospaced font. Emphasized tokens derive a
    /// semibold variant of the same size.
    public var swimFont: PlatformFont = SwimTextHighlighter.defaultFont {
        didSet {
            font = swimFont
            applyHighlighting()
        }
    }

    /// Called after a context-bar swap mutates the text, so the SwiftUI binding
    /// can update (programmatic edits don't fire `textViewDidChange`).
    public var onSwap: ((String) -> Void)?

    /// The keyboard accessory that offers pop-up lists for the swappable tokens
    /// on the caret's line. Refreshed on every text and selection change.
    private let contextBar = SwimContextBar()

    /// Fingerprint of the fields the bar currently shows. Rebuilding only when
    /// this changes avoids destroying a chip's button (and dismissing its open
    /// menu) on a spurious refresh, e.g. a caret blink or menu presentation.
    private var contextSignature: String?

    /// Held while a category multi-toggle is in flight: the in-place text edit
    /// must not rebuild the bar, which would replace the button whose menu is
    /// still open. The bar catches up on the next ordinary refresh.
    private var suppressContextRefresh = false

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        textStorage.delegate = self
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no
        backgroundColor = .clear
        font = swimFont
        textColor = PlatformColor(swimTheme.plain)
        typingAttributes = baseAttributes
        keyboardDismissMode = .interactive
        inputAccessoryView = contextBar
        contextBar.onDismiss = { [weak self] in self?.resignFirstResponder() }
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: swimFont, .foregroundColor: PlatformColor(swimTheme.plain)]
    }

    /// Recolors the entire backing store. Safe to call from inside the text
    /// storage delegate: it only edits attributes, which don't carry
    /// `.editedCharacters`, so the delegate's guard short-circuits the re-entry.
    private func applyHighlighting() {
        let string = textStorage.string
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.setAttributes(baseAttributes, range: full)
        let emphasized = PlatformFont.monospacedSystemFont(ofSize: swimFont.pointSize, weight: .semibold)
        for token in SwimTextLexer.tokens(in: string) {
            let nsRange = NSRange(token.range, in: string)
            textStorage.addAttribute(.foregroundColor,
                                     value: PlatformColor(swimTheme.color(for: token.kind)),
                                     range: nsRange)
            if swimTheme.isEmphasized(token.kind) {
                textStorage.addAttribute(.font, value: emphasized, range: nsRange)
            }
        }
        // Mark swappable spans with a thick dotted underline — the "this can be
        // picked from a list" cue, only in the editable view (the context bar
        // acts on it). No underline color is set, so TextKit draws it in each
        // token's own foreground color.
        let dotted = NSUnderlineStyle([.thick, .patternDot]).rawValue
        for field in SwimTextFieldResolver.fields(in: string) where !field.range.isEmpty {
            textStorage.addAttribute(.underlineStyle, value: dotted, range: NSRange(field.range, in: string))
        }
        typingAttributes = baseAttributes
    }

    // MARK: - Context bar

    /// Rebuilds the keyboard accessory for the swappable fields on the caret's
    /// line. Call on every text and selection change.
    func refreshContextBar() {
        guard !suppressContextRefresh else { return }
        let text = self.text ?? ""
        guard isEditable, isFirstResponder, let caret = caretIndex(in: text) else {
            // Transient: presenting a chip's menu can momentarily drop the caret
            // or first-responder status. Leave the bar as-is rather than tearing
            // it down — clearing here is what made the chips vanish on tap.
            return
        }
        let fields = SwimTextFieldResolver.fields(in: text, onLineContaining: caret)
        let addable = SwimTextFieldResolver.addableModifiers(in: text, onLineContaining: caret)
        let canComment = SwimTextFieldResolver.commentInsertion(in: text, onLineContaining: caret) != nil
        let signature = fields.map {
            "\($0.kind.rawValue):\(text.distance(from: text.startIndex, to: $0.range.lowerBound)):\($0.currentRaw)"
        }.joined(separator: "|")
            + "#add:" + addable.map(\.rawValue).joined(separator: ",")
            + "#comment:\(canComment)"
        guard signature != contextSignature else { return }
        contextSignature = signature

        var items = fields.map {
            SwimContextBar.Item(title: SwimTextFieldStyle.chipTitle(for: $0),
                                systemImage: SwimTextFieldStyle.icon($0.kind),
                                menu: menu(for: $0, in: text))
        }
        // Add-a-modifier chip for what's not already on the row, then a comment
        // chip — the two ways to extend a set line beyond swapping what's there.
        if !addable.isEmpty {
            items.append(SwimContextBar.Item(title: "Add", systemImage: "plus", menu: addMenu(addable)))
        }
        if canComment {
            items.append(SwimContextBar.Item(title: "Note", systemImage: "text.bubble",
                                             action: { [weak self] in self?.addNote() }))
        }
        contextBar.configure(items: items)
    }

    /// "Add" menu: a submenu of options per modifier kind not yet on the row.
    private func addMenu(_ kinds: [SwimTextField.Kind]) -> UIMenu {
        let submenus = kinds.map { kind -> UIMenuElement in
            let actions = SwimTextFieldResolver.rawOptions(for: kind).map { raw in
                UIAction(title: SwimTextFieldStyle.optionLabel(raw, kind: kind)) { [weak self] _ in
                    self?.addModifier(raw)
                }
            }
            return UIMenu(title: SwimTextFieldStyle.menuTitle(kind),
                          image: UIImage(systemName: SwimTextFieldStyle.icon(kind)),
                          children: actions)
        }
        return UIMenu(title: "Add Modifier", children: submenus)
    }

    private func addModifier(_ raw: String) {
        let text = self.text ?? ""
        guard let caret = caretIndex(in: text),
              let insertion = SwimTextFieldResolver.modifierInsertion(of: raw, in: text, onLineContaining: caret)
        else { return }
        replace(NSRange(insertion.index..<insertion.index, in: text), with: insertion.replacement)
    }

    private func addNote() {
        let text = self.text ?? ""
        guard let caret = caretIndex(in: text),
              let insertion = SwimTextFieldResolver.commentInsertion(in: text, onLineContaining: caret)
        else { return }
        // Caret lands after " | ", ready for the note.
        replace(NSRange(insertion.index..<insertion.index, in: text), with: insertion.replacement)
    }

    /// The caret as a `String.Index` into `text`, or nil if there's a selection
    /// span rather than an insertion point we can resolve.
    private func caretIndex(in text: String) -> String.Index? {
        Range(NSRange(location: selectedRange.location, length: 0), in: text)?.lowerBound
    }

    private func menu(for field: SwimTextField, in text: String) -> UIMenu {
        switch field.kind {
        case .date:
            return dateMenu(current: field.currentRaw)
        case .categories:
            return categoriesMenu()
        case .course:
            return optionMenu(for: field) { [weak self] raw in self?.setMetadataValue(raw) }
        case .stroke, .activity, .equipment, .effortLevel, .effortShape:
            let nsRange = NSRange(field.range, in: text)
            let token = field.currentRaw
            return optionMenu(for: field) { [weak self] raw in
                self?.replace(nsRange, with: raw, expecting: token)
            }
        }
    }

    /// A single-selection list of the canonical options for `field`.
    private func optionMenu(for field: SwimTextField, apply: @escaping (String) -> Void) -> UIMenu {
        let current = field.currentRaw.lowercased()
        let actions = SwimTextFieldResolver.rawOptions(for: field.kind).map { raw in
            UIAction(title: SwimTextFieldStyle.optionLabel(raw, kind: field.kind),
                     state: raw == current ? .on : .off) { _ in apply(raw) }
        }
        return UIMenu(title: SwimTextFieldStyle.menuTitle(field.kind),
                      options: .singleSelection, children: actions)
    }

    /// Multi-select category toggles that keep the menu open. The options are
    /// built in an *uncached* deferred element so they re-evaluate (refreshing
    /// checkmarks) after each `keepsMenuPresented` tap, and the toggle suppresses
    /// the bar rebuild so the open menu survives.
    private func categoriesMenu() -> UIMenu {
        let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { completion([]); return }
            let current = self.currentCategoryList()
            let actions = SwimTextFieldResolver.rawOptions(for: .categories).map { raw in
                UIAction(title: SwimTextFieldStyle.optionLabel(raw, kind: .categories),
                         attributes: [.keepsMenuPresented],
                         state: current.contains(raw) ? .on : .off) { [weak self] _ in
                    self?.toggleCategory(raw)
                }
            }
            completion(actions)
        }
        return UIMenu(title: SwimTextFieldStyle.menuTitle(.categories), children: [deferred])
    }

    /// The categories currently on the caret's line.
    private func currentCategoryList() -> [String] {
        let text = self.text ?? ""
        guard let caret = caretIndex(in: text),
              let field = SwimTextFieldResolver.fields(in: text, onLineContaining: caret)
                .first(where: { $0.kind == .categories })
        else { return [] }
        return SwimTextFieldStyle.categoryList(field.currentRaw)
    }

    private func toggleCategory(_ raw: String) {
        suppressContextRefresh = true
        defer { suppressContextRefresh = false }
        var list = currentCategoryList()
        if let index = list.firstIndex(of: raw) { list.remove(at: index) } else { list.append(raw) }
        setMetadataValue(list.joined(separator: ", "))
    }

    /// Relative-date shortcuts plus a full calendar.
    private func dateMenu(current: String) -> UIMenu {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        func iso(_ daysFromNow: Int) -> String {
            let day = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
            return formatter.string(from: day)
        }
        let initial = formatter.date(from: current) ?? Date()
        let actions: [UIMenuElement] = [
            UIAction(title: "Today") { [weak self] _ in self?.setMetadataValue(iso(0)) },
            UIAction(title: "Yesterday") { [weak self] _ in self?.setMetadataValue(iso(-1)) },
            UIAction(title: "Tomorrow") { [weak self] _ in self?.setMetadataValue(iso(1)) },
            UIAction(title: "Choose Date…", image: UIImage(systemName: "calendar")) { [weak self] _ in
                self?.presentDatePicker(initial: initial, formatter: formatter)
            },
            UIAction(title: "Clear", attributes: .destructive) { [weak self] _ in self?.setMetadataValue("") },
        ]
        return UIMenu(title: SwimTextFieldStyle.menuTitle(.date), children: actions)
    }

    /// Presents an inline calendar in a sheet, writing the chosen day back to the
    /// `date:` line. Anchored from the app window since the bar lives in the
    /// keyboard window and can't present.
    private func presentDatePicker(initial: Date, formatter: DateFormatter) {
        guard let presenter = topViewController() else { return }
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.date = initial
        picker.translatesAutoresizingMaskIntoConstraints = false

        let content = UIViewController()
        content.title = "Date"
        content.view.backgroundColor = .systemBackground
        content.view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: content.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            picker.leadingAnchor.constraint(equalTo: content.view.layoutMarginsGuide.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: content.view.layoutMarginsGuide.trailingAnchor),
        ])

        let nav = UINavigationController(rootViewController: content)
        content.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel, primaryAction: UIAction { _ in nav.dismiss(animated: true) })
        content.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done, primaryAction: UIAction { [weak self] _ in
                self?.setMetadataValue(formatter.string(from: picker.date))
                nav.dismiss(animated: true)
            })
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(nav, animated: true)
    }

    private func topViewController() -> UIViewController? {
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - Applying a swap

    /// Replaces `nsRange` with `replacement`, keeps the caret just after it, and
    /// notifies the binding. Re-highlighting follows from the storage edit.
    ///
    /// `expecting`, when set, must still match the characters at `nsRange` — a
    /// guard against a captured range going stale if the text was edited between
    /// building the menu and tapping it. On mismatch the swap is dropped rather
    /// than corrupting an unrelated span.
    private func replace(_ nsRange: NSRange, with replacement: String, expecting: String? = nil) {
        guard nsRange.location + nsRange.length <= textStorage.length else { return }
        if let expecting, (textStorage.string as NSString).substring(with: nsRange) != expecting {
            return
        }
        textStorage.replaceCharacters(in: nsRange, with: replacement)
        selectedRange = NSRange(location: nsRange.location + (replacement as NSString).length, length: 0)
        onSwap?(self.text ?? "")
        refreshContextBar()
    }

    /// Rewrites the value clause of the metadata line the caret sits on to
    /// `key: value` (or a bare `key:` when `value` is empty), normalizing spacing.
    private func setMetadataValue(_ value: String) {
        let text = self.text ?? ""
        guard let caret = caretIndex(in: text) else { return }
        let lineStart = text[..<caret].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[caret...].firstIndex(of: "\n") ?? text.endIndex
        guard let colon = text[lineStart..<lineEnd].firstIndex(of: ":") else { return }
        let clause = text.index(after: colon)..<lineEnd
        replace(NSRange(clause, in: text), with: value.isEmpty ? "" : " " + value)
    }
}

extension SwimTextView: @MainActor NSTextStorageDelegate {
    public func textStorage(_ textStorage: NSTextStorage,
                            didProcessEditing editedMask: NSTextStorage.EditActions,
                            range editedRange: NSRange,
                            changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        applyHighlighting()
    }
}

#elseif canImport(AppKit)
import AppKit

/// An `NSTextView` subclass that syntax-highlights SwimText as it changes.
/// See the UIKit variant above for behavior; both share ``SwimTextHighlighter``.
public final class SwimTextView: NSTextView {

    public var swimTheme: SwimTextTheme = .standard {
        didSet { applyHighlighting() }
    }

    public var swimFont: PlatformFont = SwimTextHighlighter.defaultFont {
        didSet {
            font = swimFont
            applyHighlighting()
        }
    }

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        textStorage?.delegate = self
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isRichText = false
        font = swimFont
        textColor = PlatformColor(swimTheme.plain)
        applyHighlighting()
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: swimFont, .foregroundColor: PlatformColor(swimTheme.plain)]
    }

    private func applyHighlighting() {
        guard let storage = textStorage else { return }
        let string = storage.string
        let full = NSRange(location: 0, length: storage.length)
        storage.setAttributes(baseAttributes, range: full)
        let emphasized = PlatformFont.monospacedSystemFont(ofSize: swimFont.pointSize, weight: .semibold)
        for token in SwimTextLexer.tokens(in: string) {
            let nsRange = NSRange(token.range, in: string)
            storage.addAttribute(.foregroundColor,
                                 value: PlatformColor(swimTheme.color(for: token.kind)),
                                 range: nsRange)
            if swimTheme.isEmphasized(token.kind) {
                storage.addAttribute(.font, value: emphasized, range: nsRange)
            }
        }
        // Thick dotted underline marks swappable spans, drawn in each token's own
        // foreground color (no underline color set). See the UIKit variant.
        let dotted = NSUnderlineStyle([.thick, .patternDot]).rawValue
        for field in SwimTextFieldResolver.fields(in: string) where !field.range.isEmpty {
            storage.addAttribute(.underlineStyle, value: dotted, range: NSRange(field.range, in: string))
        }
    }
}

extension SwimTextView: @MainActor NSTextStorageDelegate {
    public func textStorage(_ textStorage: NSTextStorage,
                            didProcessEditing editedMask: NSTextStorageEditActions,
                            range editedRange: NSRange,
                            changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        applyHighlighting()
    }
}

#endif
