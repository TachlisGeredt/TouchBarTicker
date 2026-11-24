import AppKit

final class TouchBarPillButton: NSButton {
    var feedID: String = ""
    var isSelectedPill: Bool = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        setButtonType(.momentaryChange)
        updateAppearance()
    }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 18, height: 28)
    }

    private func updateAppearance() {
        let bgColor: NSColor
        if isSelectedPill {
            bgColor = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)
        } else {
            bgColor = NSColor(white: 0.22, alpha: 1.0)
        }
        layer?.backgroundColor = bgColor.cgColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isSelectedPill ? .bold : .medium),
                .foregroundColor: NSColor.white
            ]
        )
    }
}

final class SettingsTouchBarView: NSView {
    var onCancel: (() -> Void)?
    var onSave: ((String, Double) -> Void)?
    var onSpeedChangedForPreview: ((Double) -> Void)?

    private let closeButton = NSButton()
    private let speedSlider = NSSlider()
    private let feedScrollView = NSScrollView()
    private let feedStackView = NSStackView()
    private let saveButton = NSButton()

    private var feedButtons: [TouchBarPillButton] = []
    private var selectedFeedID: String = TickerPreferences.shared.selectedFeedID
    private var currentSpeed: Double = TickerPreferences.shared.scrollSpeed

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    func configure(feedID: String, speed: Double) {
        selectedFeedID = feedID
        currentSpeed = speed
        speedSlider.doubleValue = speed
        updateFeedSelectionUI()
        scrollToSelectedFeed()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // 1. Far-left Cancel (✕) button
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 6
        closeButton.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1.0).cgColor
        if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close without saving") {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            closeButton.image = img.withSymbolConfiguration(config)
            closeButton.contentTintColor = .white
        } else {
            closeButton.title = "✕"
        }
        closeButton.target = self
        closeButton.action = #selector(handleCancel)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        // 2. Left-side Speed Slider with tortoise/hare icons
        let slowIcon = makeSymbolView("tortoise.fill")
        let fastIcon = makeSymbolView("hare.fill")

        speedSlider.minValue = TickerPreferences.minSpeed
        speedSlider.maxValue = TickerPreferences.maxSpeed
        speedSlider.doubleValue = currentSpeed
        speedSlider.isContinuous = false // Fires when user releases finger -> triggers 2s preview
        speedSlider.target = self
        speedSlider.action = #selector(handleSpeedSliderReleased)
        speedSlider.translatesAutoresizingMaskIntoConstraints = false

        let sliderContainer = NSStackView(views: [slowIcon, speedSlider, fastIcon])
        sliderContainer.orientation = .horizontal
        sliderContainer.alignment = .centerY
        sliderContainer.spacing = 6
        sliderContainer.translatesAutoresizingMaskIntoConstraints = false

        // 3. Middle horizontally scrollable Feed Picker
        feedStackView.orientation = .horizontal
        feedStackView.alignment = .centerY
        feedStackView.spacing = 6
        feedStackView.edgeInsets = NSEdgeInsets(top: 1, left: 2, bottom: 1, right: 2)
        feedStackView.translatesAutoresizingMaskIntoConstraints = false

        for feed in FeedCatalog.all {
            let btn = TouchBarPillButton(frame: .zero)
            btn.title = feed.name
            btn.feedID = feed.id
            btn.target = self
            btn.action = #selector(handleFeedTapped(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
            feedButtons.append(btn)
            feedStackView.addArrangedSubview(btn)
        }

        let documentContainer = NSView()
        documentContainer.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(feedStackView)
        NSLayoutConstraint.activate([
            feedStackView.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
            feedStackView.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),
            feedStackView.topAnchor.constraint(equalTo: documentContainer.topAnchor),
            feedStackView.bottomAnchor.constraint(equalTo: documentContainer.bottomAnchor),
            documentContainer.heightAnchor.constraint(equalToConstant: 30)
        ])

        feedScrollView.documentView = documentContainer
        feedScrollView.hasHorizontalScroller = false
        feedScrollView.hasVerticalScroller = false
        feedScrollView.drawsBackground = false
        feedScrollView.horizontalScrollElasticity = .allowed
        feedScrollView.verticalScrollElasticity = .none
        feedScrollView.translatesAutoresizingMaskIntoConstraints = false

        // 4. Far-right Save button
        saveButton.isBordered = false
        saveButton.wantsLayer = true
        saveButton.layer?.cornerRadius = 6
        saveButton.layer?.backgroundColor = NSColor(srgbRed: 0.19, green: 0.72, blue: 0.34, alpha: 1.0).cgColor
        saveButton.attributedTitle = NSAttributedString(
            string: "Save",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor.white
            ]
        )
        saveButton.target = self
        saveButton.action = #selector(handleSave)
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(closeButton)
        addSubview(sliderContainer)
        addSubview(feedScrollView)
        addSubview(saveButton)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 38),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            sliderContainer.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 10),
            sliderContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            sliderContainer.widthAnchor.constraint(equalToConstant: 155),
            sliderContainer.heightAnchor.constraint(equalToConstant: 30),

            feedScrollView.leadingAnchor.constraint(equalTo: sliderContainer.trailingAnchor, constant: 12),
            feedScrollView.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -10),
            feedScrollView.topAnchor.constraint(equalTo: topAnchor),
            feedScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            saveButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            saveButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 58),
            saveButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        updateFeedSelectionUI()
    }

    private func makeSymbolView(_ name: String) -> NSImageView {
        let iv = NSImageView()
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            iv.image = img.withSymbolConfiguration(config)
            iv.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        }
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return iv
    }

    private func updateFeedSelectionUI() {
        for btn in feedButtons {
            btn.isSelectedPill = (btn.feedID == selectedFeedID)
        }
    }

    private func scrollToSelectedFeed() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let selectedBtn = self.feedButtons.first(where: { $0.feedID == self.selectedFeedID }) else {
                return
            }
            self.feedScrollView.documentView?.layoutSubtreeIfNeeded()
            selectedBtn.scrollToVisible(selectedBtn.bounds.insetBy(dx: -12, dy: 0))
        }
    }

    @objc private func handleCancel() {
        onCancel?()
    }

    @objc private func handleSave() {
        currentSpeed = speedSlider.doubleValue
        onSave?(selectedFeedID, currentSpeed)
    }

    @objc private func handleSpeedSliderReleased() {
        currentSpeed = speedSlider.doubleValue
        onSpeedChangedForPreview?(currentSpeed)
    }

    @objc private func handleFeedTapped(_ sender: TouchBarPillButton) {
        selectedFeedID = sender.feedID
        updateFeedSelectionUI()
    }
}
