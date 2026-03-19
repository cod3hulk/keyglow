import Cocoa

final class SliderMenuItem: NSView, NSTextFieldDelegate {
    private let slider: GradientSlider
    private let valueField: NSTextField
    private let unit: String
    private let minValue: Double
    private let maxValue: Double
    var onValueChanged: ((Int) -> Void)?

    init(
        label: String,
        minValue: Double,
        maxValue: Double,
        value: Double,
        unit: String,
        gradientColors: [NSColor],
        leadingIcon: String,
        trailingIcon: String
    ) {
        self.unit = unit
        self.minValue = minValue
        self.maxValue = maxValue

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = .menuFont(ofSize: 11)
        titleLabel.textColor = .tertiaryLabelColor

        slider = GradientSlider(frame: .zero)
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.doubleValue = value
        slider.isContinuous = true
        slider.gradientColors = gradientColors

        valueField = NSTextField(string: "\(Int(value))\(unit)")
        valueField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueField.textColor = .labelColor
        valueField.backgroundColor = .quaternaryLabelColor
        valueField.isBordered = false
        valueField.isBezeled = true
        valueField.bezelStyle = .roundedBezel
        valueField.isEditable = true
        valueField.isSelectable = true
        valueField.alignment = .center
        valueField.focusRingType = .none
        valueField.setContentHuggingPriority(.required, for: .horizontal)
        valueField.setContentCompressionResistancePriority(.required, for: .horizontal)

        let leadingImage = NSImageView()
        let trailingImage = NSImageView()
        if let img = NSImage(systemSymbolName: leadingIcon, accessibilityDescription: nil) {
            leadingImage.image = img
            leadingImage.contentTintColor = .secondaryLabelColor
        }
        if let img = NSImage(systemSymbolName: trailingIcon, accessibilityDescription: nil) {
            trailingImage.image = img
            trailingImage.contentTintColor = .secondaryLabelColor
        }
        leadingImage.setContentHuggingPriority(.required, for: .horizontal)
        trailingImage.setContentHuggingPriority(.required, for: .horizontal)

        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 54))

        slider.target = self
        slider.action = #selector(sliderChanged)
        valueField.delegate = self

        let titleRow = NSStackView(views: [titleLabel, valueField])
        titleRow.orientation = .horizontal
        titleRow.distribution = .fill

        let sliderRow = NSStackView(views: [leadingImage, slider, trailingImage])
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 6

        let stack = NSStackView(views: [titleRow, sliderRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            valueField.widthAnchor.constraint(equalToConstant: 56),
            leadingImage.widthAnchor.constraint(equalToConstant: 16),
            trailingImage.widthAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let value = sender.integerValue
        valueField.stringValue = "\(value)\(unit)"
        onValueChanged?(value)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        applyTextInput()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            applyTextInput()
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    private func applyTextInput() {
        let text = valueField.stringValue
            .replacingOccurrences(of: unit, with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let parsed = Double(text) else {
            valueField.stringValue = "\(slider.integerValue)\(unit)"
            return
        }
        let clamped = max(minValue, min(maxValue, parsed))
        let intValue = Int(clamped)
        slider.integerValue = intValue
        valueField.stringValue = "\(intValue)\(unit)"
        onValueChanged?(intValue)
    }

    func setValue(_ value: Double) {
        slider.doubleValue = value
        valueField.stringValue = "\(Int(value))\(unit)"
    }

    func setEnabled(_ enabled: Bool) {
        slider.isEnabled = enabled
        valueField.isEditable = enabled
    }
}
