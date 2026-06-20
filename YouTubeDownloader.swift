import AppKit
import Foundation

private let defaultFirstRunLink = "https://www.youtube.com/watch?v=dQw4w9WgXcQ\n"
private let defaultLinkSeededKey = "defaultLinkSeeded"
private let specialVideoID = "dQw4w9WgXcQ"
private let specialVideoDisplayName = "Relaxing Sleep Sounds"
private let specialVideoKnownTitles = [
    "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)",
    "Rick Astley - Never Gonna Give You Up (Official Music Video)",
    "Never Gonna Give You Up"
]

enum OutputFormat: String {
    case mp3
    case mp4

    var buttonTitle: String {
        rawValue.uppercased()
    }
}

enum VideoResolution: String, CaseIterable {
    case best    = "best"
    case res2160 = "2160"
    case res1080 = "1080"
    case res720  = "720"
    case res480  = "480"

    var label: String {
        switch self {
        case .best:    return "Best Available"
        case .res2160: return "4K (2160p)"
        case .res1080: return "1080p"
        case .res720:  return "720p"
        case .res480:  return "480p"
        }
    }
}

final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class LineNumberRulerView: NSRulerView {
    private static let width: CGFloat = 32

    init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = Self.width
        reservedThicknessForMarkers = Self.width
        reservedThicknessForAccessoryView = 0
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var requiredThickness: CGFloat {
        Self.width
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let textFont = textView.font,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        layoutManager.ensureLayout(for: textContainer)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.34),
            .paragraphStyle: paragraphStyle
        ]

        let lineHeight = layoutManager.defaultLineHeight(for: textFont)
        let text = textView.string as NSString
        let origin = textView.textContainerOrigin
        let visibleRect = textView.visibleRect

        if text.length == 0 {
            drawLineNumber(1, y: origin.y - visibleRect.minY + 1, lineHeight: lineHeight, attributes: attributes)
            return
        }

        var lineNumber = 1
        var location = 0
        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(lineRange.location, text.length - 1))
            let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let y = origin.y + fragmentRect.minY - visibleRect.minY + 1

            if y + lineHeight >= rect.minY && y <= rect.maxY {
                drawLineNumber(lineNumber, y: y, lineHeight: lineHeight, attributes: attributes)
            }

            lineNumber += 1
            location = NSMaxRange(lineRange)
        }
    }

    private func drawLineNumber(_ lineNumber: Int, y: CGFloat, lineHeight: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let rect = NSRect(x: 1, y: y, width: Self.width - 4, height: lineHeight)
        ("\(lineNumber)" as NSString).draw(in: rect, withAttributes: attributes)
    }
}

final class LinkInputTextView: NSTextView {
    private static let leftInset: CGFloat = 3
    private static let rightInset: CGFloat = 8
    private static let topInset: CGFloat = 10
    private static let bottomInset: CGFloat = 14

    override var textContainerOrigin: NSPoint {
        NSPoint(x: Self.leftInset, y: Self.topInset)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTextContainerSize()
    }

    override func paste(_ sender: Any?) {
        guard let pastedText = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }

        let range = selectedRange()
        let sanitizedText = YouTubeLinkSanitizer.sanitizedPasteText(pastedText)
        let textToInsert = shouldPrefixPasteWithNewline(at: range.location, text: sanitizedText)
            ? "\n\(sanitizedText)"
            : sanitizedText
        insertText(textToInsert, replacementRange: range)
    }

    func configureTextContainer() {
        textContainerInset = NSSize(width: 0, height: Self.bottomInset)
        textContainer?.widthTracksTextView = false
        textContainer?.heightTracksTextView = false
        textContainer?.lineFragmentPadding = 0
        textContainer?.lineBreakMode = .byCharWrapping
        updateTextContainerSize()
    }

    private func updateTextContainerSize() {
        guard let textContainer else { return }

        textContainer.containerSize = NSSize(
            width: max(0, bounds.width - Self.leftInset - Self.rightInset),
            height: .greatestFiniteMagnitude
        )
    }

    static var placeholderOffset: CGFloat {
        leftInset
    }

    private func shouldPrefixPasteWithNewline(at location: Int, text: String) -> Bool {
        guard !text.isEmpty,
              !text.hasPrefix("\n"),
              !text.hasPrefix("\r"),
              location > 0 else {
            return false
        }

        let fullText = string as NSString
        let safeLocation = min(location, fullText.length)
        let lineRange = fullText.lineRange(for: NSRange(location: safeLocation, length: 0))
        guard safeLocation > lineRange.location else { return false }

        let beforePaste = fullText.substring(with: NSRange(location: lineRange.location, length: safeLocation - lineRange.location))
        return beforePaste.rangeOfCharacter(from: CharacterSet.whitespaces.inverted) != nil
    }
}

