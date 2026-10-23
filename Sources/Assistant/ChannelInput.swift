import SwiftUI
import AppKit

/// The editable value is also the query for the classroom dropdown.
struct ChannelInput: NSViewRepresentable {
    @Binding var text: String
    var channels: [String]
    var onSubmit: () -> Void
    /// Mirrors whether the system list is showing (accent border + chevron on the enclosing field).
    var isOpen: Binding<Bool> = .constant(false)
    /// Re-frame the system list to the enclosing field: extra width left/right, dropped to the field's bottom edge.
    var menuLeading: CGFloat = 0
    var menuTrailing: CGFloat = 0
    var menuDrop: CGFloat = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSComboBox {
        let field = ChannelComboBox()
        field.placeholderString = "频道号"
        field.setAccessibilityLabel("频道号")
        field.font = .systemFont(ofSize: 15, weight: .regular)   // same as the 新建课程 picker below
        field.focusRingType = .none   // picker below has no focus ring
        field.isBordered = false
        field.isBezeled = false
        field.isButtonBordered = false   // no white bezel: sits on the card field fill like the picker
        field.drawsBackground = false
        field.isEditable = true
        field.completes = false
        field.usesDataSource = true
        field.numberOfVisibleItems = 6
        field.itemHeight = 32   // list rows: 32 high like every other dropdown panel
        field.delegate = context.coordinator
        field.dataSource = context.coordinator
        if CommandLine.arguments.contains("--preview"), CommandLine.arguments.contains("--preview-channels") {   // dev screenshots: list open
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { field.setAccessibilityExpanded(true) }
        }
        return field
    }

    func updateNSView(_ field: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        context.coordinator.refresh(field)
    }

    final class Coordinator: NSObject, NSComboBoxDataSource, NSComboBoxDelegate {
        var parent: ChannelInput
        var matches: [String] = []
        init(_ parent: ChannelInput) { self.parent = parent }

        func refresh(_ field: NSComboBox) {
            let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let filtered = Array(Set(parent.channels)).sorted().filter { query.isEmpty || $0.contains(query) }
            if filtered != matches {
                matches = filtered
                field.reloadData()
            }
        }

        func numberOfItems(in comboBox: NSComboBox) -> Int { matches.count }
        func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
            matches.indices.contains(index) ? matches[index] : nil
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSComboBox else { return }
            parent.text = field.stringValue
            refresh(field)
        }
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSComboBox,
                  matches.indices.contains(field.indexOfSelectedItem) else { return }
            let channel = matches[field.indexOfSelectedItem]
            // AppKit finishes applying its selection before SwiftUI reloads the data source.
            DispatchQueue.main.async { [weak self] in self?.parent.text = channel }
        }
        func comboBoxWillPopUp(_ notification: Notification) {
            guard let field = notification.object as? NSComboBox else { return }
            parent.isOpen.wrappedValue = true
            DispatchQueue.main.async { [weak self] in self?.alignPopup(field) }
        }
        /// Keep the system list; only move/resize its window to line up with the 44pt field.
        private func alignPopup(_ field: NSComboBox) {
            guard let host = field.window else { return }
            let r = host.convertToScreen(field.convert(field.bounds, to: nil))
            for w in NSApp.windows where w !== host && w.isVisible && w.frame.maxY <= r.maxY && w.frame.maxY >= r.minY - 8 && abs(w.frame.minX - r.minX) < 40 {
                var f = w.frame
                f.origin.x = r.minX - parent.menuLeading
                f.size.width = r.width + parent.menuLeading + parent.menuTrailing
                f.origin.y = r.minY - parent.menuDrop - f.height
                w.setFrame(f, display: true)
                style(w)
            }
        }
        /// Same look as the custom dropdown panels: white, 1px cardBorder, r12, inset 32pt rows, 13pt text, faint shadow.
        private func style(_ w: NSWindow) {
            guard let content = w.contentView else { return }
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            content.wantsLayer = true
            content.layer?.cornerRadius = 12
            content.layer?.cornerCurve = .continuous
            content.layer?.masksToBounds = true
            content.layer?.borderWidth = 1
            content.effectiveAppearance.performAsCurrentDrawingAppearance {
                content.layer?.backgroundColor = NSColor(AppTheme.cardFill).cgColor
                content.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            }
            func walk(_ v: NSView) {
                if let scroll = v as? NSScrollView { scroll.drawsBackground = false; scroll.contentView.drawsBackground = false; scroll.automaticallyAdjustsContentInsets = false; scroll.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0) }
                if let table = v as? NSTableView {
                    table.backgroundColor = .clear
                    table.style = .inset
                    table.intercellSpacing = .zero
                    for column in table.tableColumns { (column.dataCell as? NSCell)?.font = .systemFont(ofSize: 13) }
                    table.reloadData()
                }
                v.subviews.forEach(walk)
            }
            walk(content)
        }
        func comboBoxWillDismiss(_ notification: Notification) {
            guard let field = notification.object as? NSComboBox else { return }
            parent.isOpen.wrappedValue = false
            DispatchQueue.main.async {   // Esc leaves the text selected (grey); collapse to an insertion point
                if let editor = field.currentEditor() { editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0) }
                field.cell?.isHighlighted = false; field.needsDisplay = true
                if field.stringValue.isEmpty { field.window?.makeFirstResponder(nil) }   // nothing typed: drop focus, no leftover highlight
            }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Esc maps to complete: in a field editor and leaves a grey completion highlight; swallow it (completes is off anyway).
            if selector == #selector(NSResponder.complete(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) { return true }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}


/// Ends editing when its window stops being key (popover opens), so no inactive grey field-editor fill is left behind.
final class ChannelComboBox: NSComboBox {
    override class var cellClass: AnyClass? { get { ChannelComboBoxCell.self } set {} }
    private var token: NSObjectProtocol?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let token { NotificationCenter.default.removeObserver(token) }
        guard let window else { return }
        token = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.cell?.isHighlighted = false; self.needsDisplay = true
        }
    }
}

/// Draws only the text: the system arrow stays clickable but invisible, the field draws the shared 11pt chevron instead.
final class ChannelComboBoxCell: NSComboBoxCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawInterior(withFrame: cellFrame, in: controlView)
    }
}
