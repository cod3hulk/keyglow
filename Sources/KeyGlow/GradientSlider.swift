import Cocoa

final class GradientSliderCell: NSSliderCell {
    var gradientColors: [NSColor] = [.systemGray, .white]

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let trackRect = NSRect(x: rect.origin.x, y: rect.midY - 3,
                               width: rect.width, height: 6)
        let path = NSBezierPath(roundedRect: trackRect, xRadius: 3, yRadius: 3)
        path.addClip()

        let gradient = NSGradient(colors: gradientColors)
        gradient?.draw(in: trackRect, angle: 0)
    }

    override func knobRect(flipped: Bool) -> NSRect {
        var rect = super.knobRect(flipped: flipped)
        rect = NSRect(x: rect.midX - 7, y: rect.midY - 7, width: 14, height: 14)
        return rect
    }

    override func drawKnob(_ knobRect: NSRect) {
        let path = NSBezierPath(ovalIn: knobRect.insetBy(dx: 0.5, dy: 0.5))

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

final class GradientSlider: NSSlider {
    var gradientColors: [NSColor] = [.systemGray, .white] {
        didSet { (cell as? GradientSliderCell)?.gradientColors = gradientColors }
    }

    override class var cellClass: AnyClass? {
        get { GradientSliderCell.self }
        set {}
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        (cell as? GradientSliderCell)?.gradientColors = gradientColors
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