enum YouTubeLinkSanitizer {
    static func sanitizedPasteText(_ text: String) -> String {
        let urls = extractedURLs(from: text)
        let candidates = urls.isEmpty ? splitLooseCandidates(from: text) : urls
        let sanitized = candidates
            .map { sanitizedCandidate($0) }
            .filter { !$0.isEmpty }

        return sanitized.isEmpty ? text : sanitized.joined(separator: "\n")
    }

    private static func extractedURLs(from text: String) -> [String] {
        let pattern = #"https?://[^\s,"'<>]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private static func splitLooseCandidates(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split { character in
                character == "\n" || character == "," || character == "\t"
            }
            .map(String.init)
    }

    private static func sanitizedCandidate(_ candidate: String) -> String {
        let trimmed = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>"))
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;)"))

        guard let normalized = normalizedYouTubeURL(from: trimmed) else {
            return trimmed
        }

        return normalized
    }

    private static func normalizedYouTubeURL(from rawURL: String) -> String? {
        guard let components = URLComponents(string: rawURL),
              let host = components.host?.lowercased() else {
            return nil
        }

        let videoID: String?
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            videoID = components.path
                .split(separator: "/")
                .first
                .map(String.init)
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com") {
            if components.path == "/watch" {
                videoID = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else {
                let pathParts = components.path.split(separator: "/").map(String.init)
                if pathParts.count >= 2, ["shorts", "embed", "live"].contains(pathParts[0]) {
                    videoID = pathParts[1]
                } else {
                    videoID = nil
                }
            }
        } else {
            videoID = nil
        }

        guard let id = videoID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return nil
        }

        return "https://www.youtube.com/watch?v=\(id)"
    }
}

