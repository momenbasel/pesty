import AppKit

@MainActor
enum ClipEditor {
    enum Edit {
        case text(String, richTextData: Data?)
        case color(String)
    }

    static func run(for item: ClipItem, launchWritingTools: Bool = false) -> Edit? {
        NSApp.activate(ignoringOtherApps: true)
        switch item.type {
        case .text, .richText, .link:
            return TextClipEditorController(item: item,
                                            launchWritingTools: launchWritingTools).run()
        case .color:
            return editColor(item)
        case .image, .file:
            showUnsupportedEditor(for: item)
            return nil
        }
    }

    private static func editColor(_ item: ClipItem) -> Edit? {
        let alert = NSAlert()
        alert.messageText = "Edit Color"
        alert.informativeText = "Choose the color stored in this clip."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let color = item.colorHex.flatMap(NSColor.init(hex:)) ?? .black
        let accessory = ColorEditorAccessoryView(color: color)
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return .color(accessory.selectedHex)
    }

    private static func showUnsupportedEditor(for item: ClipItem) {
        let alert = NSAlert()
        alert.messageText = "This clip can't be edited"
        alert.informativeText = "Pesty can edit text, rich text, links, and colors. \(item.type.label) clips are kept as-is."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@MainActor
private final class TextClipEditorController: NSObject, NSTextViewDelegate, NSWindowDelegate {
    private let item: ClipItem
    private let launchWritingTools: Bool
    private let panel: NSPanel
    private let textView = NSTextView()
    private let saveButton = NSButton()
    private let statsLabel = NSTextField(labelWithString: "")
    private var result: ClipEditor.Edit?
    private var appliedRichFormatting = false

    init(item: ClipItem, launchWritingTools: Bool) {
        self.item = item
        self.launchWritingTools = launchWritingTools
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        configureEditor()
        buildInterface()
        loadInitialContent()
        updateStats()
    }

    func run() -> ClipEditor.Edit? {
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)

        if launchWritingTools {
            DispatchQueue.main.async { self.showWritingTools() }
        }

        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return result
    }

    func textDidChange(_ notification: Notification) {
        updateStats()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(with: nil)
        return false
    }

    private func configurePanel() {
        panel.delegate = self
        panel.title = "Edit \(item.type.label)"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
        panel.minSize = NSSize(width: 520, height: 380)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func configureEditor() {
        textView.delegate = self
        textView.frame = NSRect(x: 0, y: 0, width: 720, height: 420)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .complete
        }
    }

    private func buildInterface() {
        let effect = NSVisualEffectView()
        effect.material = .sheet
        effect.blendingMode = .withinWindow
        effect.state = .active
        panel.contentView = effect

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        saveButton.title = "Save"
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.keyEquivalentModifierMask = [.command]
        saveButton.bezelColor = .controlAccentColor
        saveButton.toolTip = "Save (⌘↩)"

        let formatting = NSStackView(views: [
            toolbarTextButton("B", tooltip: "Bold", action: #selector(toggleBold),
                              font: .systemFont(ofSize: 17, weight: .bold)),
            toolbarTextButton("I", tooltip: "Italic", action: #selector(toggleItalic),
                              font: NSFontManager.shared.convert(
                                .systemFont(ofSize: 17, weight: .semibold),
                                toHaveTrait: .italicFontMask
                              )),
            toolbarTextButton("U", tooltip: "Underline", action: #selector(toggleUnderline),
                              underline: true),
            toolbarTextButton("S", tooltip: "Strikethrough", action: #selector(toggleStrikethrough),
                              strikethrough: true)
        ])
        formatting.orientation = .horizontal
        formatting.spacing = 6

        if writingToolsAvailable {
            formatting.addArrangedSubview(
                toolbarSymbolButton(symbol: "pencil.and.scribble",
                                    tooltip: "Writing Tools",
                                    action: #selector(showWritingTools)))
        }

        let leadingSpacer = flexibleSpacer()
        let trailingSpacer = flexibleSpacer()
        let toolbar = NSStackView(views: [cancelButton, leadingSpacer, formatting, trailingSpacer, saveButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 10

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .lineBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 10

        statsLabel.font = .systemFont(ofSize: 13, weight: .regular)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.lineBreakMode = .byTruncatingTail

        for view in [toolbar, scrollView, statsLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -16),

            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 36),

            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: statsLabel.topAnchor, constant: -10),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),

            statsLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 4),
            statsLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -4),
            statsLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statsLabel.heightAnchor.constraint(equalToConstant: 18)
        ])

        leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor).isActive = true
    }

    private func loadInitialContent() {
        if item.type == .richText,
           let data = item.rtfData,
           let value = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            textView.textStorage?.setAttributedString(value)
        } else {
            textView.string = item.text ?? ""
        }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    private var writingToolsAvailable: Bool {
        guard #available(macOS 15.2, *) else { return false }
        return NSWritingToolsCoordinator.isWritingToolsAvailable
    }

    private func toolbarTextButton(_ title: String,
                                   tooltip: String,
                                   action: Selector,
                                   font: NSFont = .systemFont(ofSize: 17, weight: .semibold),
                                   underline: Bool = false,
                                   strikethrough: Bool = false) -> NSButton {
        let button = configuredToolbarButton(tooltip: tooltip, action: action)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        if underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        return button
    }

    private func toolbarSymbolButton(symbol: String,
                                     tooltip: String,
                                     action: Selector) -> NSButton {
        let button = configuredToolbarButton(tooltip: tooltip, action: action)
        let configuration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(configuration)
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        return button
    }

    private func configuredToolbarButton(tooltip: String,
                                         action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .rounded
        button.bezelColor = .controlBackgroundColor
        button.contentTintColor = .labelColor
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.widthAnchor.constraint(equalToConstant: 38).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    @objc private func cancel() {
        finish(with: nil)
    }

    @objc private func save() {
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let shouldSaveRichText = item.type == .richText || appliedRichFormatting
        let range = NSRange(location: 0, length: textView.textStorage?.length ?? 0)
        let richTextData = shouldSaveRichText ? textView.rtf(from: range) : nil
        finish(with: .text(text, richTextData: richTextData))
    }

    @objc private func showWritingTools() {
        guard #available(macOS 15.2, *), NSWritingToolsCoordinator.isWritingToolsAvailable else { return }
        panel.makeFirstResponder(textView)
        textView.showWritingTools(nil)
    }

    @objc private func toggleBold() {
        toggleFontTrait(.boldFontMask)
    }

    @objc private func toggleItalic() {
        toggleFontTrait(.italicFontMask)
    }

    @objc private func toggleUnderline() {
        toggleDecoration(.underlineStyle, enabledValue: NSUnderlineStyle.single.rawValue)
    }

    @objc private func toggleStrikethrough() {
        toggleDecoration(.strikethroughStyle, enabledValue: NSUnderlineStyle.single.rawValue)
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        let range = textView.selectedRange()
        let currentFont = font(at: range.location)
        let isEnabled = NSFontManager.shared.traits(of: currentFont).contains(trait)
        let transform: (NSFont) -> NSFont = { font in
            isEnabled
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
        }

        applyAttribute(.font, range: range, transform: transform)
    }

    private func toggleDecoration(_ key: NSAttributedString.Key, enabledValue: Int) {
        let range = textView.selectedRange()
        let current = decorationValue(for: key, at: range.location)
        let target = current == 0 ? enabledValue : 0

        if range.length == 0 {
            var attributes = textView.typingAttributes
            attributes[key] = target
            textView.typingAttributes = attributes
        } else {
            textView.textStorage?.addAttribute(key, value: target, range: range)
        }
        appliedRichFormatting = true
        panel.makeFirstResponder(textView)
    }

    private func applyAttribute(_ key: NSAttributedString.Key,
                                range: NSRange,
                                transform: (NSFont) -> NSFont) {
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let font = (attributes[key] as? NSFont) ?? textView.font ?? .systemFont(ofSize: 17)
            attributes[key] = transform(font)
            textView.typingAttributes = attributes
        } else if let storage = textView.textStorage {
            storage.beginEditing()
            storage.enumerateAttribute(key, in: range, options: []) { value, subrange, _ in
                let font = (value as? NSFont) ?? self.textView.font ?? .systemFont(ofSize: 17)
                storage.addAttribute(key, value: transform(font), range: subrange)
            }
            storage.endEditing()
        }
        appliedRichFormatting = true
        panel.makeFirstResponder(textView)
    }

    private func font(at location: Int) -> NSFont {
        guard let storage = textView.textStorage, storage.length > 0 else {
            return (textView.typingAttributes[.font] as? NSFont) ?? textView.font ?? .systemFont(ofSize: 17)
        }
        let safeLocation = min(max(location, 0), storage.length - 1)
        return (storage.attribute(.font, at: safeLocation, effectiveRange: nil) as? NSFont)
            ?? textView.font
            ?? .systemFont(ofSize: 17)
    }

    private func decorationValue(for key: NSAttributedString.Key, at location: Int) -> Int {
        guard let storage = textView.textStorage, storage.length > 0 else {
            return textView.typingAttributes[key] as? Int ?? 0
        }
        let safeLocation = min(max(location, 0), storage.length - 1)
        return storage.attribute(key, at: safeLocation, effectiveRange: nil) as? Int ?? 0
    }

    private func updateStats() {
        let text = textView.string
        let characters = text.count
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let lines = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
        let characterStat = "\(characters) \(countLabel(characters, singular: "character"))"
        let wordStat = "\(words) \(countLabel(words, singular: "word"))"
        let lineStat = "\(lines) \(countLabel(lines, singular: "line"))"
        statsLabel.stringValue = [characterStat, wordStat, lineStat].joined(separator: "  ·  ")
        saveButton.isEnabled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        count == 1 ? singular : "\(singular)s"
    }

    private func finish(with value: ClipEditor.Edit?) {
        result = value
        panel.orderOut(nil)
        NSApp.stopModal()
    }
}

@MainActor
private final class ColorEditorAccessoryView: NSStackView {
    private let colorWell: NSColorWell
    private let valueLabel: NSTextField

    init(color: NSColor) {
        colorWell = NSColorWell()
        valueLabel = NSTextField(labelWithString: color.hexString)
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 32))

        orientation = .horizontal
        alignment = .centerY
        spacing = 10

        let label = NSTextField(labelWithString: "Color:")
        valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        colorWell.color = color
        colorWell.target = self
        colorWell.action = #selector(colorDidChange)
        colorWell.widthAnchor.constraint(equalToConstant: 42).isActive = true

        addArrangedSubview(label)
        addArrangedSubview(colorWell)
        addArrangedSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var selectedHex: String { colorWell.color.hexString }

    @objc private func colorDidChange() {
        valueLabel.stringValue = selectedHex
    }
}
