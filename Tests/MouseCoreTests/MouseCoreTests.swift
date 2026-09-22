import Foundation
import MouseCore

final class MouseCoreTests {
    private var artworkDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LogiMouseControl/DeviceImages")
    }
    func testDeviceColourUsesExtendedModelByteAndRejectsTruncation() throws {
        var payload = [UInt8](repeating: 0, count: 16)
        payload[7] = 0xb0; payload[8] = 0x42; payload[13] = 1; payload[14] = 5
        XCTAssertEqual(try MouseIdentity.extendedModelID(from: payload), 1)
        do {
            _ = try MouseIdentity.extendedModelID(from: Array(payload.prefix(13)))
            XCTFail("Truncated identity accepted")
        } catch HIDFailure.malformed {} catch { XCTFail("Unexpected error") }
    }
    func testCatalogSelectsWhiteAndAllVariantImagesExist() throws {
        let manifest = try JSONDecoder().decode(MouseArtworkManifest.self, from: Data(contentsOf: artworkDirectory.appendingPathComponent("manifest.json")))
        XCTAssertEqual(manifest.imageName(extendedModelID: 1, buttons: true), "side_ext_1.png")
        XCTAssertEqual(manifest.imageName(extendedModelID: 1, buttons: false), "front_ext_1.png")
        XCTAssertEqual(manifest.imageName(extendedModelID: nil, buttons: true), "side_ext_1.png")
        XCTAssertEqual(manifest.imageName(extendedModelID: 255, buttons: true), "side_core.png")
        for ext: UInt8 in 0...5 {
            for buttons in [false, true] {
                let name = try XCTUnwrap(manifest.imageName(extendedModelID: ext, buttons: buttons))
                let data = try Data(contentsOf: artworkDirectory.appendingPathComponent(name))
                XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
            }
        }
    }
    func testButtonHotspotsAccountForImagePaddingAndKeepHapticPanelDistinct() throws {
        let metadata = try JSONDecoder().decode(MouseArtworkMetadata.self, from: Data(contentsOf: artworkDirectory.appendingPathComponent("core_metadata.json")))
        let buttons = try XCTUnwrap(metadata.buttons)
        let ids = Set(buttons.assignments?.compactMap(\.controlID) ?? [])
        XCTAssertEqual(ids, Set<UInt16>([0x52, 0xc4, 0x56, 0x53, 0xc3, 0x1a0]))
        let middle = try XCTUnwrap(buttons.normalizedPoint(for: 0x52, pngWidth: 656))
        XCTAssertLessThan(abs(middle.x - (10 + 0.755 * 636) / 656), 0.00001)
        XCTAssertEqual(middle.y, 0.19)
        let gesture = try XCTUnwrap(buttons.normalizedPoint(for: 0xc3, pngWidth: 656))
        let panel = try XCTUnwrap(buttons.normalizedPoint(for: 0x1a0, pngWidth: 656))
        XCTAssertLessThan(gesture.y, panel.y)
        XCTAssertNil(buttons.normalizedPoint(for: 0x50, pngWidth: 656))
        XCTAssertNil(buttons.normalizedPoint(for: 0x999, pngWidth: 656))
        XCTAssertNil(buttons.normalizedPoint(for: 0x52, pngWidth: 0))
    }
    func testLongReportRoundTripAndPadding() throws {
        let packet = HIDPacket(feature: 4, function: 3, softwareID: 7, payload: [0, 0x1f, 0x40])
        XCTAssertEqual(packet.bytes.count, 20)
        XCTAssertEqual(Array(packet.bytes.prefix(7)), [0x11, 0xff, 4, 0x37, 0, 0x1f, 0x40])
        let decoded = try XCTUnwrap(HIDPacket.decode(packet.bytes))
        XCTAssertEqual(decoded.feature, 4)
        XCTAssertEqual(decoded.payload.prefix(3), [0, 0x1f, 0x40])
    }
    func testUnrelatedAndUnsolicitedResponsesCannotCompleteRequest() {
        let request = HIDPacket(feature: 4, function: 3, softwareID: 7)
        for reply in [HIDPacket(feature: 4, function: 3, softwareID: 0), HIDPacket(device: 1, feature: 4, function: 3, softwareID: 7), HIDPacket(feature: 5, function: 3, softwareID: 7), HIDPacket(feature: 4, function: 2, softwareID: 7)] {
            XCTAssertNil(reply.response(to: request))
        }
    }
    func testDeviceRejectionIsNotAFalseSuccess() {
        let request = HIDPacket(feature: 4, function: 3, softwareID: 7)
        let reply = HIDPacket(feature: 0xff, function: 0, softwareID: 4, payload: [0x37, 2])
        guard case .failure(.rejected(2)) = reply.response(to: request) else { return XCTFail("Expected protocol rejection") }
    }
    func testTruncatedAndNonHIDReportsAreIgnored() {
        for data: [UInt8] in [[], [0x11], [0x10, 0xff, 1, 0, 0], Array(repeating: 0, count: 20)] { XCTAssertNil(HIDPacket.decode(data)) }
    }
    func testDistanceConservationAtDifferentFrameRates() {
        for hz in [60.0, 120.0, 144.0] {
            var integrator = ScrollIntegrator(); integrator.feed(480)
            var distance: Int32 = 0
            for _ in 0..<Int(hz * 3) { distance += integrator.advance(seconds: 1 / hz, smoothness: 0.07) }
            XCTAssertLessThanOrEqual(abs(distance - 480), 1)
            XCTAssertFalse(integrator.isActive)
        }
    }
    func testTinyHighResolutionStepsAreNotLost() {
        var integrator = ScrollIntegrator(); var distance: Int32 = 0
        for _ in 0..<1000 { integrator.feed(0.12); distance += integrator.advance(seconds: 1 / 120, smoothness: 0.07) }
        for _ in 0..<300 { distance += integrator.advance(seconds: 1 / 120, smoothness: 0.07) }
        XCTAssertLessThanOrEqual(abs(distance - 120), 1)
    }
    func testUnsmoothedModeHasNoInertialTail() {
        var integrator = ScrollIntegrator()
        integrator.feed(40)
        XCTAssertEqual(integrator.takeImmediately(), 40)
        XCTAssertFalse(integrator.isActive)
        XCTAssertEqual(integrator.advance(seconds: 0.01, smoothness: 0.1), 0)
    }
    func testUnsmoothedModeRetainsSubpixelMovement() {
        var integrator = ScrollIntegrator(); var distance: Int32 = 0
        for _ in 0..<100 { integrator.feed(0.25); distance += integrator.takeImmediately() }
        XCTAssertEqual(distance, 25)
    }
    func testDirectionChangeStopsOldMomentumImmediately() {
        var integrator = ScrollIntegrator(); integrator.feed(1000)
        _ = integrator.advance(seconds: 1 / 120, smoothness: 0.1)
        integrator.feed(-30)
        XCTAssertEqual(integrator.remaining, -30)
        XCTAssertLessThan(integrator.advance(seconds: 1 / 60, smoothness: 0.07), 0)
    }
    func testResetAndNonFiniteInputCannotProduceRunawayScroll() {
        var integrator = ScrollIntegrator(); integrator.feed(.infinity); integrator.feed(.nan)
        XCTAssertEqual(integrator.remaining, 0)
        integrator.feed(100); integrator.reset()
        XCTAssertEqual(integrator.advance(seconds: .nan, smoothness: 0.07), 0)
        XCTAssertEqual(integrator.advance(seconds: 1, smoothness: 0.07), 0)
    }
    func testOrdinaryButtonDoesNotReceiveUnsupportedRawFlags() {
        XCTAssertEqual(reportingPayload(cid: 0x53, capabilities: 0x20, diverted: true, rawXY: false), [0, 0x53, 3, 0, 0, 0])
    }
    func testGestureFlagsNeverEnableAnalyticsOrPersistentCapture() {
        let payload = reportingPayload(cid: 0x1a0, capabilities: 0x0f60, diverted: true, rawXY: true)
        XCTAssertEqual(payload, [1, 0xa0, 0xbb, 0, 0, 0x0a])
        XCTAssertEqual(payload[2] & 4, 0)
        XCTAssertEqual(payload[5] & 1, 0)
    }
    func testRestoreReleasesAllSupportedDiversionFlagsAndKeepsRemap() {
        XCTAssertEqual(reportingPayload(cid: 0xc3, capabilities: 0x0f60, diverted: false, rawXY: false, remap: [0, 0x53]), [0, 0xc3, 0xaa, 0, 0x53, 0x0a])
    }
    func testSignedHardwareDelta() {
        XCTAssertEqual(signedWord([0xff, 0xf0]), -16)
        XCTAssertEqual(signedWord([0x00, 0x10]), 16)
        XCTAssertEqual(splitWord(8000), [0x1f, 0x40])
    }
    func testSmartShiftUses255ToDisableAutomaticRelease() {
        XCTAssertEqual(WheelMode.ratchet.threshold(30), 255)
        XCTAssertEqual(WheelMode.freeSpin.wireValue, 1)
        XCTAssertEqual(WheelMode.smartShift.threshold(0), 1)
        XCTAssertEqual(WheelMode.smartShift.threshold(999), 254)
    }
    func testHapticPanelDiscardsInitialPositionJump() {
        var panel = GestureAccumulator(discardFirst: true)
        panel.add(dx: 30000, dy: -30000)
        XCTAssertNil(panel.direction)
        panel.add(dx: -70, dy: 2)
        XCTAssertEqual(panel.direction, "left")
        var button = GestureAccumulator(discardFirst: false)
        button.add(dx: 0, dy: 80)
        XCTAssertEqual(button.direction, "down")
    }
    func testCorruptPreferencesAreClampedAndRingIsRepaired() {
        var p = Preferences(); p.scroll.speed = .infinity; p.scroll.smoothness = -2; p.ring = [.mouse(.ring)]
        p.desiredDPI = 999999; p.desiredThreshold = 0; p.desiredIntensity = -1; p.sanitize()
        XCTAssertEqual(p.scroll.speed, 1); XCTAssertEqual(p.scroll.smoothness, 0.015)
        XCTAssertEqual(p.ring.count, 6); XCTAssertFalse(p.ring.contains(.mouse(.ring)))
        XCTAssertEqual(p.desiredDPI, 8000); XCTAssertEqual(p.desiredThreshold, 1); XCTAssertEqual(p.desiredIntensity, 0)
    }
    func testRingSupportsApplicationsAndLegacyActions() throws {
        let legacy = Data("\"missionControl\"".utf8)
        XCTAssertEqual(try JSONDecoder().decode(RingAction.self, from: legacy), .mouse(.missionControl))

        let application = RingApplication(bundleIdentifier: "com.example.Editor", name: "Editor", path: "/Applications/Editor.app")
        let action = RingAction.application(application)
        XCTAssertEqual(try JSONDecoder().decode(RingAction.self, from: JSONEncoder().encode(action)), action)

        var preferences = Preferences()
        preferences.ring[0] = action
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.ring, preferences.ring)
    }
    func testSettingsRoundTripIncludesApplicationProfiles() throws {
        var p = Preferences(); p.buttons["416"] = .ring
        p.profiles = [AppProfile(id: "example.editor", name: "Editor", scroll: p.scroll, buttons: p.buttons)]
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(restored.profiles, p.profiles)
        XCTAssertEqual(restored.buttons["416"], .ring)
    }
}

