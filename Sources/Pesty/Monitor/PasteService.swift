import AppKit
import Carbon.HIToolbox

/// How a clip's content is written to the pasteboard when pasting.
enum PasteFormat {
    /// The clip exactly as captured.
    case original
    /// Text only, all formatting removed.
    case plainText
    /// Bold, italic, underline, and links survive; fonts, sizes, and colors
    /// are normalized away.
    case cleanFormatting
    /// Rich content converted to Markdown text.
    case markdown
}

@MainActor
enum PasteService {
    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
    private static let packagedBundleID = "com.greycorelabs.pesty"

    /// How long the target app gets to read one clip of a multi-clip paste
    /// before the next one replaces it on the pasteboard. Nothing reports
    /// that a paste was consumed, so this errs on the side of a slow app.
    private static let sequenceInterval: TimeInterval = 0.3
    /// Bumped by every paste, so a sequence still in flight stops rather
    /// than interleaving with the paste that followed it.
    private static var sequenceGeneration = 0

    private static func markSource(of item: ClipItem, on pasteboard: NSPasteboard) {
        let source = item.sourceBundleID ?? Bundle.main.bundleIdentifier ?? packagedBundleID
        pasteboard.setString(source, forType: sourceType)
    }

    @discardableResult
    static func copy(_ item: ClipItem,
                     format: PasteFormat = .original,
                     to pasteboard: NSPasteboard = .general) -> Int {
        switch format {
        case .plainText:
            if let text = item.plainText {
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                markSource(of: item, on: pasteboard)
                return pasteboard.changeCount
            }
        case .cleanFormatting:
            if let rtf = FormatConverter.cleanedRTF(for: item) {
                pasteboard.clearContents()
                pasteboard.setData(rtf, forType: .rtf)
                if let text = item.plainText { pasteboard.setString(text, forType: .string) }
                markSource(of: item, on: pasteboard)
                return pasteboard.changeCount
            }
            // No rich source to clean: plain text is the honest result.
            if item.plainText != nil {
                return copy(item, format: .plainText, to: pasteboard)
            }
        case .markdown:
            if let markdown = FormatConverter.markdown(for: item) {
                pasteboard.clearContents()
                pasteboard.setString(markdown, forType: .string)
                markSource(of: item, on: pasteboard)
                return pasteboard.changeCount
            }
            if item.plainText != nil {
                return copy(item, format: .plainText, to: pasteboard)
            }
        case .original:
            break
        }
        if item.type == .image {
            guard let img = ClipboardStore.shared.loadImage(for: item) else {
                return pasteboard.changeCount
            }
            pasteboard.clearContents()
            pasteboard.writeObjects([img])
            markSource(of: item, on: pasteboard)
            return pasteboard.changeCount
        }
        pasteboard.clearContents()
        switch item.type {
        case .image:
            break
        case .file:
            let urls = item.fileURLs.compactMap { URL(string: $0) }
            if !urls.isEmpty { pasteboard.writeObjects(urls as [NSURL]) }
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        case .color:
            if let hex = item.colorHex, let c = NSColor(hex: hex) {
                pasteboard.writeObjects([c])
                pasteboard.setString(hex, forType: .string)
            }
        case .richText:
            if let rtf = item.rtfData { pasteboard.setData(rtf, forType: .rtf) }
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        case .text, .link:
            if let t = item.text { pasteboard.setString(t, forType: .string) }
        }
        markSource(of: item, on: pasteboard)
        return pasteboard.changeCount
    }

    /// Writes several clips as separate pasteboard items in one change, for
    /// when they cannot be pasted one at a time: a copy, or a paste without
    /// direct-paste access. Apps that read every item get them all; the rest
    /// take the first.
    @discardableResult
    static func copy(_ steps: [ClipItem], to pasteboard: NSPasteboard = .general) -> Int {
        guard steps.count > 1 else {
            return steps.first.map { copy($0, to: pasteboard) } ?? pasteboard.changeCount
        }
        let writers = steps.flatMap(writers(for:))
        guard !writers.isEmpty else { return pasteboard.changeCount }
        pasteboard.clearContents()
        pasteboard.writeObjects(writers)
        pasteboard.setString(Bundle.main.bundleIdentifier ?? packagedBundleID, forType: sourceType)
        return pasteboard.changeCount
    }

