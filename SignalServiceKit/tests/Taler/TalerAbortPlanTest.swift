//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// TalerAbortPlan (S10, Gap A): betroffene URIs nur nach dem Abbruch-Gate
/// (`TalerCardActionGate.showCancel`: eigene, offene pay-push), Dubletten und
/// Record-lose URIs fallen heraus; Ergebnis-Mapping des Ruecksprungs nur fuer
/// erlaubte URIs (Ziel-Validierung), `already_claimed`/`declined` erzwingen
/// keinen Status.
final class TalerAbortPlanTest: XCTestCase {

    private func makeRecord(uri: String,
                            status: TalerPaymentStatus,
                            isOwn: Bool,
                            kind: TalerUriKind? = .payPush) -> TalerPaymentRecord {
        TalerPaymentRecord(
            uri: uri,
            threadUniqueId: "thread",
            uriKind: kind,
            status: status,
            createdAt: 1,
            isOwnPayment: isOwn
        )
    }

    // MARK: - affectedUris

    func testAffectedUrisKeepsOnlyOwnOpenPayPush() {
        let ownOpen = makeRecord(uri: "taler://pay-push/ex/OWN-OPEN", status: .offen, isOwn: true)
        let foreignOpen = makeRecord(uri: "taler://pay-push/ex/FOREIGN-OPEN", status: .offen, isOwn: false)
        let ownAccepted = makeRecord(uri: "taler://pay-push/ex/OWN-DONE", status: .angenommen, isOwn: true)
        let ownOpenPull = makeRecord(uri: "taler://pay-pull/ex/OWN-PULL", status: .offen, isOwn: true, kind: .payPull)
        let ownOpenUnknownKind = makeRecord(uri: "taler://pay-push/ex/OWN-KINDLESS", status: .offen, isOwn: true, kind: nil)

        let uris = TalerAbortPlan.affectedUris(records: [ownOpen, foreignOpen, ownAccepted, ownOpenPull, ownOpenUnknownKind, nil])

        XCTAssertEqual(uris, ["taler://pay-push/ex/OWN-OPEN"])
    }

    func testAffectedUrisDeduplicatesAndKeepsOrder() {
        let first = makeRecord(uri: "taler://pay-push/ex/A", status: .offen, isOwn: true)
        let second = makeRecord(uri: "taler://pay-push/ex/B", status: .offen, isOwn: true)

        let uris = TalerAbortPlan.affectedUris(records: [first, second, first])

        XCTAssertEqual(uris, ["taler://pay-push/ex/A", "taler://pay-push/ex/B"])
    }

    func testAffectedUrisWithEmptyInputIsEmpty() {
        XCTAssertEqual(TalerAbortPlan.affectedUris(records: []), [])
        XCTAssertEqual(TalerAbortPlan.affectedUris(records: [nil, nil]), [])
    }

    // MARK: - apply

    func testApplyMapsAllOutcomes() {
        let updates = TalerAbortPlan.apply(
            results: [
                TalerAbortResult(uri: "taler://pay-push/ex/A", outcome: .aborted),
                TalerAbortResult(uri: "taler://pay-push/ex/B", outcome: .expired),
                TalerAbortResult(uri: "taler://pay-push/ex/C", outcome: .alreadyClaimed),
                TalerAbortResult(uri: "taler://pay-push/ex/D", outcome: .declined),
            ],
            allowed: ["taler://pay-push/ex/A", "taler://pay-push/ex/B", "taler://pay-push/ex/C", "taler://pay-push/ex/D"]
        )

        // Arrays von Tupeln sind nicht Equatable: URIs und Status getrennt pruefen.
        XCTAssertEqual(updates.map(\.uri), [
            "taler://pay-push/ex/A",
            "taler://pay-push/ex/B",
            "taler://pay-push/ex/C",
            "taler://pay-push/ex/D",
        ])
        XCTAssertEqual(updates.map(\.status), [.ungueltig, .abgelaufen, nil, nil])
    }

    func testApplyDropsUrisOutsideAllowedList() {
        let updates = TalerAbortPlan.apply(
            results: [
                TalerAbortResult(uri: "taler://pay-push/ex/FOREIGN", outcome: .aborted),
                TalerAbortResult(uri: "taler://pay-push/ex/A", outcome: .aborted),
            ],
            allowed: ["taler://pay-push/ex/A"]
        )

        XCTAssertEqual(updates.map(\.uri), ["taler://pay-push/ex/A"])
        XCTAssertEqual(updates.first?.status, .ungueltig)
    }

    func testApplyWithEmptyAllowedListDropsEverything() {
        let updates = TalerAbortPlan.apply(
            results: [TalerAbortResult(uri: "taler://pay-push/ex/A", outcome: .aborted)],
            allowed: []
        )
        XCTAssertTrue(updates.isEmpty)
    }

    func testApplyKeepsResultOrderNotAllowedOrder() {
        let updates = TalerAbortPlan.apply(
            results: [
                TalerAbortResult(uri: "taler://pay-push/ex/B", outcome: .aborted),
                TalerAbortResult(uri: "taler://pay-push/ex/A", outcome: .expired),
            ],
            allowed: ["taler://pay-push/ex/A", "taler://pay-push/ex/B"]
        )

        XCTAssertEqual(updates.map(\.uri), ["taler://pay-push/ex/B", "taler://pay-push/ex/A"])
        XCTAssertEqual(updates.map(\.status), [.ungueltig, .abgelaufen])
    }
}
