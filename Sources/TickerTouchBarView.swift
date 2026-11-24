import AppKit
import QuartzCore

final class TickerTouchBarView: NSView {
    private let containerLayer = CALayer()
    private let statusLabel = NSTextField(labelWithString: "")

    private var quotes: [StockQuote] = []
    private var stripWidth: CGFloat = 0
    private var pointsPerSecond: Double = TickerPreferences.defaultSpeed
    private var isPaused: Bool = false
    private var allowTapToPause: Bool = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        layer?.cornerRadius = 6

        containerLayer.anchorPoint = CGPoint(x: 0, y: 0)
        containerLayer.position = CGPoint(x: 0, y: 0)
        layer?.addSublayer(containerLayer)

        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = NSColor(white: 0.72, alpha: 1.0)
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])

        allowedTouchTypes = [.direct]
    }

    override func layout() {
        super.layout()
        if !quotes.isEmpty {
            rebuildMarquee(preserveProgress: true)
        }
    }

    func setAllowTapToPause(_ allow: Bool) {
        allowTapToPause = allow
    }

    func showStatus(_ message: String) {
        quotes = []
        stripWidth = 0
        containerLayer.removeAllAnimations()
        containerLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        isPaused = false
        containerLayer.speed = 1.0
        containerLayer.timeOffset = 0
        containerLayer.beginTime = 0
        statusLabel.stringValue = message
        statusLabel.isHidden = false
    }

    func update(quotes: [StockQuote], speed: Double) {
        self.quotes = quotes
        self.pointsPerSecond = max(speed, TickerPreferences.minSpeed)
        if quotes.isEmpty {
            showStatus("Unable to load quotes — retrying…")
            return
        }
        statusLabel.isHidden = true
        rebuildMarquee(preserveProgress: true)
    }

    func updateSpeed(_ speed: Double) {
        let clamped = min(max(speed, TickerPreferences.minSpeed), TickerPreferences.maxSpeed)
        pointsPerSecond = clamped
        guard !quotes.isEmpty else { return }
        if isPaused {
            resumeScrolling()
        }
        rebuildMarquee(preserveProgress: true)
    }

    // MARK: - Touch Handling (Tap to Pause/Resume)

    override func touchesEnded(with event: NSEvent) {
        super.touchesEnded(with: event)
        guard allowTapToPause, !quotes.isEmpty else { return }
        if isPaused {
            resumeScrolling()
        } else {
            pauseScrolling()
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard allowTapToPause, !quotes.isEmpty else { return }
        if isPaused {
            resumeScrolling()
        } else {
            pauseScrolling()
        }
    }

    private func pauseScrolling() {
        guard !isPaused else { return }
        let pausedTime = containerLayer.convertTime(CACurrentMediaTime(), from: nil)
        containerLayer.speed = 0.0
        containerLayer.timeOffset = pausedTime
        isPaused = true
    }

    private func resumeScrolling() {
        guard isPaused else { return }
        let pausedTime = containerLayer.timeOffset
        containerLayer.speed = 1.0
        containerLayer.timeOffset = 0.0
        containerLayer.beginTime = 0.0
        let timeSincePause = containerLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        containerLayer.beginTime = timeSincePause
        isPaused = false
    }

    // MARK: - Marquee Rendering

    private func rebuildMarquee(preserveProgress: Bool) {
        var currentOffsetFraction: CGFloat = 0
        if preserveProgress, stripWidth > 0, let presentation = containerLayer.presentation() {
            let currentTx = abs(presentation.transform.m41)
            currentOffsetFraction = (currentTx.truncatingRemainder(dividingBy: stripWidth)) / stripWidth
        }

        let attributed = buildAttributedStrip(for: quotes)
        let measured = attributed.size()
        let newStripWidth = ceil(measured.width)
        guard newStripWidth > 1 else { return }

        let viewHeight: CGFloat = bounds.height > 0 ? bounds.height : 30.0
        guard let cgImage = renderAttributedString(attributed, width: newStripWidth, height: viewHeight) else {
            return
        }

        stripWidth = newStripWidth

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        containerLayer.removeAllAnimations()
        containerLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let visibleWidth = max(bounds.width, 1085.0)
        let tileCount = max(2, Int(ceil((visibleWidth + stripWidth) / stripWidth)) + 1)

        for i in 0..<tileCount {
            let tile = CALayer()
            tile.contents = cgImage
            tile.contentsScale = 2.0
            tile.frame = CGRect(x: CGFloat(i) * stripWidth, y: 0, width: stripWidth, height: viewHeight)
            containerLayer.addSublayer(tile)
        }

        containerLayer.frame = CGRect(x: 0, y: 0, width: CGFloat(tileCount) * stripWidth, height: viewHeight)
        containerLayer.transform = CATransform3DIdentity

        let duration = Double(stripWidth) / pointsPerSecond
        let anim = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue = 0
        anim.toValue = -stripWidth
        anim.duration = duration
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        anim.timingFunction = CAMediaTimingFunction(name: .linear)

        if preserveProgress && currentOffsetFraction > 0 && currentOffsetFraction < 1 {
            anim.timeOffset = Double(currentOffsetFraction) * duration
        }

        containerLayer.add(anim, forKey: "marqueeScroll")

        if isPaused {
            let pausedTime = containerLayer.convertTime(CACurrentMediaTime(), from: nil)
            containerLayer.speed = 0.0
            containerLayer.timeOffset = pausedTime
        } else {
            containerLayer.speed = 1.0
            containerLayer.timeOffset = 0.0
            containerLayer.beginTime = 0.0
        }

        CATransaction.commit()
    }

    private func buildAttributedStrip(for quotes: [StockQuote]) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let symbolFont = NSFont.systemFont(ofSize: 13.5, weight: .bold)
        let priceFont = NSFont.monospacedDigitSystemFont(ofSize: 13.5, weight: .medium)
        let changeFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        let sepFont = NSFont.systemFont(ofSize: 12, weight: .regular)

        let white = NSColor.white
        let lightGray = NSColor(white: 0.88, alpha: 1.0)
        let green = NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1.0)
        let red = NSColor(srgbRed: 1.0, green: 0.27, blue: 0.23, alpha: 1.0)
        let neutral = NSColor(white: 0.60, alpha: 1.0)
        let sepColor = NSColor(white: 0.36, alpha: 1.0)

        for quote in quotes {
            result.append(NSAttributedString(string: quote.displaySymbol + " ", attributes: [
                .font: symbolFont,
                .foregroundColor: white
            ]))

            result.append(NSAttributedString(string: quote.formattedPrice + " ", attributes: [
                .font: priceFont,
                .foregroundColor: lightGray
            ]))

            let arrow: String
            let changeColor: NSColor
            if quote.changePercent > 0.004 {
                arrow = "▲ "
                changeColor = green
            } else if quote.changePercent < -0.004 {
                arrow = "▼ "
                changeColor = red
            } else {
                arrow = "• "
                changeColor = neutral
            }

            result.append(NSAttributedString(string: arrow + quote.formattedChange, attributes: [
                .font: changeFont,
                .foregroundColor: changeColor
            ]))

            result.append(NSAttributedString(string: "   •   ", attributes: [
                .font: sepFont,
                .foregroundColor: sepColor
            ]))
        }

        return result
    }

    private func renderAttributedString(_ attrString: NSAttributedString, width: CGFloat, height: CGFloat) -> CGImage? {
        let scale: CGFloat = 2.0
        let pixelWidth = Int(ceil(width * scale))
        let pixelHeight = Int(ceil(height * scale))
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.scaleBy(x: scale, y: scale)
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let graphicsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        let textSize = attrString.size()
        let yOffset = floor((height - textSize.height) / 2.0)
        attrString.draw(at: NSPoint(x: 0, y: yOffset))

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
