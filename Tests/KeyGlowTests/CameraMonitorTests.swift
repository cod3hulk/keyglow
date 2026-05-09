import XCTest
@testable import KeyGlow

final class CameraMonitorTests: XCTestCase {

    func testClassifyDetectsStartStream() {
        XCTAssertEqual(CameraMonitor.classify("Start Stream"), .streamStarted)
    }

    func testClassifyDetectsStopStream() {
        XCTAssertEqual(CameraMonitor.classify("Stop Stream"), .streamStopped)
    }

    func testClassifyMatchesEmbeddedSubstring() {
        let realisticLogLine =
            "2026-05-09 10:23:45.123 default 0x1a2b3c  UVCExtension: device Start Stream for FaceTime HD Camera"
        XCTAssertEqual(CameraMonitor.classify(realisticLogLine), .streamStarted)

        let stopLine =
            "2026-05-09 10:24:01.456 default 0x1a2b3c  UVCExtension: device Stop Stream"
        XCTAssertEqual(CameraMonitor.classify(stopLine), .streamStopped)
    }

    func testClassifyReturnsNilForUnrelatedLines() {
        XCTAssertNil(CameraMonitor.classify(""))
        XCTAssertNil(CameraMonitor.classify("some unrelated log line"))
        XCTAssertNil(CameraMonitor.classify("started the stream"))   // wrong casing
        XCTAssertNil(CameraMonitor.classify("stopped streaming"))    // wrong wording
    }

    func testClassifyPrefersStartWhenBothPresent() {
        // Defensive: if a line ever contained both phrases, current behavior is "start wins".
        // Pinning this so the auto-toggle doesn't silently flip if the impl is reordered.
        let line = "Start Stream ... Stop Stream"
        XCTAssertEqual(CameraMonitor.classify(line), .streamStarted)
    }
}