final class ActivityLogView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    private static let columnIdentifier = NSUserInterfaceItemIdentifier("ActivityLogColumn")
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("ActivityLogCell")
    private static let headerLines = ["============", "Activity Log", "============", ""]

    private let tableView = NSTableView()
    private var lines = headerLines

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        let column = NSTableColumn(identifier: Self.columnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = backgroundColor
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 18
        documentView = tableView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clear() {
        lines = Self.headerLines
        tableView.reloadData()
    }

    func append(_ text: String) {
        let chunks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard !chunks.isEmpty else { return }
        lines.append(contentsOf: chunks)
        tableView.reloadData()
        if !lines.isEmpty {
            tableView.scrollRowToVisible(lines.count - 1)
        }
    }

    var combinedText: String {
        lines.joined(separator: "\n")
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        lines.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = Self.cellIdentifier

        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = identifier
            textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            textField.textColor = .placeholderTextColor
            textField.backgroundColor = .clear
            textField.isBordered = false
            textField.lineBreakMode = .byClipping
            textField.maximumNumberOfLines = 1
        }

        textField.stringValue = lines[row]
        return textField
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate {
    private let projectDirectory: URL
    private let supportDirectory: URL
    private let defaults = UserDefaults.standard

    private var window: NSWindow!
    private let linksTextView = LinkInputTextView()
    private let linksPlaceholderLabel = PassthroughLabel(labelWithString: "Paste YouTube link(s) here")
    private let logView = ActivityLogView(frame: .zero)
    private let outputFolderLabel = NSTextField(labelWithString: "")
    private lazy var mp3Button = makeRadioButton(title: OutputFormat.mp3.buttonTitle, action: #selector(selectMP3))
    private lazy var mp4Button = makeRadioButton(title: OutputFormat.mp4.buttonTitle, action: #selector(selectMP4))
    private lazy var resolutionPopUp = makeResolutionPopUp()
    private lazy var downloadButton = makePrimaryButton(title: "Download", action: #selector(downloadLinks))
    private lazy var cancelButton = makeButton(title: "Cancel", action: #selector(cancelDownload))
    private lazy var chooseFolderButton = makeButton(title: "Save to...", action: #selector(chooseOutputFolder))
    private lazy var openFolderButton = makeButton(title: "Open", action: #selector(openFolder))

    private var autosaveWorkItem: DispatchWorkItem?
    private var activeProcess: Process?
    private var cancelRequested = false

    private var videoFileURL: URL {
        supportDirectory.appendingPathComponent("video.txt")
    }

    init(projectDirectory: URL) {
        self.projectDirectory = projectDirectory
        self.supportDirectory = AppDelegate.makeSupportDirectory()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApp()
        buildWindow()
        loadLinks()
        applySavedFormatSelection()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(linksTextView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        activeProcess?.terminate()
        persistLinks(showStatus: false)
    }

    func windowWillClose(_ notification: Notification) {
        persistLinks(showStatus: false)
    }

    func textDidChange(_ notification: Notification) {
        updatePlaceholderVisibility()
        linksTextView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        scheduleAutosave()
    }

    private func configureApp() {
        NSApp.setActivationPolicy(.regular)

        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(editMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit YouTube Downloader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "YouTube Downloader"
        window.delegate = self

        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView

        let linksScrollView = NSScrollView()
        linksScrollView.borderType = .noBorder
        linksScrollView.hasVerticalScroller = true
        linksScrollView.translatesAutoresizingMaskIntoConstraints = false
        linksScrollView.wantsLayer = true
        linksScrollView.layer?.cornerRadius = 8
        linksScrollView.layer?.masksToBounds = true
        linksScrollView.layer?.borderWidth = 1
        linksScrollView.layer?.borderColor = NSColor.separatorColor.cgColor
        linksScrollView.contentView.postsBoundsChangedNotifications = true
        linksTextView.isRichText = false
        linksTextView.isAutomaticQuoteSubstitutionEnabled = false
        linksTextView.isAutomaticDashSubstitutionEnabled = false
        linksTextView.isAutomaticTextReplacementEnabled = false
        linksTextView.usesFindBar = true
        linksTextView.isEditable = true
        linksTextView.isSelectable = true
        linksTextView.allowsUndo = true
        linksTextView.drawsBackground = true
        linksTextView.backgroundColor = .textBackgroundColor
        linksTextView.textColor = .textColor
        linksTextView.insertionPointColor = .controlAccentColor
        linksTextView.isHorizontallyResizable = false
        linksTextView.isVerticallyResizable = true
        linksTextView.autoresizingMask = [.width]
        linksTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        linksTextView.delegate = self
        linksTextView.configureTextContainer()
        linksPlaceholderLabel.font = .systemFont(ofSize: 15)
        linksPlaceholderLabel.textColor = .placeholderTextColor
        linksPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        linksScrollView.documentView = linksTextView
        linksScrollView.hasVerticalRuler = true
        linksScrollView.rulersVisible = true
        linksScrollView.verticalRulerView = LineNumberRulerView(textView: linksTextView, scrollView: linksScrollView)
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: linksScrollView.contentView,
            queue: .main
        ) { [weak linksScrollView] _ in
            linksScrollView?.verticalRulerView?.needsDisplay = true
        }
        linksTextView.addSubview(linksPlaceholderLabel)

        let resolutionLabel = NSTextField(labelWithString: "Resolution:")
        resolutionLabel.font = .systemFont(ofSize: 13)

        cancelButton.isEnabled = false

        let controlsSpacer = NSView()
        controlsSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        controlsSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let controlsStack = NSStackView(views: [mp3Button, mp4Button, resolutionLabel, resolutionPopUp, downloadButton, cancelButton, controlsSpacer, chooseFolderButton, openFolderButton])
        controlsStack.orientation = .horizontal
        controlsStack.spacing = 10
        controlsStack.alignment = .centerY

        let saveLabel = NSTextField(labelWithString: "Save to:")
        saveLabel.font = .systemFont(ofSize: 13)
        outputFolderLabel.font = .systemFont(ofSize: 12)
        outputFolderLabel.textColor = .secondaryLabelColor
        outputFolderLabel.lineBreakMode = .byTruncatingMiddle
        outputFolderLabel.maximumNumberOfLines = 1
        outputFolderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let folderStack = NSStackView(views: [saveLabel, outputFolderLabel])
        folderStack.orientation = .horizontal
        folderStack.spacing = 8
        folderStack.alignment = .centerY

        logView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [linksScrollView, controlsStack, folderStack, logView])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        updateOutputFolderLabel()

        rootView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -20),
            linksPlaceholderLabel.leadingAnchor.constraint(equalTo: linksTextView.leadingAnchor, constant: LinkInputTextView.placeholderOffset),
            linksPlaceholderLabel.topAnchor.constraint(equalTo: linksTextView.topAnchor, constant: 10),
            linksScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            logView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
    }

    private func makeResolutionPopUp() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for resolution in VideoResolution.allCases {
            popup.addItem(withTitle: resolution.label)
            popup.lastItem?.representedObject = resolution.rawValue
        }
        popup.action = #selector(resolutionChanged)
        popup.target = self
        return popup
    }

    @objc private func resolutionChanged() {
        // Resolution intentionally resets to Best Available on each launch.
    }

    private func selectedResolution() -> VideoResolution {
        guard let raw = resolutionPopUp.selectedItem?.representedObject as? String,
              let res = VideoResolution(rawValue: raw) else {
            return .best
        }
        return res
    }

    private func setSelectedResolution(_ resolution: VideoResolution) {
        for (index, item) in resolutionPopUp.itemArray.enumerated() {
            if item.representedObject as? String == resolution.rawValue {
                resolutionPopUp.selectItem(at: index)
                break
            }
        }
        resolutionPopUp.isEnabled = selectedFormat() == .mp4
    }

    private func makeRadioButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: self, action: action)
        button.setButtonType(.radio)
        return button
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func makePrimaryButton(title: String, action: Selector) -> NSButton {
        let button = makeButton(title: title, action: action)
        button.bezelColor = .controlAccentColor
        button.contentTintColor = .white
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            ]
        )
        return button
    }

    private func loadLinks() {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let hasSeededDefaultLink = defaults.bool(forKey: defaultLinkSeededKey)

            if FileManager.default.fileExists(atPath: videoFileURL.path) {
                let savedLinks = try String(contentsOf: videoFileURL, encoding: .utf8)
                if !hasSeededDefaultLink && savedLinks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try defaultFirstRunLink.write(to: videoFileURL, atomically: true, encoding: .utf8)
                    defaults.set(true, forKey: defaultLinkSeededKey)
                    linksTextView.string = defaultFirstRunLink
                } else {
                    if !hasSeededDefaultLink {
                        defaults.set(true, forKey: defaultLinkSeededKey)
                    }
                    linksTextView.string = savedLinks
                }
            } else {
                try defaultFirstRunLink.write(to: videoFileURL, atomically: true, encoding: .utf8)
                defaults.set(true, forKey: defaultLinkSeededKey)
                linksTextView.string = defaultFirstRunLink
            }
            updatePlaceholderVisibility()
        } catch {
            updateStatus("Couldn't open links")
            appendLog("Open error: \(error.localizedDescription)")
        }
    }

    private func scheduleAutosave() {
        autosaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.persistLinks(showStatus: false)
        }

        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    @objc private func openFolder() {
        let folderURL = destinationDirectory(for: selectedFormat())

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folderURL)
        } catch {
            updateStatus("Couldn't open folder")
            appendLog("Open folder error: \(error.localizedDescription)")
        }
    }

    @objc private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = outputBaseDirectory()
        panel.message = "Choose where the YouTube Downloader folder should live. Audio and Video folders will be created inside it."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        defaults.set(youtubeDownloaderParentDirectory(from: url).path, forKey: "outputDirectoryPath")
        updateOutputFolderLabel()
        updateStatus("Output folder updated")
    }

    @objc private func selectMP3() {
        setSelectedFormat(.mp3)
        resolutionPopUp.isEnabled = false
    }

    @objc private func selectMP4() {
        setSelectedFormat(.mp4)
        resolutionPopUp.isEnabled = true
    }

    @objc private func cancelDownload() {
        guard let process = activeProcess else { return }

        cancelRequested = true
        updateStatus("Canceling...")
        appendLog("Cancel requested")
        process.terminate()
    }

    @objc private func downloadLinks() {
        guard activeProcess == nil else {
            updateStatus("Download in progress")
            return
        }

        persistLinks(showStatus: false)

        let urls = currentLinks()
        guard !urls.isEmpty else {
            updateStatus("Add a link first")
            return
        }

        logView.clear()
        let format = selectedFormat()
        guard requiredToolsAreAvailable() else {
            return
        }

        let outputDirectory = destinationDirectory(for: format)
        appendLog("Starting \(format.buttonTitle) download")
        appendLog("Saving to \(outputDirectory.path)")

        let process = Process()
        let outputPipe = Pipe()
        let outputHandle = outputPipe.fileHandleForReading
        let scriptURL = Bundle.main.url(forResource: "download", withExtension: "sh")
            ?? projectDirectory.appendingPathComponent("download.sh")
        process.currentDirectoryURL = supportDirectory
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        let resolution = format == .mp4 ? selectedResolution().rawValue : "best"
        process.arguments = [scriptURL.path, format.rawValue, resolution, outputDirectory.path]
        var environment = ProcessInfo.processInfo.environment
        environment["YOUTUBE_DOWNLOADER_OUTPUT_DIR"] = outputDirectory.path
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.appendLog(text)
                }
            }
        }

        process.terminationHandler = { [weak self] finishedProcess in
            DispatchQueue.main.async {
                outputHandle.readabilityHandler = nil

                let remainingData = outputHandle.readDataToEndOfFile()
                if !remainingData.isEmpty, let trailingText = String(data: remainingData, encoding: .utf8) {
                    self?.appendLog(trailingText)
                }

                self?.activeProcess = nil
                self?.setDownloading(false)

                if self?.cancelRequested == true {
                    self?.cancelRequested = false
                    self?.updateStatus("Canceled")
                    self?.appendLog("Canceled")
                } else if finishedProcess.terminationStatus == 0 {
                    self?.cleanDownloadedFilenames(in: outputDirectory)
                    self?.updateStatus("Done")
                    self?.appendLog("Finished")
                } else {
                    self?.updateStatus("Download failed")
                    self?.appendLog("Download failed")
                    self?.appendLog("Stopped with status \(finishedProcess.terminationStatus)")
                }
            }
        }

        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            cancelRequested = false
            try process.run()
            activeProcess = process
            setDownloading(true)
            updateStatus("Downloading...")
        } catch {
            outputHandle.readabilityHandler = nil
            activeProcess = nil
            cancelRequested = false
            setDownloading(false)
            updateStatus("Couldn't start download")
            appendLog("Start error: \(error.localizedDescription)")
        }
    }

    private func persistLinks(showStatus: Bool) {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try linksTextView.string.write(to: videoFileURL, atomically: true, encoding: .utf8)
            if showStatus {
                updateStatus("Saved")
            }
        } catch {
            updateStatus("Couldn't save")
            appendLog("Save error: \(error.localizedDescription)")
        }
    }

    private func currentLinks() -> [String] {
        linksTextView.string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private func outputBaseDirectory() -> URL {
        if let path = defaults.string(forKey: "outputDirectoryPath"), !path.isEmpty {
            let normalizedURL = youtubeDownloaderParentDirectory(from: URL(fileURLWithPath: path, isDirectory: true))
            if normalizedURL.path != path {
                defaults.set(normalizedURL.path, forKey: "outputDirectoryPath")
            }
            return normalizedURL
        }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Downloads", isDirectory: true)
        return youtubeDownloaderParentDirectory(from: downloads)
    }

    private func youtubeDownloaderParentDirectory(from url: URL) -> URL {
        if url.lastPathComponent == "YouTube Downloader" {
            return url
        }

        return url.appendingPathComponent("YouTube Downloader", isDirectory: true)
    }

    private func destinationDirectory(for format: OutputFormat) -> URL {
        outputBaseDirectory().appendingPathComponent(format == .mp3 ? "Audio" : "Video", isDirectory: true)
    }

    private func updateOutputFolderLabel() {
        outputFolderLabel.stringValue = outputBaseDirectory().path
    }

    private func cleanDownloadedFilenames(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for fileURL in files {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension
            let originalStem = fileURL.deletingPathExtension().lastPathComponent
            let cleanStem = cleanedFilenameStem(originalStem)

            guard !cleanStem.isEmpty, cleanStem != originalStem else { continue }

            var destinationURL = filenameURL(in: directory, stem: cleanStem, extension: ext)
            var suffix = 2
            while FileManager.default.fileExists(atPath: destinationURL.path), destinationURL.path != fileURL.path {
                destinationURL = filenameURL(in: directory, stem: "\(cleanStem) \(suffix)", extension: ext)
                suffix += 1
            }

            if destinationURL.path != fileURL.path {
                try? FileManager.default.moveItem(at: fileURL, to: destinationURL)
            }
        }
    }

    private func cleanedFilenameStem(_ stem: String) -> String {
        if stem.contains(specialVideoID) || specialVideoKnownTitles.contains(where: { stem.localizedCaseInsensitiveContains($0) }) {
            return specialVideoDisplayName
        }

        return stem
            .replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filenameURL(in directory: URL, stem: String, extension ext: String) -> URL {
        let baseURL = directory.appendingPathComponent(stem, isDirectory: false)
        return ext.isEmpty ? baseURL : baseURL.appendingPathExtension(ext)
    }

    private func requiredToolsAreAvailable() -> Bool {
        let missing = ["yt-dlp", "ffmpeg"].filter { findExecutable(named: $0) == nil }

        guard !missing.isEmpty else {
            return true
        }

        let toolList = missing.joined(separator: " and ")
        updateStatus("\(toolList) not found")
        appendLog("\(toolList) not found")
        showMissingToolsAlert(missingTools: missing)
        return false
    }

    private func findExecutable(named name: String) -> String? {
        var searchDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        searchDirectories.append(contentsOf: pathDirectories)

        for directory in searchDirectories {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func showMissingToolsAlert(missingTools: [String]) {
        let helperURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Install Required Tools.command")
        let helperExists = FileManager.default.isExecutableFile(atPath: helperURL.path)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(missingTools.joined(separator: " and ")) required"
        alert.informativeText = """
        YouTube Downloader stays lightweight by using yt-dlp and ffmpeg from your Mac instead of bundling them.

        Install the required tools, then reopen the app and try again.
        """
        alert.addButton(withTitle: helperExists ? "Open Install Helper" : "Open Homebrew")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            if helperExists {
                NSWorkspace.shared.open(helperURL)
            } else if let url = URL(string: "https://brew.sh") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func updatePlaceholderVisibility() {
        linksPlaceholderLabel.isHidden = !linksTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applySavedFormatSelection() {
        setSelectedFormat(savedFormat())
        setSelectedResolution(.best)
    }

    private func savedFormat() -> OutputFormat {
        guard let value = defaults.string(forKey: "outputFormat"), let format = OutputFormat(rawValue: value) else {
            return .mp3
        }
        return format
    }

    private func selectedFormat() -> OutputFormat {
        mp4Button.state == .on ? .mp4 : .mp3
    }

    private func setSelectedFormat(_ format: OutputFormat) {
        mp3Button.state = format == .mp3 ? .on : .off
        mp4Button.state = format == .mp4 ? .on : .off
        defaults.set(format.rawValue, forKey: "outputFormat")
    }

    private func setDownloading(_ isDownloading: Bool) {
        downloadButton.isEnabled = !isDownloading
        cancelButton.isEnabled = isDownloading
        mp3Button.isEnabled = !isDownloading
        mp4Button.isEnabled = !isDownloading
        chooseFolderButton.isEnabled = !isDownloading
        openFolderButton.isEnabled = !isDownloading
        resolutionPopUp.isEnabled = !isDownloading && selectedFormat() == .mp4
    }

    private func updateStatus(_ text: String) {
        guard text != "Ready" && text != "Saved" else { return }
        appendLog(text)
    }

    private func appendLog(_ text: String) {
        logView.append(maskedActivityText(text))
    }

    private func maskedActivityText(_ text: String) -> String {
        var masked = text
        for title in specialVideoKnownTitles {
            masked = masked.replacingOccurrences(of: title, with: specialVideoDisplayName, options: [.caseInsensitive])
        }

        let escapedID = NSRegularExpression.escapedPattern(for: specialVideoID)
        let pattern = #"([^/\\\n\r"]*?)\s*\[\#(escapedID)\]"#
        masked = masked.replacingOccurrences(
            of: pattern,
            with: "\(specialVideoDisplayName) [\(specialVideoID)]",
            options: .regularExpression
        )
        return masked
    }

    private static func makeSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL.appendingPathComponent("YouTube Downloader", isDirectory: true)
    }
}

private func projectDirectory() -> URL {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    }

    let bundleDirectory = Bundle.main.bundleURL
    if bundleDirectory.pathExtension == "app" {
        return bundleDirectory.deletingLastPathComponent()
    }

    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

@main
struct YouTubeDownloaderApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(projectDirectory: projectDirectory())
        app.delegate = delegate
        app.run()
    }
}
