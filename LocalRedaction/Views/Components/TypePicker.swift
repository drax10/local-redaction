import AppKit
import SwiftUI

struct TypePicker: NSViewRepresentable {
    @Binding var type: PIIType

    func makeCoordinator() -> Coordinator {
        Coordinator(type: $type)
    }

    func makeNSView(context: Context) -> TypeChipButton {
        let button = TypeChipButton()
        button.coordinator = context.coordinator
        button.refresh(type: type)
        return button
    }

    func updateNSView(_ button: TypeChipButton, context: Context) {
        context.coordinator.type = $type
        button.coordinator = context.coordinator
        if button.currentType != type {
            button.refresh(type: type)
        }
    }

    final class Coordinator {
        var type: Binding<PIIType>

        init(type: Binding<PIIType>) {
            self.type = type
        }

        func select(_ value: PIIType) {
            type.wrappedValue = value
        }
    }
}

final class TypeChipButton: NSButton {
    weak var coordinator: TypePicker.Coordinator?
    private(set) var currentType: PIIType = .name

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .inline
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        target = self
        action = #selector(showMenu)
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        nil
    }

    func refresh(type: PIIType) {
        currentType = type
        let title = " \(type.displayName) "
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ]
        )
        layer?.backgroundColor = type.badgeNSColor.cgColor
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let size = attributedTitle.size()
        return NSSize(width: ceil(size.width) + 12, height: 22)
    }

    @objc private func showMenu() {
        guard let coordinator else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for option in PIIType.allCases {
            let item = NSMenuItem(
                title: option.displayName,
                action: #selector(pick(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == coordinator.type.wrappedValue ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = PIIType(rawValue: raw) else {
            return
        }
        coordinator?.select(value)
        refresh(type: value)
    }
}
