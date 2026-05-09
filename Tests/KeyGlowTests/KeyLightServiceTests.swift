import XCTest
@testable import KeyGlow

final class KeyLightServiceTests: XCTestCase {

    // MARK: - temperatureToKelvin / kelvinToTemperature

    func testTemperatureToKelvinKnownValues() {
        XCTAssertEqual(KeyLightService.temperatureToKelvin(200), 5000)
        XCTAssertEqual(KeyLightService.temperatureToKelvin(143), 6993)
        XCTAssertEqual(KeyLightService.temperatureToKelvin(344), 2906)
    }

    func testTemperatureToKelvinGuardsZero() {
        XCTAssertEqual(KeyLightService.temperatureToKelvin(0), 4000)
        XCTAssertEqual(KeyLightService.temperatureToKelvin(-5), 4000)
    }

    func testKelvinToTemperatureKnownValues() {
        XCTAssertEqual(KeyLightService.kelvinToTemperature(5000), 200)
    }

    func testKelvinToTemperatureClamps() {
        XCTAssertEqual(KeyLightService.kelvinToTemperature(2900), 344)  // would compute 344 but well above max
        XCTAssertEqual(KeyLightService.kelvinToTemperature(2000), 344)  // would compute 500, clamps down
        XCTAssertEqual(KeyLightService.kelvinToTemperature(7000), 143)  // would compute 142, clamps up
        XCTAssertEqual(KeyLightService.kelvinToTemperature(10000), 143) // would compute 100, clamps up
    }

    func testKelvinToTemperatureGuardsZero() {
        XCTAssertEqual(KeyLightService.kelvinToTemperature(0), 200)
        XCTAssertEqual(KeyLightService.kelvinToTemperature(-100), 200)
    }

    func testTemperatureRoundTrip() {
        for api in stride(from: 143, through: 344, by: 10) {
            let kelvin = KeyLightService.temperatureToKelvin(api)
            let back = KeyLightService.kelvinToTemperature(kelvin)
            XCTAssertLessThanOrEqual(abs(back - api), 1, "round-trip drift for api=\(api): got \(back)")
        }
    }

    // MARK: - parseState

    func testParseStateValidPayload() {
        let json = """
        { "numberOfLights": 1, "lights": [
            { "on": 1, "brightness": 80, "temperature": 220 }
        ]}
        """
        let state = KeyLightService.parseState(Data(json.utf8))
        XCTAssertNotNil(state)
        XCTAssertTrue(state?.on == true)
        XCTAssertEqual(state?.brightness, 80)
        XCTAssertEqual(state?.temperature, 220)
    }

    func testParseStateOffWhenOnIsZero() {
        let json = #"{ "lights": [ { "on": 0, "brightness": 50, "temperature": 200 } ] }"#
        XCTAssertEqual(KeyLightService.parseState(Data(json.utf8))?.on, false)
    }

    func testParseStateUsesDefaultsForMissingFields() {
        let json = #"{ "lights": [ { "on": 1 } ] }"#
        let state = KeyLightService.parseState(Data(json.utf8))
        XCTAssertEqual(state?.brightness, 50)
        XCTAssertEqual(state?.temperature, 200)
    }

    func testParseStateRejectsMalformedJSON() {
        XCTAssertNil(KeyLightService.parseState(Data("not json".utf8)))
        XCTAssertNil(KeyLightService.parseState(Data()))
    }

    func testParseStateRejectsMissingLightsKey() {
        let json = #"{ "numberOfLights": 1 }"#
        XCTAssertNil(KeyLightService.parseState(Data(json.utf8)))
    }

    func testParseStateRejectsEmptyLightsArray() {
        let json = #"{ "lights": [] }"#
        XCTAssertNil(KeyLightService.parseState(Data(json.utf8)))
    }

    // MARK: - makeBody

    func testMakeBodyEnvelope() throws {
        let data = try XCTUnwrap(KeyLightService.makeBody(on: true, brightness: 50, temperature: 200))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["numberOfLights"] as? Int, 1)
        let lights = try XCTUnwrap(json["lights"] as? [[String: Any]])
        XCTAssertEqual(lights.count, 1)
    }

    func testMakeBodyOnlyIncludesProvidedKeys() throws {
        let data = try XCTUnwrap(KeyLightService.makeBody(brightness: 50))
        let light = try firstLight(data)
        XCTAssertNil(light["on"])
        XCTAssertNil(light["temperature"])
        XCTAssertEqual(light["brightness"] as? Int, 50)
    }

    func testMakeBodyOnEncodesAsInt() throws {
        let onData = try XCTUnwrap(KeyLightService.makeBody(on: true))
        XCTAssertEqual(try firstLight(onData)["on"] as? Int, 1)

        let offData = try XCTUnwrap(KeyLightService.makeBody(on: false))
        XCTAssertEqual(try firstLight(offData)["on"] as? Int, 0)
    }

    func testMakeBodyClampsBrightness() throws {
        XCTAssertEqual(try brightness(forBrightness: 0), 3)
        XCTAssertEqual(try brightness(forBrightness: -50), 3)
        XCTAssertEqual(try brightness(forBrightness: 200), 100)
        XCTAssertEqual(try brightness(forBrightness: 50), 50)
    }

    func testMakeBodyClampsTemperature() throws {
        XCTAssertEqual(try temperature(forTemperature: 100), 143)
        XCTAssertEqual(try temperature(forTemperature: 500), 344)
        XCTAssertEqual(try temperature(forTemperature: 200), 200)
    }

    func testMakeBodyAllNilStillProducesValidEnvelope() throws {
        let data = try XCTUnwrap(KeyLightService.makeBody())
        let light = try firstLight(data)
        XCTAssertTrue(light.isEmpty)
    }

    // MARK: - helpers

    private func firstLight(_ data: Data) throws -> [String: Any] {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let lights = try XCTUnwrap(json["lights"] as? [[String: Any]])
        return try XCTUnwrap(lights.first)
    }

    private func brightness(forBrightness value: Int) throws -> Int {
        let data = try XCTUnwrap(KeyLightService.makeBody(brightness: value))
        return try XCTUnwrap(firstLight(data)["brightness"] as? Int)
    }

    private func temperature(forTemperature value: Int) throws -> Int {
        let data = try XCTUnwrap(KeyLightService.makeBody(temperature: value))
        return try XCTUnwrap(firstLight(data)["temperature"] as? Int)
    }
}
