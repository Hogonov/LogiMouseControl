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
        XCTAssertEqual(panel.direction, .click)
        panel.add(dx: -70, dy: 2)
        XCTAssertEqual(panel.direction, .left)
        var button = GestureAccumulator(discardFirst: false)
        button.add(dx: 0, dy: 80)
        XCTAssertEqual(button.direction, .down)
    }
    func testGestureBelowThresholdIsClick() {
        var gesture = GestureAccumulator(discardFirst: false)
        gesture.add(dx: 40, dy: -40); gesture.add(dx: 20, dy: -20)
        XCTAssertEqual(gesture.direction, .click)
        gesture.add(dx: 1, dy: -1)
        XCTAssertEqual(gesture.direction, .up)
        var right = GestureAccumulator(discardFirst: false)
        right.add(dx: 90, dy: 89)
        XCTAssertEqual(right.direction, .right)
    }
    func testLegacyPreferencesWithoutGesturesKeepSettings() throws {
        // Shape written by the version before CH-0002: no "gestures" key.
        let legacy = Data(#"{"scroll":{"enabled":true,"smooth":false,"natural":true,"horizontalNatural":true,"speed":2,"horizontalSpeed":1,"smoothness":0.07},"buttons":{"195":"gestures","83":"back"},"ring":["missionControl","spotlight","screenshot","copy","paste","playPause"],"profiles":[],"desiredDPI":1600,"desiredThreshold":40,"desiredIntensity":75}"#.utf8)
        let p = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertEqual(p.buttons["195"], .gestures); XCTAssertEqual(p.buttons["83"], .back)
        XCTAssertEqual(p.scroll.speed, 2); XCTAssertFalse(p.scroll.smooth)
        XCTAssertEqual(p.desiredDPI, 1600); XCTAssertEqual(p.desiredThreshold, 40); XCTAssertEqual(p.desiredIntensity, 75)
        XCTAssertEqual(p.gestureActions(for: 0xc3), GestureActions())
        let defaults = GestureActions()
        XCTAssertEqual(defaults[.up], .missionControl); XCTAssertEqual(defaults[.down], .appExpose)
        XCTAssertEqual(defaults[.left], .previousDesktop); XCTAssertEqual(defaults[.right], .nextDesktop)
        XCTAssertEqual(defaults[.click], .missionControl)
        let minimal = try JSONDecoder().decode(Preferences.self, from: Data(#"{"buttons":{"83":"forward"}}"#.utf8))
        XCTAssertEqual(minimal.buttons["83"], .forward); XCTAssertEqual(minimal.ring, Preferences().ring)
    }
    func testGestureActionsRoundTripPerControl() throws {
        var p = Preferences()
        var actions = GestureActions(); actions[.left] = .spotlight; actions[.click] = .none
        p.gestures["195"] = actions
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(restored.gestureActions(for: 0xc3)[.left], .spotlight)
        XCTAssertEqual(restored.gestureActions(for: 0xc3)[.click], MouseAction.none)
        XCTAssertEqual(restored.gestureActions(for: 0xc3)[.right], .nextDesktop)
        XCTAssertEqual(restored.gestureActions(for: 0x1a0), GestureActions())
    }
    func testInvalidGestureActionsAreRepaired() throws {
        let partial = try JSONDecoder().decode(GestureActions.self, from: Data(#"{"up":"gestures","left":"system","right":"copy"}"#.utf8))
        XCTAssertEqual(partial[.up], .missionControl); XCTAssertEqual(partial[.left], .previousDesktop)
        XCTAssertEqual(partial[.right], .copy); XCTAssertEqual(partial[.down], .appExpose)
        let unknown = try JSONDecoder().decode(Preferences.self, from: Data(#"{"buttons":{"83":"back"},"gestures":{"195":{"left":"futureAction","right":"copy"}}}"#.utf8))
        XCTAssertEqual(unknown.buttons["83"], .back)
        XCTAssertEqual(unknown.gestureActions(for: 0xc3)[.left], .previousDesktop); XCTAssertEqual(unknown.gestureActions(for: 0xc3)[.right], .copy)
        var p = Preferences(); var actions = GestureActions(); actions[.down] = .gestures; p.gestures["416"] = actions
        p.sanitize()
        XCTAssertEqual(p.gestureActions(for: 0x1a0)[.down], .appExpose)
    }
    func testDesktopSwitchActionsAreSelectable() {
        for action in [MouseAction.previousDesktop, .nextDesktop] {
            XCTAssertTrue(MouseAction.allCases.contains(action))
            XCTAssertTrue(MouseAction.ringChoices.contains(action))
            XCTAssertTrue(MouseAction.gestureChoices.contains(action))
            XCTAssertFalse(action.title.isEmpty); XCTAssertFalse(action.symbol.isEmpty)
        }
        XCTAssertEqual(MouseAction.previousDesktop.rawValue, "previousDesktop")
        XCTAssertFalse(MouseAction.gestureChoices.contains(.system)); XCTAssertFalse(MouseAction.gestureChoices.contains(.gestures))
    }
    func testSpaceSwipeFollowsMovementAndChainsDesktops() {
        var swipe = SpaceSwipe(sign: 1, countsPerSpace: 800)
        XCTAssertEqual(swipe.move(dx: 400, at: 0), [SwipeStep(.began, progress: 0.5)])
        XCTAssertEqual(swipe.move(dx: 200, at: 0.01), [SwipeStep(.changed, progress: 0.75)])
        // Crossing a whole desktop ends the segment and continues with the remainder.
        let crossed = swipe.move(dx: 400, at: 0.02)
        XCTAssertEqual(crossed.map(\.phase), [.ended, .began])
        XCTAssertEqual(crossed[0].progress, 1); XCTAssertTrue(crossed[0].velocity >= 1)
        XCTAssertEqual(crossed[1].progress, 0.25)
        // One large step crosses two desktops; mirrored sign goes the other way.
        var mirrored = SpaceSwipe(sign: -1, countsPerSpace: 800)
        _ = mirrored.move(dx: 80, at: 0)
        let far = mirrored.move(dx: 1600, at: 0.01)
        XCTAssertEqual(far.map(\.phase), [.ended, .began, .ended, .began])
        XCTAssertEqual(far[0].progress, -1); XCTAssertTrue(far[0].velocity <= -1)
        XCTAssertEqual(far[3].progress, -0.1, accuracy: 1e-9)
        XCTAssertEqual(mirrored.cancel(), [SwipeStep(.cancelled, progress: far[3].progress)])
        XCTAssertEqual(mirrored.cancel(), [])
        var invalid = SpaceSwipe(sign: 1, countsPerSpace: 800)
        XCTAssertEqual(invalid.move(dx: .nan, at: 0), []); XCTAssertFalse(invalid.began)
    }
    func testSpaceSwipeReleaseUsesRecentVelocity() {
        var forward = SpaceSwipe(sign: 1, countsPerSpace: 800)
        _ = forward.move(dx: 100, at: 0); _ = forward.move(dx: 100, at: 0.01)
        let finished = forward.release(at: 0.02)
        XCTAssertEqual(finished.map(\.phase), [.ended]); XCTAssertTrue(finished[0].velocity > 0)
        XCTAssertEqual(forward.release(at: 0.03), [])
        var back = SpaceSwipe(sign: 1, countsPerSpace: 800)
        _ = back.move(dx: 300, at: 0); _ = back.move(dx: -100, at: 0.01); _ = back.move(dx: -100, at: 0.02)
        XCTAssertEqual(back.release(at: 0.03).map(\.phase), [.cancelled])
        var resting = SpaceSwipe(sign: 1, countsPerSpace: 800)
        _ = resting.move(dx: 300, at: 0); _ = resting.move(dx: -100, at: 0.01)
        XCTAssertEqual(resting.release(at: 0.5), [SwipeStep(.ended, progress: 0.25, velocity: 0)])
    }
    func testGestureSessionStartsSwipeOnlyForHorizontalTravel() {
        var session = GestureSession(discardFirst: false, swipeSign: 1, countsPerSpace: 800)
        XCTAssertEqual(session.add(dx: 50, dy: 0, at: 0, allowSwipe: true), [])
        XCTAssertEqual(session.add(dx: 20, dy: 0, at: 0.01, allowSwipe: true), [SwipeStep(.began, progress: 70.0 / 800)])
        XCTAssertTrue(session.isSwiping)
        XCTAssertEqual(session.add(dx: 0, dy: 500, at: 0.02, allowSwipe: true).map(\.phase), [.changed])
        guard case .swipe(let steps, .right) = session.release(at: 0.03) else { return XCTFail("Expected swipe") }
        XCTAssertEqual(steps.map(\.phase), [.ended])
        // Vertical first: no swipe, the direction is resolved on release as before.
        var vertical = GestureSession(discardFirst: false, swipeSign: 1, countsPerSpace: 800)
        _ = vertical.add(dx: 0, dy: -70, at: 0, allowSwipe: true)
        XCTAssertEqual(vertical.add(dx: -500, dy: 0, at: 0.01, allowSwipe: true), [])
        XCTAssertEqual(vertical.release(at: 0.02), .action(.left))
        var click = GestureSession(discardFirst: false, swipeSign: 1, countsPerSpace: 800)
        _ = click.add(dx: 30, dy: 10, at: 0, allowSwipe: true)
        XCTAssertEqual(click.release(at: 0.01), .action(.click))
        // No desktop pair, or another control swiping: discrete gesture.
        var plain = GestureSession(discardFirst: false, swipeSign: nil, countsPerSpace: 800)
        XCTAssertEqual(plain.add(dx: 200, dy: 0, at: 0, allowSwipe: true), [])
        XCTAssertEqual(plain.release(at: 0.01), .action(.right))
        var second = GestureSession(discardFirst: false, swipeSign: 1, countsPerSpace: 800)
        XCTAssertEqual(second.add(dx: 200, dy: 0, at: 0, allowSwipe: false), [])
        XCTAssertFalse(second.isSwiping)
        // The haptic panel's initial jump never reaches the swipe.
        var panel = GestureSession(discardFirst: true, swipeSign: 1, countsPerSpace: 800)
        XCTAssertEqual(panel.add(dx: 30000, dy: 0, at: 0, allowSwipe: true), [])
        XCTAssertEqual(panel.add(dx: -80, dy: 0, at: 0.01, allowSwipe: true), [SwipeStep(.began, progress: -0.1)])
        XCTAssertEqual(panel.cancel(), [SwipeStep(.cancelled, progress: -0.1)])
        XCTAssertEqual(panel.cancel(), [])
    }
    func testDesktopSwipeSignFollowsAssignments() {
        XCTAssertEqual(GestureActions().desktopSwipeSign, 1)
        var mirrored = GestureActions(); mirrored[.left] = .nextDesktop; mirrored[.right] = .previousDesktop
        XCTAssertEqual(mirrored.desktopSwipeSign, -1)
        var other = GestureActions(); other[.left] = .back
        XCTAssertEqual(other.desktopSwipeSign, nil)
        var same = GestureActions(); same[.left] = .nextDesktop
        XCTAssertEqual(same.desktopSwipeSign, nil)
    }
    func testSpaceSwipeScalesWithDPI() {
        XCTAssertEqual(SpaceSwipe.countsPerSpace(dpi: 1000), 800)
        XCTAssertEqual(SpaceSwipe.countsPerSpace(dpi: 2000), 1600)
        XCTAssertEqual(SpaceSwipe.countsPerSpace(dpi: nil), 800)
        XCTAssertEqual(SpaceSwipe.countsPerSpace(dpi: 0), 800)
        var guarded = SpaceSwipe(sign: 1, countsPerSpace: 0)
        XCTAssertEqual(guarded.move(dx: 400, at: 0), [SwipeStep(.began, progress: 0.5)])
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
private func XCTAssertEqual(_ actual: Double, _ expected: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) { precondition(abs(actual - expected) <= accuracy, "Expected \(expected), got \(actual)", file: (file), line: line) }
private func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { precondition(value == nil, "Expected nil", file: (file), line: line) }
private func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { precondition(!value, "Expected false", file: (file), line: line) }
private func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { precondition(value, "Expected true", file: (file), line: line) }
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
        suite.testGestureBelowThresholdIsClick(); print("PASS testGestureBelowThresholdIsClick")
        try suite.testLegacyPreferencesWithoutGesturesKeepSettings(); print("PASS testLegacyPreferencesWithoutGesturesKeepSettings")
        try suite.testGestureActionsRoundTripPerControl(); print("PASS testGestureActionsRoundTripPerControl")
        try suite.testInvalidGestureActionsAreRepaired(); print("PASS testInvalidGestureActionsAreRepaired")
        suite.testDesktopSwitchActionsAreSelectable(); print("PASS testDesktopSwitchActionsAreSelectable")
        suite.testSpaceSwipeFollowsMovementAndChainsDesktops(); print("PASS testSpaceSwipeFollowsMovementAndChainsDesktops")
        suite.testSpaceSwipeReleaseUsesRecentVelocity(); print("PASS testSpaceSwipeReleaseUsesRecentVelocity")
        suite.testGestureSessionStartsSwipeOnlyForHorizontalTravel(); print("PASS testGestureSessionStartsSwipeOnlyForHorizontalTravel")
        suite.testDesktopSwipeSignFollowsAssignments(); print("PASS testDesktopSwipeSignFollowsAssignments")
        suite.testSpaceSwipeScalesWithDPI(); print("PASS testSpaceSwipeScalesWithDPI")
        print("32 checks passed")
    }
}
