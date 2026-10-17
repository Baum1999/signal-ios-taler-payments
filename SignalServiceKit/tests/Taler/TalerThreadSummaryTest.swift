//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// `TalerThreadAggregate`/`TalerThreadHeadline`/`TalerThreadFilter`/
/// `TalerThreadSummaryFormat` sind die reine Rechenschicht hinter der
/// Kopfzeile des Taler-Tabs - bewusst ohne UIKit, damit genau die Faelle
/// testbar sind, die die Kopfzeile bestimmen (wer ist dran, was war zuletzt,
/// wie steht der Saldo). Faelle nach `TalerThreadSummaryTest.kt`
/// (signal-android), plus `statusChangedAt` (S2), Filter und Formatierung.
final class TalerThreadSummaryTest: XCTestCase {

    private var nextUri = 0

    private func record(
        status: TalerPaymentStatus,
        isOwnPayment: Bool = false,
        amount: String? = nil,
        currency: String? = nil,
        exchangeBaseUrl: String? = nil,
        summary: String? = nil,
        createdAt: Int64 = 0,
        lastCheckedAt: Int64? = nil,
        statusChangedAt: Int64? = nil,
        uri: String? = nil
    ) -> TalerPaymentRecord {
        nextUri += 1
        return TalerPaymentRecord(
            uri: uri ?? "taler://pay-push/exchange.test/key\(nextUri)",
            threadUniqueId: "t",
            uriKind: .payPush,
            status: status,
            amount: amount,
            currency: currency,
            exchangeBaseUrl: exchangeBaseUrl,
            summary: summary,
            createdAt: createdAt,
            lastCheckedAt: lastCheckedAt,
            statusChangedAt: statusChangedAt,
            isOwnPayment: isOwnPayment
        )
    }

    private let de = Locale(identifier: "de_DE")

    // MARK: - Aggregat

    func testBuildEmptyListIsAllZero() {
        let result = TalerThreadAggregate.build([])

        XCTAssertEqual(0, result.total)
        XCTAssertEqual(0, result.openForMe)
        XCTAssertEqual(0, result.openForOther)
        XCTAssertEqual(0, result.unverifiable)
        XCTAssertEqual(nil, result.latest)
        XCTAssertEqual([], result.balances)
        XCTAssertEqual([], result.exchanges)
        XCTAssertEqual(nil, result.lastCheckedAt)
    }

    func testBuildSplitsOpenByWhoMustAct() {
        let result = TalerThreadAggregate.build([
            record(status: .offen, isOwnPayment: false),
            record(status: .offen, isOwnPayment: false),
            record(status: .offen, isOwnPayment: true),
            record(status: .angenommen, isOwnPayment: true),
        ])

        XCTAssertEqual(4, result.total)
        XCTAssertEqual(2, result.openForMe)
        XCTAssertEqual(1, result.openForOther)
        XCTAssertEqual(0, result.unverifiable)
    }

