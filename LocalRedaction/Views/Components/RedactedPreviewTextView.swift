import AppKit
import SwiftUI

struct RedactedPreviewTextView: NSViewRepresentable {
    let text: String
    var highlightNeedle: String
    var highlightPulse: Int
    var onSelectionChange: (String) -> Void
    var onRedact: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange, onRedact: onRedact)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let preview = PreviewTextView()
        preview.minSize = .zero
        preview.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        preview.isVerticallyResizable = true
        preview.isHorizontallyResizable = false
        preview.autoresizingMask = [.width]
        preview.textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        preview.textContainer?.widthTracksTextView = true
        preview.textContainer?.heightTracksTextView = false
        preview.font = .systemFont(ofSize: NSFont.systemFontSize)
        preview.textColor = .textColor
        preview.backgroundColor = .textBackgroundColor
        preview.drawsBackground = true
        preview.isEditable = false
        preview.isSelectable = true
        preview.isRichText = false
        preview.usesFindBar = true
        preview.textContainerInset = NSSize(width: 12, height: 12)
        preview.delegate = context.coordinator
        preview.onSelectionChange = context.coordinator.onSelectionChange
        preview.onRedact = context.coordinator.onRedact
        preview.string = text

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = preview
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onRedact = onRedact

        guard let textView = scrollView.documentView as? PreviewTextView else { return }
        textView.onSelectionChange = onSelectionChange
        textView.onRedact = onRedact

        let textChanged = textView.string != text
        if textChanged {
            let origin = scrollView.contentView.bounds.origin
            textView.string = text
            textView.hideCallout()
            scrollView.documentView?.scroll(origin)
        }

        let shouldPulse = context.coordinator.lastHighlightPulse != highlightPulse
        context.coordinator.lastHighlightPulse = highlightPulse
        textView.highlightOccurrences(
            of: highlightNeedle,
            pulse: shouldPulse && !highlightNeedle.isEmpty
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectionChange: (String) -> Void
        var onRedact: (String) -> Void
        var lastHighlightPulse = -1

        init(onSelectionChange: @escaping (String) -> Void, onRedact: @escaping (String) -> Void) {
            self.onSelectionChange = onSelectionChange
            self.onRedact = onRedact
        }
    }
}

final class PreviewTextView: NSTextView {
    var onSelectionChange: ((String) -> Void)?
    var onRedact: ((String) -> Void)?

    private var callout: NSHostingView<RedactCallout>?

    var selectedSnippet: String {
        let range = selectedRange()
        guard range.length > 0 else { return "" }
        let nsString = string as NSString
        guard range.location + range.length <= nsString.length else { return "" }
        return nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting {
            refreshSelectionUI()
        } else {
            hideCallout()
        }
    }

    override func layout() {
        super.layout()
        if let width = enclosingScrollView?.contentSize.width, width > 0, abs(frame.width - width) > 0.5 {
            frame.size.width = width
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let snippet = selectedSnippet
        if RedactionSelection.isRedactable(snippet) {
            let item = NSMenuItem(title: "Redactar", action: #selector(performRedact), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        return menu
    }

    @objc func performRedact() {
        let snippet = selectedSnippet
        guard RedactionSelection.isRedactable(snippet) else { return }
        onRedact?(snippet)
        setSelectedRange(NSRange(location: 0, length: 0))
        hideCallout()
        onSelectionChange?("")
    }

    func hideCallout() {
        callout?.removeFromSuperview()
        callout = nil
    }

    func highlightOccurrences(of needle: String, pulse: Bool) {
        clearHighlights()
        let trimmed = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let layoutManager else { return }

        let ranges = TextSpanLocator.nsRanges(of: trimmed, in: string)
        guard let first = ranges.first else { return }

        let color = NSColor.findHighlightColor.withAlphaComponent(0.85)
        for range in ranges {
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: color,
                forCharacterRange: range
            )
        }

        if pulse {
            scrollRangeToCenter(first)
            DispatchQueue.main.async { [weak self] in
                self?.showFindIndicator(for: first)
            }
        }
    }

    private func clearHighlights() {
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
    }

    private func scrollRangeToCenter(_ range: NSRange) {
        guard let layoutManager, let textContainer, let scrollView = enclosingScrollView else {
            scrollRangeToVisible(range)
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y

        let visibleHeight = scrollView.contentView.bounds.height
        let maxY = max(0, bounds.height - visibleHeight)
        let centeredY = rect.midY - visibleHeight / 2
        let origin = NSPoint(x: 0, y: min(max(0, centeredY), maxY))
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func refreshSelectionUI() {
        let snippet = selectedSnippet
        onSelectionChange?(snippet)

        hideCallout()
        guard RedactionSelection.isRedactable(snippet) else { return }

        let hosting = NSHostingView(rootView: RedactCallout { [weak self] in
            self?.performRedact()
        })
        hosting.sizingOptions = [.intrinsicContentSize]
        let size = hosting.fittingSize
        hosting.frame.size = size

        let screenRect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        guard let window else { return }
        let windowRect = window.convertFromScreen(screenRect)
        let localRect = convert(windowRect, from: nil)

        var origin = NSPoint(
            x: localRect.midX - size.width / 2,
            y: localRect.minY - size.height - 8
        )
        origin.x = min(max(4, origin.x), max(4, bounds.width - size.width - 4))
        if origin.y < 0 {
            origin.y = localRect.maxY + 8
        }

        hosting.frame.origin = origin
        addSubview(hosting)
        callout = hosting
    }
}

struct RedactCallout: View {
    let action: () -> Void

    var body: some View {
        Button("Redactar", systemImage: "eye.slash") {
            action()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}

enum RedactionSelection {
    static func isRedactable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        if trimmed.range(of: #"^\[[A-Z]+ (?:\d+|-)\]$"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }
}
