import Foundation

struct LightState {
    var on: Bool
    var brightness: Int
    var temperature: Int
}

enum KeyLightService {
    static let port = 9123
    private static let hostnames = ["elgato-key-light", "elgato-key-light.local"]

    static func discover() -> String? {
        for hostname in hostnames {
            let host = CFHostCreateWithName(nil, hostname as CFString).takeRetainedValue()
            var resolved = DarwinBoolean(false)
            CFHostStartInfoResolution(host, .addresses, nil)
            guard let addresses = CFHostGetAddressing(host, &resolved)?.takeUnretainedValue() as? [Data],
                  resolved.boolValue else { continue }

            for addrData in addresses {
                var storage = sockaddr_storage()
                (addrData as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)

                if storage.ss_family == UInt8(AF_INET) {
                    let addr = withUnsafePointer(to: &storage) {
                        $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    }
                    let ip = String(cString: inet_ntoa(addr.sin_addr))
                    print("[KeyGlow] Resolved \(hostname) -> \(ip)")
                    return ip
                }
            }
        }
        print("[KeyGlow] Key Light not found - use Rediscover to retry")
        return nil
    }

    static func fetchState(ip: String) -> LightState? {
        guard let url = URL(string: "http://\(ip):\(port)/elgato/lights") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"

        var result: LightState?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lights = json["lights"] as? [[String: Any]],
                  let light = lights.first else { return }
            result = LightState(
                on: (light["on"] as? Int) == 1,
                brightness: light["brightness"] as? Int ?? 50,
                temperature: light["temperature"] as? Int ?? 200
            )
        }.resume()
        semaphore.wait()
        return result
    }

    static func setLight(ip: String, on: Bool? = nil, brightness: Int? = nil, temperature: Int? = nil) {
        guard let url = URL(string: "http://\(ip):\(port)/elgato/lights") else { return }

        var lightDict: [String: Any] = [:]
        if let on { lightDict["on"] = on ? 1 : 0 }
        if let brightness { lightDict["brightness"] = max(3, min(100, brightness)) }
        if let temperature { lightDict["temperature"] = max(143, min(344, temperature)) }

        let body: [String: Any] = ["numberOfLights": 1, "lights": [lightDict]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    static func temperatureToKelvin(_ apiValue: Int) -> Int {
        guard apiValue > 0 else { return 4000 }
        return 1_000_000 / apiValue
    }

    static func kelvinToTemperature(_ kelvin: Int) -> Int {
        guard kelvin > 0 else { return 200 }
        return max(143, min(344, 1_000_000 / kelvin))
    }
}
