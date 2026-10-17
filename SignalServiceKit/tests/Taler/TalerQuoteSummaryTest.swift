//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// `TalerQuoteSummary.build` nach `TalerQuoteSummary.kt` (signal-android):
/// nil ohne Taler-URI, Betrag ausschliesslich aus dem Record (Regel 5),
/// mehrere URIs (Gruppen-Split) als Zusammenfassung mit Anzahl. Vergleiche
/// gegen `TalerStrings` selbst, damit die Tests nicht von konkreten
/// Uebersetzungen abhaengen.
final class TalerQuoteSummaryTest: XCTestCase {

    private let uriA = "taler://pay-push/exchange.example/AAA"
    private let uriB = "taler://pay-push/exchange.example/BBB"

    private func record(
        _ uri: String,
        amount: String? = "5.00",
        currency: String? = "KUDOS"
    ) -> TalerPaymentRecord {
        TalerPaymentRecord(
            uri: uri,
            threadUniqueId: "t1",
            uriKind: .payPush,
            status: .angenommen,
            amount: amount,
            currency: currency,
            createdAt: 1,
            isOwnPayment: true
        )
    }

    // MARK: - Keine Taler-Zahlung

    func testNoUrisYieldsNil() {
        XCTAssertNil(TalerQuoteSummary.build(uris: [], records: []))
    }

    // MARK: - Einzel-URI mit Betrag

    func testSingleWithAmountContainsTitleAndAmount() {
        let summary = TalerQuoteSummary.build(uris: [uriA], records: [record(uriA)])
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.hasPrefix(TalerStrings.quoteTitle))
        XCTAssertTrue(summary!.contains(TalerCardModel.formatAmount("5.00")))
        XCTAssertTrue(summary!.contains("KUDOS"))
        XCTAssertTrue(summary!.contains("·"))
        // Die URI darf im Zitat nie auftauchen (Regel 4).
        XCTAssertFalse(summary!.contains("taler://"))
    }

    // MARK: - Einzel-URI ohne Betrag (nur Titel, kein Trennzeichen)

    func testSingleWithoutRecordYieldsTitleOnly() {
        XCTAssertEqual(TalerQuoteSummary.build(uris: [uriA], records: [nil]), TalerStrings.quoteTitle)
    }

    func testSingleWithRecordButNoAmountYieldsTitleOnly() {
        XCTAssertEqual(
            TalerQuoteSummary.build(uris: [uriA], records: [record(uriA, amount: nil)]),
            TalerStrings.quoteTitle
        )
        XCTAssertEqual(
            TalerQuoteSummary.build(uris: [uriA], records: [record(uriA, amount: "")]),
            TalerStrings.quoteTitle
        )
    }

    func testSingleWithoutCurrencyShowsAmountOnly() {
        let summary = TalerQuoteSummary.build(uris: [uriA], records: [record(uriA, currency: nil)])
        XCTAssertTrue(summary!.hasSuffix(TalerCardModel.formatAmount("5.00")))
        XCTAssertFalse(summary!.contains("·  "))
    }

    // MARK: - Gruppe (mehrere URIs)

    func testGroupYieldsGroupSummaryFormat() {
        let summary = TalerQuoteSummary.build(
            uris: [uriA, uriB],
            records: [record(uriA), record(uriB)]
        )
        XCTAssertEqual(summary, String(format: TalerStrings.quoteGroupSummaryFormat, 2))
        XCTAssertFalse(summary!.contains("taler://"))
    }
}
