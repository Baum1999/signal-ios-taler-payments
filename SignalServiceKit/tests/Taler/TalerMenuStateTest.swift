//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// `TalerMenuState.compute` nach `TalerMenuStateTest.kt` (signal-android):
/// Einzel-URI-Matrix und Gruppenfaelle (Ersteller, Empfaenger mit Umlauf,
/// Claim unterdrueckt Ablehnen, kein Teilnehmer).
final class TalerMenuStateTest: XCTestCase {

    private let uriA = "taler://pay-push/exchange.example/A"
    private let uriB = "taler://pay-push/exchange.example/B"
    private let uriC = "taler://pay-push/exchange.example/C"

    private func record(
        _ uri: String,
        status: TalerPaymentStatus,
        isOwnPayment: Bool,
        uriKind: TalerUriKind? = .payPush
    ) -> TalerPaymentRecord {
        TalerPaymentRecord(
            uri: uri,
            threadUniqueId: "t1",
            uriKind: uriKind,
            status: status,
            createdAt: 1,
            isOwnPayment: isOwnPayment
        )
    }

    private func computeSingle(_ record: TalerPaymentRecord?) -> TalerMenuTargets {
        TalerMenuState.compute(uris: [uriA], records: [record], role: nil, claimedUris: [], anyClaimed: false)
    }

    // MARK: - Gate

    func testHasTalerUris() {
        XCTAssertTrue(TalerMenuGate.hasTalerUris(body: "Payment: taler://pay-push/exchange.example/AAA"))
        XCTAssertFalse(TalerMenuGate.hasTalerUris(body: nil))
        XCTAssertFalse(TalerMenuGate.hasTalerUris(body: ""))
        XCTAssertFalse(TalerMenuGate.hasTalerUris(body: "Kein Taler-Link hier."))
    }

    // MARK: - Einzel-URI

    func testEmptyUrisYieldNone() {
        XCTAssertEqual(TalerMenuState.compute(uris: [], records: [], role: nil, claimedUris: [], anyClaimed: false), .none)
    }

    func testOwnOpenPaymentShowsCancelAndRefresh() {
        let targets = computeSingle(record(uriA, status: .offen, isOwnPayment: true))
        XCTAssertNil(targets.rejectUri)
        XCTAssertEqual(targets.cancelUris, [uriA])
        XCTAssertTrue(targets.showCancel)
        XCTAssertTrue(targets.showRefresh)
        XCTAssertFalse(targets.showRefund)
    }

    func testForeignOpenPaymentShowsReject() {
        let targets = computeSingle(record(uriA, status: .offen, isOwnPayment: false))
        XCTAssertEqual(targets.rejectUri, uriA)
        XCTAssertTrue(targets.showReject)
        XCTAssertEqual(targets.cancelUris, [])
    }

    func testAcceptedForeignPaymentShowsRefundOnly() {
        let targets = computeSingle(record(uriA, status: .angenommen, isOwnPayment: false))
        XCTAssertNil(targets.rejectUri)
        XCTAssertEqual(targets.cancelUris, [])
        XCTAssertEqual(targets.refundUris, [uriA])
        XCTAssertTrue(targets.showRefund)
    }

    func testMissingRecordYieldsNone() {
        XCTAssertEqual(computeSingle(nil), .none)
    }

    func testNonPayPushYieldsNone() {
        XCTAssertEqual(computeSingle(record(uriA, status: .offen, isOwnPayment: true, uriKind: .payPull)), .none)
    }

    // MARK: - Gruppe

    func testCreatorCancelsOwnOpenShares() {
        let targets = TalerMenuState.compute(
            uris: [uriA, uriB],
            records: [
                record(uriA, status: .offen, isOwnPayment: true),
                record(uriB, status: .angenommen, isOwnPayment: true),
            ],
            role: .creator,
            claimedUris: [],
            anyClaimed: false
        )
        XCTAssertEqual(targets.cancelUris, [uriA])
        XCTAssertNil(targets.rejectUri)
    }

    func testRecipientRejectsNextOpenShareWithWraparound() {
        // Ab dem eigenen Index ist alles entschieden -> Umlauf zum
        // naechsten offenen Anteil am Anfang.
        let targets = TalerMenuState.compute(
            uris: [uriA, uriB, uriC],
            records: [
                record(uriA, status: .angenommen, isOwnPayment: true),
                record(uriB, status: .offen, isOwnPayment: true),
                record(uriC, status: .abgelaufen, isOwnPayment: true),
            ],
            role: .recipient(myIndex: 2),
            claimedUris: [],
            anyClaimed: false
        )
        XCTAssertEqual(targets.rejectUri, uriB)
    }

    func testAnyClaimedSuppressesReject() {
        let targets = TalerMenuState.compute(
            uris: [uriA, uriB],
            records: [
                record(uriA, status: .offen, isOwnPayment: true),
                nil,
            ],
            role: .recipient(myIndex: 1),
            claimedUris: [uriA],
            anyClaimed: true
        )
        XCTAssertNil(targets.rejectUri)
    }

    func testNotAParticipantYieldsNone() {
        let targets = TalerMenuState.compute(
            uris: [uriA, uriB],
            records: [
                record(uriA, status: .offen, isOwnPayment: true),
                record(uriB, status: .offen, isOwnPayment: true),
            ],
            role: .notAParticipant,
            claimedUris: [],
            anyClaimed: false
        )
        XCTAssertEqual(targets, .none)
    }

    func testClaimedAcceptedShareIsRefundable() {
        let targets = TalerMenuState.compute(
            uris: [uriA, uriB],
            records: [
                record(uriA, status: .angenommen, isOwnPayment: false),
                record(uriB, status: .offen, isOwnPayment: true),
            ],
            role: .recipient(myIndex: 0),
            claimedUris: [uriA],
            anyClaimed: true
        )
        XCTAssertEqual(targets.refundUris, [uriA])
        XCTAssertFalse(targets.showCancel)
    }
}
