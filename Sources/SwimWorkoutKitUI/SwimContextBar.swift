// SPDX-License-Identifier: MIT

import SwimWorkoutKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// A keyboard accessory bar that shows a small pop-up list for each swappable
/// ``SwimTextField`` on the caret's current line. Driven by ``SwimTextView``:
/// place the cursor on a set line and chips appear for its stroke, effort, etc.;
/// place it on `course: scy` and a pool-size chip appears. Tapping a chip swaps
/// the value in place. Single-tap still just positions the caret, so free-text
/// editing is never interrupted.
final class SwimContextBar: UIInputView {

    /// One chip. Most carry a `menu` (swap a value, or add a modifier); a few
    /// carry a direct `action` instead (e.g. start an inline comment).
    struct Item {
        let title: String
        let systemImage: String?
        var menu: UIMenu? = nil
        var action: (() -> Void)? = nil
    }

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let hint = UILabel()
    private let dismissButton = UIButton(type: .system)

    /// Called when the hide-keyboard button is tapped. The bar lives in the
    /// keyboard window, so the owning text view resigns on its behalf.
    var onDismiss: (() -> Void)?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        autoresizingMask = .flexibleWidth
        allowsSelfSizing = true

        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceHorizontal = true
        addSubview(scroll)

        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.textColor = .tertiaryLabel
        hint.adjustsFontForContentSizeCategory = true
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)

        dismissButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        dismissButton.tintColor = .secondaryLabel
        dismissButton.accessibilityLabel = "Hide Keyboard"
        dismissButton.addAction(UIAction { [weak self] _ in self?.onDismiss?() }, for: .touchUpInside)
        dismissButton.setContentHuggingPriority(.required, for: .horizontal)
        dismissButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),

            hint.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: dismissButton.leadingAnchor, constant: -8),
            hint.centerYAnchor.constraint(equalTo: centerYAnchor),

            dismissButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44) }

    /// Rebuilds the bar for `items`. Empty hides the chips and shows a one-line
    /// hint so the affordance is discoverable without crowding the keyboard.
    func configure(items: [Item]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        hint.isHidden = !items.isEmpty
        scroll.isHidden = items.isEmpty
        guard !items.isEmpty else {
            hint.text = "Tap a stroke, effort, or pool value to change it"
            return
        }
        for item in items {
            stack.addArrangedSubview(makeChip(item))
        }
    }

    /// A chip is a filled pill (the tappable affordance) with an icon+value on
    /// top and a background-free menu button in between.
    ///
    /// The pill fill lives on the *container*; the menu's source is a clear
    /// `.custom` button with no fill of its own. So the only filled layer is the
    /// static pill — iOS has nothing on the source to morph into Liquid Glass,
    /// which is what previously "doubled" against the pill on dismiss. The
    /// content is a sibling above the button (not its child), so the chip stays
    /// anchored while its list is open instead of flowing into the menu.
    private func makeChip(_ item: Item) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .secondarySystemFill
        container.layer.cornerRadius = 16
        container.layer.cornerCurve = .continuous
        container.setContentHuggingPriority(.required, for: .horizontal)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Menu source (or tap target), behind the content. Plain .custom so it
        // carries no fill of its own — see the doubling note above.
        let button = UIButton(type: .custom)
        if let menu = item.menu {
            button.menu = menu
            button.showsMenuAsPrimaryAction = true
        } else if let action = item.action {
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)

        let label = UILabel()
        label.text = item.title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 4
        row.alignment = .center
        row.isUserInteractionEnabled = false   // taps fall through to the button
        row.translatesAutoresizingMaskIntoConstraints = false
        if let name = item.systemImage, let image = UIImage(systemName: name) {
            let icon = UIImageView(image: image)
            icon.tintColor = .secondaryLabel
            icon.contentMode = .scaleAspectFit
            icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
            row.addArrangedSubview(icon)
        }
        row.addArrangedSubview(label)
        container.addSubview(row)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 32),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 11),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -11),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }
}

/// Presentation for ``SwimTextField`` kinds — chip titles, menu titles, icons,
/// and option labels. Kept in the UI layer so the core kit stays display-free.
enum SwimTextFieldStyle {

    /// The menu's title — the axis being changed.
    static func menuTitle(_ kind: SwimTextField.Kind) -> String {
        switch kind {
        case .stroke:      return "Stroke"
        case .activity:    return "Activity"
        case .equipment:   return "Equipment"
        case .effortLevel: return "Effort"
        case .effortShape: return "Shape"
        case .course:      return "Pool"
        case .categories:  return "Categories"
        case .date:        return "Date"
        }
    }

    static func icon(_ kind: SwimTextField.Kind) -> String {
        switch kind {
        case .stroke:      return "figure.pool.swim"
        case .activity:    return "figure.run"
        case .equipment:   return "gearshape"
        case .effortLevel: return "gauge.with.dots.needle.67percent"
        case .effortShape: return "chart.line.uptrend.xyaxis"
        case .course:      return "ruler"
        case .categories:  return "tag"
        case .date:        return "calendar"
        }
    }

    /// The chip's title: the current value, abbreviated to fit the bar.
    static func chipTitle(for field: SwimTextField) -> String {
        switch field.kind {
        case .course:
            return field.currentRaw.isEmpty ? menuTitle(.course) : field.currentRaw.uppercased()
        case .categories:
            let list = categoryList(field.currentRaw)
            guard let first = list.first else { return menuTitle(.categories) }
            let extra = list.count - 1
            return extra > 0 ? "\(optionLabel(first, kind: .categories)) +\(extra)"
                             : optionLabel(first, kind: .categories)
        case .date:
            return field.currentRaw.isEmpty ? menuTitle(.date) : field.currentRaw
        default:
            return optionLabel(field.currentRaw, kind: field.kind)
        }
    }

    /// A human label for one raw option token.
    static func optionLabel(_ raw: String, kind: SwimTextField.Kind) -> String {
        switch kind {
        case .stroke:
            switch raw {
            case "im": return "IM"
            case "imo": return "IM Order"
            case "rimo": return "Reverse IM"
            default: return raw.capitalized
            }
        case .effortShape:
            switch raw {
            case "ns": return "Negative Split"
            case "vs": return "Variable Sprint"
            default: return raw.capitalized
            }
        case .course:
            switch raw {
            case "scy": return "SCY · 25 yd"
            case "scm": return "SCM · 25 m"
            case "lcm": return "LCM · 50 m"
            default: return raw.uppercased()
            }
        case .categories:
            switch raw {
            case "im": return "IM"
            case "openwater": return "Open Water"
            case "lowvolume": return "Low Volume"
            default: return raw.capitalized
            }
        case .activity, .equipment, .effortLevel, .date:
            return raw.capitalized
        }
    }

    /// Splits a "sprint, distance" categories value into its raw tokens.
    static func categoryList(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}
#endif
