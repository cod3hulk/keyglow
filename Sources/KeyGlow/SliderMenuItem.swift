import Cocoa

final class SliderMenuItem: NSView {
    private let slider: NSSlider
    private let valueLabel: NSTextField
    private let formatValue: (Double) -> String
    var onValueChanged: ((Int) -> Void)?

    init(label: String, minValue: Double, maxValue: Double, value: Double, formatValue: @escaping (Double) -> String) {
        self.formatValue = formatValue

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = .menuFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor

        slider = NSSlider(value: value, minValue: minValue, maxValue: maxValue,
                          target: nil, action: nil)
        slider.isContinuous = true

        valueLabel = NSTextField(labelWithString: formatValue(value))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 50))

        slider.target = self
        slider.action = #selector(sliderChanged)

        let sliderRow = NSStackView(views: [slider, valueLabel])
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 8

        let stack = NSStackView(views: [titleLabel, sliderRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            valueLabel.widthAnchor.constraint(equalToConstant: 52),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let value = sender.integerValue
        valueLabel.stringValue = formatValue(Double(value))
        onValueChanged?(value)
    }

    func setValue(_ value: Double) {
        slider.doubleValue = value
        valueLabel.stringValue = formatValue(value)
    }

    func setEnabled(_ enabled: Bool) {
        slider.isEnabled = enabled
    }
}
