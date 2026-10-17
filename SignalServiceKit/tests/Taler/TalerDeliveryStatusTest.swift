//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// `TalerDeliveryStatus.compute` nach `TalerDeliveryStatusPresenter.kt`
/// (signal-android): nil ohne Taler-URI, "bezahlt" nur wenn ALLE URIs
/// angenommen sind, sonst "offen" - inklusive fehlender Records.
final class TalerDeliveryStatusTest: XCTestCase {

    private let uriA = "taler://pay-push/exchange.example/AAA"
    private let uriB = "taler://pay-push/exchange.example/BBB"

    private func record(
        _ uri: String,
        status: TalerPaymentStatus,
        isOwnPayment: Bool = true,
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

    // MARK: - Keine Taler-Zahlung

    func testNoUrisYieldsNil() {
        XCTAssertNil(TalerDeliveryStatus.compute(uris: [], records: []))
    }

    // MARK: - Einzel-URI

    func testSingleAcceptedIsPaid() {
        XCTAssertEqual(
            TalerDeliveryStatus.compute(uris: [uriA], records: [record(uriA, status: .angenommen)]),
            .paid
        )
    }

    func testSingleOpenIsOpen() {
        XCTAssertEqual(
            TalerDeliveryStatus.compute(uris: [uriA], records: [record(uriA, status: .offen)]),
            .open
        )
    }

    func testSingleExpiredIsOpen() {
        XCTAssertEqual(
            TalerDeliveryStatus.compute(uris: [uriA], records: [record(uriA, status: .abgelaufen)]),
            .open
        )
    }

    func testMissingRecordCountsAsNotAccepted() {
        XCTAssertEqual(TalerDeliveryStatus.compute(uris: [uriA], records: [nil]), .open)
    }

    // MARK: - Gruppe (mehrere URIs)

    func testGroupAllAcceptedIsPaid() {
        XCTAssertEqual(
            TalerDeliveryStatus.compute(
                uris: [uriA, uriB],
                records: [record(uriA, status: .angenommen), record(uriB, status: .angenommen)]
            ),
            .paid
        )
    }

    func testGroupOneOpenIsOpen() {
        XCTAssertEqual(
            TalerDeliveryStatus.compute(
                uris: [uriA, uriB],
                records: [record(uriA, status: .angenommen), record(uriB, status: .offen)]
            ),
            .open
        )
    }

    func testGroupOneMissingRecordIsOpen() {
        XCTAssertEqual(
            TalerDeliveryStatus.compute(
                uris: [uriA, uriB],
                records: [record(uriA, status: .angenommen), nil]
            ),
            .open
        )
    }

    /// Defensiv: unvollstaendige Record-Liste darf nie "bezahlt" ergeben.
    func testGroupShortRecordListIsOpen() {
        XCTAssertEqual(
            TalerDeliveryStatus.compute(uris: [uriA, uriB], records: [record(uriA, status: .angenommen)]),
            .open
        )
        XCTAssertEqual(TalerDeliveryStatus.compute(uris: [uriA, uriB], records: []), .open)
    }
}
