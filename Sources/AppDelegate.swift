import AppKit

private extension NSTouchBarItem.Identifier {
    static let rootContainer = NSTouchBarItem.Identifier("com.touchbarticker.root")
    static let trayIdentifier = NSTouchBarItem.Identifier("com.touchbarticker.tray")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    private let quoteService = QuoteService()
    private let prefs = TickerPreferences.shared

    private var modalTouchBar: NSTouchBar?
    private var rootView: NSView?

    private var tickerContainer: NSView!
    private var quitButton: NSButton!
    private var tickerView: TickerTouchBarView!
    private var settingsButton: NSButton!
    private var previewBadge: NSTextField!

    private var settingsView: SettingsTouchBarView!

    private var refreshTimer: Timer?
    private var previewTimer: Timer?
    private var currentQuotes: [StockQuote] = []
    private var activeFetchID: UUID = UUID()

    private enum Mode {
        case ticker
        case settings
        case speedPreview
    }
    private var mode: Mode = .ticker

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupTouchBar()
        presentTouchBar()
        startRefreshing()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentTouchBar()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        previewTimer?.invalidate()
        if let bar = modalTouchBar {
            NSTouchBar.dismissSystemModalTouchBar(bar)
        }
    }

    // MARK: - Touch Bar Setup

    private func setupTouchBar() {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [.rootContainer]
        self.modalTouchBar = bar
    }

    private func presentTouchBar() {
        guard let bar = modalTouchBar else { return }
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        let placementSel = #selector(NSTouchBar.presentSystemModalTouchBar(_:placement:systemTrayItemIdentifier:))
        if NSTouchBar.responds(to: placementSel) {
            NSTouchBar.presentSystemModalTouchBar(bar, placement: 1, systemTrayItemIdentifier: .trayIdentifier)
        } else {
            NSTouchBar.presentSystemModalTouchBar(bar, systemTrayItemIdentifier: .trayIdentifier)
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == .rootContainer else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = buildRootView()
        return item
    }

    private func buildRootView() -> NSView {
        if let existing = rootView {
            return existing
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1085, height: 30))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        container.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        // Stretch across the entire available Touch Bar width: priority 999 beats NSTouchBar's
        // internal fitting priority (~500-750) while yielding to the required (1000) max-width constraint.
        let expandWidth = container.widthAnchor.constraint(equalToConstant: 1085)
        expandWidth.priority = NSLayoutConstraint.Priority(999)
        expandWidth.isActive = true
        container.heightAnchor.constraint(equalToConstant: 30).isActive = true

        // --- Ticker Mode Container ---
        tickerContainer = NSView()
        tickerContainer.translatesAutoresizingMaskIntoConstraints = false

        quitButton = makeIconButton(symbolName: "xmark", fallback: "✕", action: #selector(handleQuit))
        settingsButton = makeIconButton(symbolName: "gearshape.fill", fallback: "⚙", action: #selector(handleOpenSettings))

        tickerView = TickerTouchBarView(frame: .zero)
        tickerView.translatesAutoresizingMaskIntoConstraints = false
        tickerView.showStatus("Loading \(prefs.selectedFeed.name)…")

        previewBadge = NSTextField(labelWithString: "Preview")
        previewBadge.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        previewBadge.textColor = NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1.0)
        previewBadge.alignment = .center
        previewBadge.wantsLayer = true
        previewBadge.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1.0).cgColor
        previewBadge.layer?.cornerRadius = 6
        previewBadge.translatesAutoresizingMaskIntoConstraints = false
        previewBadge.isHidden = true

        tickerContainer.addSubview(quitButton)
        tickerContainer.addSubview(tickerView)
        tickerContainer.addSubview(settingsButton)
        tickerContainer.addSubview(previewBadge)

        NSLayoutConstraint.activate([
            quitButton.leadingAnchor.constraint(equalTo: tickerContainer.leadingAnchor),
            quitButton.centerYAnchor.constraint(equalTo: tickerContainer.centerYAnchor),
            quitButton.widthAnchor.constraint(equalToConstant: 38),
            quitButton.heightAnchor.constraint(equalToConstant: 28),

            settingsButton.trailingAnchor.constraint(equalTo: tickerContainer.trailingAnchor),
            settingsButton.centerYAnchor.constraint(equalTo: tickerContainer.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 38),
            settingsButton.heightAnchor.constraint(equalToConstant: 28),

            previewBadge.trailingAnchor.constraint(equalTo: tickerContainer.trailingAnchor),
            previewBadge.centerYAnchor.constraint(equalTo: tickerContainer.centerYAnchor),
            previewBadge.widthAnchor.constraint(equalToConstant: 64),
            previewBadge.heightAnchor.constraint(equalToConstant: 24),

            tickerView.leadingAnchor.constraint(equalTo: quitButton.trailingAnchor, constant: 8),
            tickerView.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -8),
            tickerView.topAnchor.constraint(equalTo: tickerContainer.topAnchor),
            tickerView.bottomAnchor.constraint(equalTo: tickerContainer.bottomAnchor)
        ])

        // --- Settings Mode Container ---
        settingsView = SettingsTouchBarView(frame: .zero)
        settingsView.translatesAutoresizingMaskIntoConstraints = false
        settingsView.isHidden = true

        settingsView.onCancel = { [weak self] in
            self?.cancelSettings()
        }
        settingsView.onSave = { [weak self] feedID, speed in
            self?.saveSettings(feedID: feedID, speed: speed)
        }
        settingsView.onPreview = { [weak self] previewSpeed in
            self?.startSpeedPreview(speed: previewSpeed)
        }

        container.addSubview(tickerContainer)
        container.addSubview(settingsView)

        NSLayoutConstraint.activate([
            tickerContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tickerContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tickerContainer.topAnchor.constraint(equalTo: container.topAnchor),
            tickerContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            settingsView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            settingsView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            settingsView.topAnchor.constraint(equalTo: container.topAnchor),
            settingsView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        self.rootView = container
        return container
    }

    private func makeIconButton(symbolName: String, fallback: String, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1.0).cgColor
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: fallback) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            btn.image = img.withSymbolConfiguration(config)
            btn.contentTintColor = .white
        } else {
            btn.title = fallback
        }
        btn.target = self
        btn.action = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    // MARK: - Mode Switching

    private func setMode(_ newMode: Mode) {
        mode = newMode
        switch newMode {
        case .ticker:
            previewTimer?.invalidate()
            previewTimer = nil
            settingsView.isHidden = true
            tickerContainer.isHidden = false
            quitButton.isHidden = false
            settingsButton.isHidden = false
            previewBadge.isHidden = true
            tickerView.setAllowTapToPause(true)
            tickerView.updateSpeed(prefs.scrollSpeed)

        case .settings:
            previewTimer?.invalidate()
            previewTimer = nil
            tickerContainer.isHidden = true
            settingsView.isHidden = false

        case .speedPreview:
            settingsView.isHidden = true
            tickerContainer.isHidden = false
            quitButton.isHidden = true
            settingsButton.isHidden = true
            previewBadge.isHidden = false
            tickerView.setAllowTapToPause(false)
        }
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    @objc private func handleOpenSettings() {
        settingsView.configure(feedID: prefs.selectedFeedID, speed: prefs.scrollSpeed)
        setMode(.settings)
    }

    private func cancelSettings() {
        setMode(.ticker)
    }

    private func saveSettings(feedID: String, speed: Double) {
        let feedChanged = (feedID != prefs.selectedFeedID)
        prefs.selectedFeedID = feedID
        prefs.scrollSpeed = speed

        setMode(.ticker)

        if feedChanged {
            currentQuotes = []
            tickerView.showStatus("Loading \(prefs.selectedFeed.name)…")
            fetchQuotesNow()
        } else {
            tickerView.updateSpeed(speed)
        }
    }

    private func startSpeedPreview(speed: Double) {
        previewTimer?.invalidate()
        setMode(.speedPreview)

        if currentQuotes.isEmpty {
            tickerView.showStatus("Previewing speed…")
        } else {
            tickerView.update(quotes: currentQuotes, speed: speed)
        }

        previewTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self = self, self.mode == .speedPreview else { return }
            self.setMode(.settings)
        }
    }

    // MARK: - Live Quote Refreshing

    private func startRefreshing() {
        fetchQuotesNow()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.fetchQuotesNow()
        }
    }

    private func fetchQuotesNow() {
        let feed = prefs.selectedFeed
        let fetchID = UUID()
        activeFetchID = fetchID

        quoteService.fetchQuotes(for: feed.symbols) { [weak self] quotes in
            guard let self = self, self.activeFetchID == fetchID else { return }
            if !quotes.isEmpty {
                self.currentQuotes = quotes
                if self.mode == .ticker {
                    self.tickerView.update(quotes: quotes, speed: self.prefs.scrollSpeed)
                }
            } else if self.currentQuotes.isEmpty {
                self.tickerView.showStatus("Unable to reach market data — retrying…")
            }
        }
    }
}
