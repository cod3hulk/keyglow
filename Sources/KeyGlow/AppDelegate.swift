import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var cameraMonitor: CameraMonitor?

    private var keyLightIP: String?
    private var lightOn = false
    private var brightness = 50
    private var temperature = 200
    private var autoMode = true
    private var cameraActive = false

    private var brightnessSlider: SliderMenuItem?
    private var temperatureSlider: SliderMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let iconURL = Bundle.module.url(forResource: "menubar-icon", withExtension: "svg"),
               let image = NSImage(contentsOf: iconURL) {
                image.size = NSSize(width: 20, height: 20)
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "KG"
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let ip = KeyLightService.discover()
            var state: LightState?
            if let ip { state = KeyLightService.fetchState(ip: ip) }

            DispatchQueue.main.async { [self] in
                keyLightIP = ip
                if let state {
                    lightOn = state.on
                    brightness = state.brightness
                    temperature = state.temperature
                }
                rebuildMenu()
                startCameraMonitor()
            }
        }

        rebuildMenu()
    }

    private func startCameraMonitor() {
        cameraMonitor = CameraMonitor { [weak self] cameraOn in
            guard let self else { return }
            cameraActive = cameraOn

            if autoMode, let ip = keyLightIP, cameraOn != lightOn {
                lightOn = cameraOn
                KeyLightService.setLight(ip: ip, on: cameraOn)
            }
            rebuildMenu()
        }
        cameraMonitor?.start()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let connectionLabel = keyLightIP.map { "Key Light: \($0)" } ?? "Key Light: Not Found"
        let connectionItem = NSMenuItem(title: connectionLabel, action: nil, keyEquivalent: "")
        connectionItem.isEnabled = false
        menu.addItem(connectionItem)

        let camLabel = cameraActive ? "Camera: Active" : "Camera: Inactive"
        let camItem = NSMenuItem(title: camLabel, action: nil, keyEquivalent: "")
        camItem.isEnabled = false
        menu.addItem(camItem)

        let lightLabel = lightOn ? "Light: ON" : "Light: OFF"
        let lightItem = NSMenuItem(title: lightLabel, action: nil, keyEquivalent: "")
        lightItem.isEnabled = false
        menu.addItem(lightItem)

        menu.addItem(.separator())

        let autoLabel = autoMode ? "Auto Mode: ON" : "Auto Mode: OFF"
        let autoItem = NSMenuItem(title: autoLabel, action: #selector(toggleAutoMode), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = autoMode ? .on : .off
        menu.addItem(autoItem)

        let toggleLabel = lightOn ? "Turn Light Off" : "Turn Light On"
        let toggleItem = NSMenuItem(title: toggleLabel, action: #selector(toggleLight), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = keyLightIP != nil
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let brightnessView = SliderMenuItem(
            label: "Brightness",
            minValue: 3, maxValue: 100,
            value: Double(brightness),
            unit: "%",
            gradientColors: [
                NSColor(calibratedWhite: 0.25, alpha: 1),
                NSColor(calibratedWhite: 1.0, alpha: 1),
            ],
            leadingIcon: "sun.min",
            trailingIcon: "sun.max"
        )
        brightnessView.onValueChanged = { [weak self] value in
            guard let self, let ip = keyLightIP else { return }
            brightness = value
            KeyLightService.setLight(ip: ip, brightness: value)
        }
        brightnessView.setEnabled(keyLightIP != nil)
        self.brightnessSlider = brightnessView
        let brightnessItem = NSMenuItem()
        brightnessItem.view = brightnessView
        menu.addItem(brightnessItem)

        let kelvin = KeyLightService.temperatureToKelvin(temperature)
        let temperatureView = SliderMenuItem(
            label: "Color Temperature",
            minValue: 2900, maxValue: 7000,
            value: Double(kelvin),
            unit: "K",
            gradientColors: [
                NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.25, alpha: 1),
                NSColor(calibratedRed: 0.55, green: 0.75, blue: 1.0, alpha: 1),
            ],
            leadingIcon: "flame",
            trailingIcon: "snowflake"
        )
        temperatureView.onValueChanged = { [weak self] kelvinValue in
            guard let self, let ip = keyLightIP else { return }
            temperature = KeyLightService.kelvinToTemperature(kelvinValue)
            KeyLightService.setLight(ip: ip, temperature: temperature)
        }
        temperatureView.setEnabled(keyLightIP != nil)
        self.temperatureSlider = temperatureView
        let temperatureItem = NSMenuItem()
        temperatureItem.view = temperatureView
        menu.addItem(temperatureItem)

        menu.addItem(.separator())

        let rediscoverItem = NSMenuItem(title: "Rediscover Key Light", action: #selector(rediscover), keyEquivalent: "")
        rediscoverItem.target = self
        menu.addItem(rediscoverItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleAutoMode() {
        autoMode.toggle()
        rebuildMenu()
    }

    @objc private func toggleLight() {
        guard let ip = keyLightIP else { return }
        lightOn.toggle()
        KeyLightService.setLight(ip: ip, on: lightOn)
        rebuildMenu()
    }

    @objc private func rediscover() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let ip = KeyLightService.discover()
            var state: LightState?
            if let ip { state = KeyLightService.fetchState(ip: ip) }

            DispatchQueue.main.async { [self] in
                keyLightIP = ip
                if let state {
                    lightOn = state.on
                    brightness = state.brightness
                    temperature = state.temperature
                }
                rebuildMenu()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cameraMonitor?.stop()
    }
}