    private static func writers(for item: ClipItem) -> [NSPasteboardWriting] {
        switch item.type {
        case .image:
            return ClipboardStore.shared.loadImage(for: item).map { [$0] } ?? []
        case .file:
            return item.fileURLs.compactMap { URL(string: $0) as NSURL? }
        case .richText:
            if let rtf = item.rtfData,
               let rich = NSAttributedString(rtf: rtf, documentAttributes: nil) {
                return [rich]
            }
            return item.text.map { [$0 as NSString] } ?? []
        case .text, .link, .color:
            return item.plainText.map { [$0 as NSString] } ?? []
        }
    }

    static func paste(_ item: ClipItem,
                      into targetApp: NSRunningApplication?,
                      monitor: ClipboardMonitor,
                      format: PasteFormat = .original) {
        sequenceGeneration &+= 1
        let change = copy(item, format: format)
        monitor.suppressUntilChangeCount = change
        if Settings.shared.playSound { NSSound(named: "Pop")?.play() }

        guard let target = targetApp, !target.isTerminated else { return }

        #if MAS
        // Mac App Store (sandboxed) build: copy the clip and return focus to the
        // app the user came from so they can paste with ⌘V. No Accessibility
        // APIs and no synthetic keystrokes are used.
        target.activate()
        #else
        // Direct-download build: optionally paste straight into the active app by
        // synthesizing ⌘V. This requires the user's Accessibility grant.
        guard Settings.shared.pasteDirectly else { return }
        guard AXIsProcessTrusted() else {
            AppController.shared.noteBlockedDirectPaste()
            return
        }
        target.activate()
        waitForFrontmost(target, attempts: 20) { sendCommandV() }
        #endif
    }

    /// Pastes the steps of a multi-clip selection (see `ClipComposer`) in
    /// order. One step is an ordinary paste. Several are written and pasted
    /// one at a time, which is the only delivery every app understands for
    /// text next to images.
    static func paste(_ steps: [ClipItem],
                      into targetApp: NSRunningApplication?,
                      monitor: ClipboardMonitor) {
        guard steps.count > 1 else {
            if let only = steps.first { paste(only, into: targetApp, monitor: monitor) }
            return
        }
        sequenceGeneration &+= 1
        if Settings.shared.playSound { NSSound(named: "Pop")?.play() }

        #if !MAS
        if Settings.shared.pasteDirectly, AXIsProcessTrusted(),
           let target = targetApp, !target.isTerminated {
            target.activate()
            pasteNext(of: steps[...], into: target, monitor: monitor, generation: sequenceGeneration)
            return
        }
        #endif

        // Without a way to press Command-V between clips, the selection goes
        // out as one multi-item pasteboard for the user to paste.
        monitor.suppressUntilChangeCount = copy(steps)
        guard let target = targetApp, !target.isTerminated else { return }
        #if MAS
        target.activate()
        #else
        if Settings.shared.pasteDirectly { AppController.shared.noteBlockedDirectPaste() }
        #endif
    }

    #if !MAS
    private static func pasteNext(of steps: ArraySlice<ClipItem>,
                                  into app: NSRunningApplication,
                                  monitor: ClipboardMonitor,
                                  generation: Int) {
        guard generation == sequenceGeneration, !app.isTerminated,
              let step = steps.first else { return }
        let rest = steps.dropFirst()
        let previousChange = NSPasteboard.general.changeCount
        let change = copy(step)
        monitor.suppressUntilChangeCount = change
        // A step that wrote nothing (its image file is gone) must not send
        // Command-V: the previous clip is still on the pasteboard and would
        // be pasted a second time.
        guard change != previousChange else {
            pasteNext(of: rest, into: app, monitor: monitor, generation: generation)
            return
        }
        // Checked before every step, not just the first: if the user has
        // moved to another app, the rest of the selection stays unpasted
        // instead of landing there.
        waitForFrontmost(app, attempts: 20) {
            guard generation == sequenceGeneration else { return }
            sendCommandV()
            guard !rest.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + sequenceInterval) {
                pasteNext(of: rest, into: app, monitor: monitor, generation: generation)
            }
        }
    }

    private static func waitForFrontmost(_ app: NSRunningApplication,
                                         attempts: Int,
                                         then paste: @escaping @MainActor () -> Void) {
        guard attempts > 0, !app.isTerminated else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { paste() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            waitForFrontmost(app, attempts: attempts - 1, then: paste)
        }
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
    #endif
}
