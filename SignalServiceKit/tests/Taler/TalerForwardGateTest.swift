//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// `TalerForwardGate.needsOpenShareWarning` nach `TalerForwardGate.kt` /
/// `anyOpen` (signal-android): gewarnt wird genau dann, wenn mindestens ein
/// Anteil noch OFFEN ist.
final class TalerForwardGateTest: XCTestCase {

    // MARK: - Einzelzahlung

    func testSingleOpenNeedsWarning() {
        XCTAssertTrue(TalerForwardGate.needsOpenShareWarning(statuses: [.offen]))
    }

    func testSingleAcceptedNeedsNoWarning() {
        XCTAssertFalse(TalerForwardGate.needsOpenShareWarning(statuses: [.angenommen]))
    }

    func testSingleExpiredNeedsNoWarning() {
        XCTAssertFalse(TalerForwardGate.needsOpenShareWarning(statuses: [.abgelaufen]))
    }

    func testSingleMissingRecordNeedsNoWarning() {
        // Wie Android: nil ist nicht OFFEN.
        XCTAssertFalse(TalerForwardGate.needsOpenShareWarning(statuses: [nil]))
    }

    func testEmptyNeedsNoWarning() {
        XCTAssertFalse(TalerForwardGate.needsOpenShareWarning(statuses: []))
    }

    // MARK: - Gruppe (mehrere Anteile)

    func testOneOpenAmongManyNeedsWarning() {
        XCTAssertTrue(TalerForwardGate.needsOpenShareWarning(statuses: [.angenommen, .offen, .abgelaufen]))
    }

    func testAllDecidedNeedsNoWarning() {
        XCTAssertFalse(TalerForwardGate.needsOpenShareWarning(statuses: [.angenommen, .lokalAbgelehnt, .abgelaufen]))
    }

    func testMissingRecordAmongManyNeedsNoWarning() {
        XCTAssertFalse(TalerForwardGate.needsOpenShareWarning(statuses: [nil, .angenommen, nil]))
    }

    func testUnknownOfflineNeedsNoWarning() {
        XCTAssertFalse(TalerForwardGate.needsOpenShareWarning(statuses: [.unbekanntOffline]))
    }
}