    func testBuildBalanceSplitsAcceptedByDirection() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: false, amount: "12.50", currency: "KUDOS"),
            record(status: .angenommen, isOwnPayment: false, amount: "5.00", currency: "KUDOS"),
            record(status: .angenommen, isOwnPayment: true, amount: "4.00", currency: "KUDOS"),
        ])

        XCTAssertEqual(
            [TalerCurrencyBalance(currency: "KUDOS", inflow: 17.50 as Decimal, outflow: 4.00 as Decimal)],
            result.balances
        )
    }

    func testBuildBalanceIgnoresEverythingButAccepted() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, amount: "5.00", currency: "KUDOS"),
            record(status: .offen, amount: "99.00", currency: "KUDOS"),
            record(status: .lokalAbgelehnt, amount: "99.00", currency: "KUDOS"),
            record(status: .lokalAbgebrochen, amount: "99.00", currency: "KUDOS"),
            record(status: .abgelaufen, amount: "99.00", currency: "KUDOS"),
            record(status: .ungueltig, amount: "99.00", currency: "KUDOS"),
            record(status: .unbekanntOffline, amount: "99.00", currency: "KUDOS"),
        ])

        XCTAssertEqual(
            [TalerCurrencyBalance(currency: "KUDOS", inflow: 5.00 as Decimal, outflow: 0 as Decimal)],
            result.balances
        )
    }

    func testBuildBalanceIgnoresInvalidAmountsButKeepsTheCurrency() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, amount: "12,50", currency: "KUDOS"),
            record(status: .angenommen, amount: "abc", currency: "KUDOS"),
            record(status: .angenommen, amount: nil, currency: "KUDOS"),
        ])

        XCTAssertEqual(
            [TalerCurrencyBalance(currency: "KUDOS", inflow: 0 as Decimal, outflow: 0 as Decimal)],
            result.balances
        )
    }

    func testBuildBalanceWithoutCurrencyIsSkipped() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, amount: "5.00", currency: nil),
            record(status: .angenommen, amount: "5.00", currency: ""),
        ])

        XCTAssertEqual([], result.balances)
    }

    func testBuildKeepsCurrenciesApartSortedByAbsoluteNet() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: true, amount: "3.00", currency: "EUR"),
            record(status: .angenommen, isOwnPayment: false, amount: "12.50", currency: "KUDOS"),
            record(status: .angenommen, isOwnPayment: false, amount: "2.00", currency: "CHF"),
        ])

        XCTAssertEqual(
            [
                TalerCurrencyBalance(currency: "KUDOS", inflow: 12.50 as Decimal, outflow: 0 as Decimal),
                TalerCurrencyBalance(currency: "EUR", inflow: 0 as Decimal, outflow: 3.00 as Decimal),
                TalerCurrencyBalance(currency: "CHF", inflow: 2.00 as Decimal, outflow: 0 as Decimal),
            ],
            result.balances
        )
    }

    func testBuildBalanceTieBreaksByCurrencyName() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: true, amount: "5.00", currency: "EUR"),
            record(status: .angenommen, isOwnPayment: false, amount: "5.00", currency: "CHF"),
        ])

        XCTAssertEqual(
            ["CHF", "EUR"],
            result.balances.map { $0.currency }
        )
    }

    // MARK: - Letzter Vorgang

    func testLatestIsNewestByCreatedAt() {
        let newest = record(status: .offen, summary: "Pizza", createdAt: 300)

        let result = TalerThreadAggregate.build([
            record(status: .angenommen, createdAt: 100),
            newest,
            record(status: .angenommen, createdAt: 200),
        ])

        XCTAssertEqual(newest, result.latest)
    }

    func testLatestUsesStatusChangedAtOverNewerRecognition() {
        // Juengere Erkennung (createdAt 900) ohne Statuswechsel verliert gegen
        // einen frischen Statuswechsel (createdAt 100, statusChangedAt 950).
        let settledLate = record(status: .angenommen, createdAt: 100, statusChangedAt: 950)
        let detectedLater = record(status: .unbekanntOffline, createdAt: 900)

        XCTAssertEqual(settledLate, TalerThreadAggregate.build([detectedLater, settledLate]).latest)
        XCTAssertEqual(settledLate, TalerThreadAggregate.build([settledLate, detectedLater]).latest)
    }

    func testLatestTieBreaksByLargerCreatedAt() {
        // Gleiche latestActivityAt (200): der juenger erkannte Vorgang gewinnt.
        let a = record(status: .offen, createdAt: 200, uri: "taler://pay-push/e/aaa")
        let b = record(status: .angenommen, createdAt: 100, statusChangedAt: 200, uri: "taler://pay-push/e/bbb")

        XCTAssertEqual(a, TalerThreadAggregate.build([a, b]).latest)
        XCTAssertEqual(a, TalerThreadAggregate.build([b, a]).latest)
    }

    func testLatestTieBreaksByUriSoOrderOfRowsDoesNotMatter() {
        let a = record(status: .offen, createdAt: 100, uri: "taler://pay-push/e/aaa")
        let b = record(status: .offen, createdAt: 100, uri: "taler://pay-push/e/bbb")

        XCTAssertEqual(b, TalerThreadAggregate.build([a, b]).latest)
        XCTAssertEqual(b, TalerThreadAggregate.build([b, a]).latest)
    }

    // MARK: - Exchanges und lastCheckedAt

    func testExchangesAreDistinctHostsInOrderOfFirstOccurrence() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, exchangeBaseUrl: "https://exchange.demo.taler.net/"),
            record(status: .offen, exchangeBaseUrl: "https://exchange.demo.taler.net/"),
            record(status: .offen, exchangeBaseUrl: "https://bank.example.org/sub/"),
            record(status: .unbekanntOffline, exchangeBaseUrl: nil),
            record(status: .offen, exchangeBaseUrl: "not a url"),
        ])

        XCTAssertEqual(["exchange.demo.taler.net", "bank.example.org"], result.exchanges)
    }

    func testLastCheckedAtIsTheMostRecentCheck() {
        let result = TalerThreadAggregate.build([
            record(status: .offen, lastCheckedAt: 500),
            record(status: .offen, lastCheckedAt: nil),
            record(status: .offen, lastCheckedAt: 900),
        ])

        XCTAssertEqual(Int64(900), result.lastCheckedAt)
    }

    func testCountsOnlyOfflineAsUnverifiable() {
        let result = TalerThreadAggregate.build([
            record(status: .unbekanntOffline),
            record(status: .unbekanntOffline),
            record(status: .ungueltig),
            record(status: .angenommen),
            record(status: .abgelaufen),
        ])

        XCTAssertEqual(2, result.unverifiable)
    }

    // MARK: - Kopfzeilen-Rangfolge

    private func headlineFor(_ records: [TalerPaymentRecord]) -> TalerThreadHeadline {
        TalerThreadHeadline.from(TalerThreadAggregate.build(records))
    }

    func testHeadlineNoRecordsIsEmpty() {
        XCTAssertEqual(.empty, headlineFor([]))
    }

    func testHeadlineOnlyIncomingOpenAsksTheUserToAct() {
        XCTAssertEqual(
            .waitingForMe(2),
            headlineFor([
                record(status: .offen, isOwnPayment: false),
                record(status: .offen, isOwnPayment: false),
                record(status: .angenommen),
            ])
        )
    }

    func testHeadlineOnlyOutgoingOpenWaitsForTheOtherSide() {
        XCTAssertEqual(
            .waitingForOther(1),
            headlineFor([
                record(status: .offen, isOwnPayment: true),
                record(status: .angenommen),
            ])
        )
    }

    func testHeadlineOpenOnBothSidesNamesBothCounts() {
        XCTAssertEqual(
            .waitingForBoth(forMe: 1, forOther: 2),
            headlineFor([
                record(status: .offen, isOwnPayment: false),
                record(status: .offen, isOwnPayment: true),
                record(status: .offen, isOwnPayment: true),
            ])
        )
    }

    func testHeadlineOpenBeatsUnverifiable() {
        XCTAssertEqual(
            .waitingForMe(1),
            headlineFor([
                record(status: .offen, isOwnPayment: false),
                record(status: .unbekanntOffline),
                record(status: .unbekanntOffline),
            ])
        )
    }

    func testHeadlineUnverifiableBeatsAllSettled() {
        XCTAssertEqual(
            .unverifiable(1),
            headlineFor([
                record(status: .angenommen),
                record(status: .abgelaufen),
                record(status: .unbekanntOffline),
            ])
        )
    }

    func testHeadlineNothingPendingReportsTheTotal() {
        XCTAssertEqual(
            .allSettled(3),
            headlineFor([
                record(status: .angenommen),
                record(status: .abgelaufen),
                record(status: .lokalAbgelehnt),
            ])
        )
    }

    // MARK: - Filter-Chips

    func testFilterCases() {
        XCTAssertEqual(4, TalerThreadFilter.allCases.count)
    }

    func testFilterAllMatchesEverything() {
        let records = [
            record(status: .offen, isOwnPayment: false),
            record(status: .angenommen, isOwnPayment: true),
            record(status: .unbekanntOffline),
        ]
        XCTAssertTrue(records.allSatisfy { TalerThreadFilter.all.matches($0) })
    }

    func testFilterOpenMatchesOnlyOpenStatus() {
        XCTAssertTrue(TalerThreadFilter.open.matches(record(status: .offen, isOwnPayment: false)))
        XCTAssertTrue(TalerThreadFilter.open.matches(record(status: .offen, isOwnPayment: true)))
        XCTAssertFalse(TalerThreadFilter.open.matches(record(status: .angenommen)))
        XCTAssertFalse(TalerThreadFilter.open.matches(record(status: .unbekanntOffline)))
    }

    func testFilterReceivedAndSentSplitByDirection() {
        let incoming = record(status: .angenommen, isOwnPayment: false)
        let outgoing = record(status: .angenommen, isOwnPayment: true)

        XCTAssertTrue(TalerThreadFilter.received.matches(incoming))
        XCTAssertFalse(TalerThreadFilter.received.matches(outgoing))
        XCTAssertFalse(TalerThreadFilter.sent.matches(incoming))
        XCTAssertTrue(TalerThreadFilter.sent.matches(outgoing))
    }

    // MARK: - Kontextzeile (Saldo)

    func testContextLineShowsLargestBalanceAndHost() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: false, amount: "12.50", currency: "KUDOS", exchangeBaseUrl: "https://exchange.demo.taler.net/"),
            record(status: .angenommen, isOwnPayment: true, amount: "4.00", currency: "KUDOS", exchangeBaseUrl: "https://exchange.demo.taler.net/"),
        ])

        XCTAssertEqual("+8,50 KUDOS · exchange.demo.taler.net", TalerThreadSummaryFormat.contextLine(result, locale: de))
    }

    func testContextLineMarksOutflowWithMinus() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: true, amount: "4.00", currency: "KUDOS"),
        ])

        XCTAssertEqual("-4,00 KUDOS", TalerThreadSummaryFormat.contextLine(result, locale: de))
    }

    func testContextLineOmitsZeroBalanceEvenWithExchanges() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: false, amount: "4.00", currency: "KUDOS", exchangeBaseUrl: "https://exchange.demo.taler.net/"),
            record(status: .angenommen, isOwnPayment: true, amount: "4.00", currency: "KUDOS", exchangeBaseUrl: "https://exchange.demo.taler.net/"),
        ])

        XCTAssertNil(TalerThreadSummaryFormat.contextLine(result, locale: de))
    }

    func testContextLineCapsAtTwoCurrenciesAndCountsTheRest() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: false, amount: "9.00", currency: "AAA"),
            record(status: .angenommen, isOwnPayment: false, amount: "6.00", currency: "BBB"),
            record(status: .angenommen, isOwnPayment: false, amount: "3.00", currency: "CCC"),
            record(status: .angenommen, isOwnPayment: false, amount: "1.00", currency: "DDD"),
        ])

        XCTAssertEqual("+9,00 AAA · +6,00 BBB · +2", TalerThreadSummaryFormat.contextLine(result, locale: de))
    }

    func testContextLineNamesCountForMultipleExchanges() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: false, amount: "1.00", currency: "KUDOS", exchangeBaseUrl: "https://exchange.demo.taler.net/"),
            record(status: .angenommen, isOwnPayment: false, amount: "1.00", currency: "KUDOS", exchangeBaseUrl: "https://bank.example.org/"),
            record(status: .angenommen, isOwnPayment: false, amount: "1.00", currency: "KUDOS", exchangeBaseUrl: "https://other.example.org/"),
        ])

        XCTAssertEqual(
            "+3,00 KUDOS · " + String(format: TalerStrings.exchangeCountFormat, 3),
            TalerThreadSummaryFormat.contextLine(result, locale: de)
        )
    }

    func testContextLineWithoutExchangeOmitsHost() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: false, amount: "5.00", currency: "KUDOS", exchangeBaseUrl: nil),
        ])

        XCTAssertEqual("+5,00 KUDOS", TalerThreadSummaryFormat.contextLine(result, locale: de))
    }

    func testContextLineOnEmptyAggregateIsNil() {
        XCTAssertNil(TalerThreadSummaryFormat.contextLine(TalerThreadAggregate.build([]), locale: de))
    }

    // MARK: - Zeile "Letzter Vorgang"

    func testLatestLinePartsAmountDirectionSummary() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: false, amount: "5.00", currency: "KUDOS", summary: "Pizza", createdAt: 100),
        ])

        XCTAssertEqual(
            ["5,00 KUDOS", "erhalten", "Pizza"],
            TalerThreadSummaryFormat.latestLineParts(result, receivedLabel: "erhalten", sentLabel: "gesendet", locale: de)
        )
    }

    func testLatestLineUsesSentLabelForOwnPayments() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: true, amount: "5.00", currency: "KUDOS", summary: "Pizza", createdAt: 100),
        ])

        XCTAssertEqual(
            ["5,00 KUDOS", "gesendet", "Pizza"],
            TalerThreadSummaryFormat.latestLineParts(result, receivedLabel: "erhalten", sentLabel: "gesendet", locale: de)
        )
    }

    func testLatestLineOmitsMissingAmountCurrencyAndEmptySummary() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: false, amount: nil, currency: nil, summary: "  ", createdAt: 100),
        ])

        XCTAssertEqual(
            ["erhalten"],
            TalerThreadSummaryFormat.latestLineParts(result, receivedLabel: "erhalten", sentLabel: "gesendet", locale: de)
        )
    }

    func testLatestLineOmitsInvalidAmount() {
        let result = TalerThreadAggregate.build([
            record(status: .angenommen, isOwnPayment: false, amount: "12,50", currency: "KUDOS", summary: "Pizza", createdAt: 100),
        ])

        XCTAssertEqual(
            ["erhalten", "Pizza"],
            TalerThreadSummaryFormat.latestLineParts(result, receivedLabel: "erhalten", sentLabel: "gesendet", locale: de)
        )
    }

    func testLatestLineOnEmptyAggregateIsEmpty() {
        XCTAssertEqual(
            [],
            TalerThreadSummaryFormat.latestLineParts(TalerThreadAggregate.build([]), receivedLabel: "erhalten", sentLabel: "gesendet", locale: de)
        )
    }
}
