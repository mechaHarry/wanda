import XCTest
@testable import Wanda

final class LatencyProbeTests: XCTestCase {
    func testRecordsCompleteKeystrokeMeasurement() {
        var probe = LatencyProbe()
        let id = probe.recordKeyReceived(at: 100)

        probe.recordPTYWrite(for: id, at: 120)
        probe.recordModelMutation(for: id, at: 150)
        probe.recordFramePresented(for: id, at: 180)

        XCTAssertEqual(probe.completedMeasurements.count, 1)
        XCTAssertEqual(probe.completedMeasurements[0].keystrokeToPresentNanoseconds, 80)
    }

    func testP95SummaryUsesSortedMeasurements() {
        var probe = LatencyProbe()
        for index in 1...20 {
            let id = probe.recordKeyReceived(at: UInt64(index * 100))
            probe.recordFramePresented(for: id, at: UInt64(index * 100 + index))
        }

        XCTAssertEqual(probe.summary().p95Nanoseconds, 19)
    }

    func testEmptySummaryHasZeroCountAndNilP95() {
        let probe = LatencyProbe()

        XCTAssertEqual(probe.summary(), LatencySummary(count: 0, p95Nanoseconds: nil))
    }

    func testUnknownIDsAreIgnored() {
        var probe = LatencyProbe()

        probe.recordPTYWrite(for: 404, at: 120)
        probe.recordModelMutation(for: 404, at: 150)
        probe.recordFramePresented(for: 404, at: 180)

        XCTAssertEqual(probe.completedMeasurements, [])
    }

    func testIncompleteMeasurementHasNilDurationUntilPresented() {
        var measurement = LatencyMeasurement(id: 1, keyReceived: 100)

        XCTAssertNil(measurement.keystrokeToPresentNanoseconds)

        measurement.framePresented = 180

        XCTAssertEqual(measurement.keystrokeToPresentNanoseconds, 80)
    }
}