private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) { precondition(actual == expected, "Expected \(expected), got \(actual)", file: (file), line: line) }
private func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { precondition(value == nil, "Expected nil", file: (file), line: line) }
private func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { precondition(!value, "Expected false", file: (file), line: line) }
private func XCTAssertLessThan<T: Comparable>(_ actual: T, _ other: T, file: StaticString = #filePath, line: UInt = #line) { precondition(actual < other, "Expected less than", file: (file), line: line) }
private func XCTAssertLessThanOrEqual<T: Comparable>(_ actual: T, _ other: T, file: StaticString = #filePath, line: UInt = #line) { precondition(actual <= other, "Expected less than or equal", file: (file), line: line) }
private func XCTFail(_ message: String, file: StaticString = #filePath, line: UInt = #line) { preconditionFailure(message, file: (file), line: line) }
private func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw HIDFailure.malformed }; return value }

@main enum Checks {
    static func main() throws {
        let suite = MouseCoreTests()
        try suite.testLongReportRoundTripAndPadding(); print("PASS testLongReportRoundTripAndPadding")
        suite.testUnrelatedAndUnsolicitedResponsesCannotCompleteRequest(); print("PASS testUnrelatedAndUnsolicitedResponsesCannotCompleteRequest")
        suite.testDeviceRejectionIsNotAFalseSuccess(); print("PASS testDeviceRejectionIsNotAFalseSuccess")
        suite.testTruncatedAndNonHIDReportsAreIgnored(); print("PASS testTruncatedAndNonHIDReportsAreIgnored")
        suite.testDistanceConservationAtDifferentFrameRates(); print("PASS testDistanceConservationAtDifferentFrameRates")
        suite.testTinyHighResolutionStepsAreNotLost(); print("PASS testTinyHighResolutionStepsAreNotLost")
        suite.testDirectionChangeStopsOldMomentumImmediately(); print("PASS testDirectionChangeStopsOldMomentumImmediately")
        suite.testResetAndNonFiniteInputCannotProduceRunawayScroll(); print("PASS testResetAndNonFiniteInputCannotProduceRunawayScroll")
        suite.testSignedHardwareDelta(); print("PASS testSignedHardwareDelta")
        suite.testSmartShiftUses255ToDisableAutomaticRelease(); print("PASS testSmartShiftUses255ToDisableAutomaticRelease")
        suite.testHapticPanelDiscardsInitialPositionJump(); print("PASS testHapticPanelDiscardsInitialPositionJump")
        suite.testCorruptPreferencesAreClampedAndRingIsRepaired(); print("PASS testCorruptPreferencesAreClampedAndRingIsRepaired")
        try suite.testRingSupportsApplicationsAndLegacyActions(); print("PASS testRingSupportsApplicationsAndLegacyActions")
        try suite.testSettingsRoundTripIncludesApplicationProfiles(); print("PASS testSettingsRoundTripIncludesApplicationProfiles")
        suite.testUnsmoothedModeHasNoInertialTail(); print("PASS testUnsmoothedModeHasNoInertialTail")
        suite.testUnsmoothedModeRetainsSubpixelMovement(); print("PASS testUnsmoothedModeRetainsSubpixelMovement")
        suite.testOrdinaryButtonDoesNotReceiveUnsupportedRawFlags(); print("PASS testOrdinaryButtonDoesNotReceiveUnsupportedRawFlags")
        suite.testGestureFlagsNeverEnableAnalyticsOrPersistentCapture(); print("PASS testGestureFlagsNeverEnableAnalyticsOrPersistentCapture")
        suite.testRestoreReleasesAllSupportedDiversionFlagsAndKeepsRemap(); print("PASS testRestoreReleasesAllSupportedDiversionFlagsAndKeepsRemap")
        try suite.testDeviceColourUsesExtendedModelByteAndRejectsTruncation(); print("PASS testDeviceColourUsesExtendedModelByteAndRejectsTruncation")
        try suite.testCatalogSelectsWhiteAndAllVariantImagesExist(); print("PASS testCatalogSelectsWhiteAndAllVariantImagesExist")
        try suite.testButtonHotspotsAccountForImagePaddingAndKeepHapticPanelDistinct(); print("PASS testButtonHotspotsAccountForImagePaddingAndKeepHapticPanelDistinct")
        print("22 checks passed")
    }
}
