//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Darstellungslogik der Karte und `TalerCardActionGate` (Faelle nach
/// `TalerCardActionGateTest.kt` und `TalerPaymentCardPresenter`).
final class TalerCardModelTest: XCTestCase {

    private func record(kind: TalerUriKind = .payPush, status: TalerPaymentStatus, own: Bool, exchange: String? = "https://exchange.example/") -> TalerPaymentRecord {
        TalerPaymentRecord(uri: "taler://pay-push/e/A", threadUniqueId: "t", uriKind: kind, status: status, amount: "12.5", currency: "KUDOS", exchangeBaseUrl: exchange, summary: "Pizza", createdAt: 0, isOwnPayment: own)
    }

    func testDirectionTruthTable() {
        XCTAssertTrue(TalerCardModel.isDirectionIn(kind: .payPush, isOwnPayment: false))
        XCTAssertFalse(TalerCardModel.isDirectionIn(kind: .payPush, isOwnPayment: true))
        XCTAssertFalse(TalerCardModel.isDirectionIn(kind: .payPull, isOwnPayment: false))
        XCTAssertTrue(TalerCardModel.isDirectionIn(kind: .payPull, isOwnPayment: true))
    }

    func testAmountAndCurrencyFormatting() {
        XCTAssertEqual(TalerCardModel.formatAmount("12.5"), "12,5")
        XCTAssertEqual(TalerCardModel.formatAmount(nil), "0")
        XCTAssertEqual(TalerCardModel.currencySymbol("KUDOS"), "ク")
        XCTAssertEqual(TalerCardModel.currencySymbol("EUR"), "€")
        XCTAssertEqual(TalerCardModel.currencySymbol("CHF"), "CHF")
        XCTAssertEqual(TalerCardModel.currencySymbol(nil), "")
    }

    func testDisplayHostHidesNonAscii() {
        XCTAssertEqual(TalerCardModel.displayHost("https://exchange.example/sub/"), "exchange.example")
        XCTAssertNil(TalerCardModel.displayHost(nil))
        XCTAssertNil(TalerCardModel.displayHost("not a url"))
    }

    func testAcceptOnlyForForeignOpenPayPush() {
        XCTAssertTrue(TalerCardActionGate.showAccept(record(status: .offen, own: false)))
        XCTAssertFalse(TalerCardActionGate.showAccept(record(status: .offen, own: true)))
        XCTAssertFalse(TalerCardActionGate.showAccept(record(kind: .payPull, status: .offen, own: false)))
        XCTAssertFalse(TalerCardActionGate.showAccept(record(status: .angenommen, own: false)))
        XCTAssertFalse(TalerCardActionGate.showAccept(nil))
    }

    func testCancelOnlyForOwnOpenPayPush() {
        XCTAssertTrue(TalerCardActionGate.showCancel(record(status: .offen, own: true)))
        XCTAssertFalse(TalerCardActionGate.showCancel(record(status: .offen, own: false)))
        XCTAssertFalse(TalerCardActionGate.showCancel(record(status: .angenommen, own: true)))
    }

    func testRefundOnlyForForeignAcceptedPayment() {
        XCTAssertTrue(TalerCardActionGate.showRefund(record(status: .angenommen, own: false)))
        XCTAssertTrue(TalerCardActionGate.showRefund(record(kind: .payPull, status: .angenommen, own: false)))
        XCTAssertFalse(TalerCardActionGate.showRefund(record(status: .angenommen, own: true)))
        XCTAssertFalse(TalerCardActionGate.showRefund(record(status: .offen, own: false)))
    }

    func testStatusTones() {
        XCTAssertEqual(TalerCardModel.build(record: record(status: .offen, own: false), otherPartyName: "Bob").statusTone, .waiting)
        XCTAssertEqual(TalerCardModel.build(record: record(status: .angenommen, own: true), otherPartyName: "Bob").statusTone, .ok)
        XCTAssertEqual(TalerCardModel.build(record: record(status: .abgelaufen, own: true), otherPartyName: nil).statusTone, .bad)
        XCTAssertEqual(TalerCardModel.build(record: nil, otherPartyName: nil).statusTone, .neutral)
        XCTAssertEqual(TalerCardModel.build(record: nil, otherPartyName: nil).statusIcon, "…")
    }

    func testCardFieldsForIncomingPayment() {
        let model = TalerCardModel.build(record: record(status: .offen, own: false), otherPartyName: "Bob")
        XCTAssertTrue(model.directionIn)
        XCTAssertEqual(model.amountText, "12,5")
        XCTAssertEqual(model.currencySymbol, "ク")
        XCTAssertEqual(model.summary, "Pizza")
        XCTAssertEqual(model.exchangeHost, "exchange.example")
        XCTAssertTrue(model.showAccept)
    }

    func testAmountPlaceholderWhenNoVerifiedAmount() {
        // Regel 5: ohne verifizierten Betrag ein Platzhalter, nie Text aus
        // dem Body - und niemals eine Zahl, die wie ein Betrag aussieht.
        XCTAssertEqual(TalerCardModel.build(record: nil, otherPartyName: nil).amountText, TalerStrings.amountPending)
        let noAmount = TalerPaymentRecord(uri: "u", threadUniqueId: "t", uriKind: .payPush, status: .unbekanntOffline, createdAt: 0, isOwnPayment: false)
        XCTAssertEqual(TalerCardModel.build(record: noAmount, otherPartyName: nil).amountText, TalerStrings.amountPending)
    }

    // MARK: - Gruppen-Split (reine Logik, Faelle nach GroupSplitCard.kt)

    func testRecipientAcisAreSortedAndExcludeSender() {
        XCTAssertEqual(TalerGroupSplit.recipientAcis(memberAcis: ["C", "A", "B", "S"], senderAci: "S"), ["A", "B", "C"])
    }

    func testResolveRole() {
        XCTAssertEqual(TalerGroupSplit.resolveRole(recipientAcis: ["A", "B", "C"], senderAci: "S", myAci: "S"), .creator)
        XCTAssertEqual(TalerGroupSplit.resolveRole(recipientAcis: ["A", "B", "C"], senderAci: "S", myAci: "B"), .recipient(myIndex: 1))
        XCTAssertEqual(TalerGroupSplit.resolveRole(recipientAcis: ["A", "B", "C"], senderAci: "S", myAci: "X"), .notAParticipant)
        // Ohne bekannte Empfaengerliste (z.B. kein Gruppen-Thread) nur der
        // Ersteller selbst hat eine Rolle.
        XCTAssertEqual(TalerGroupSplit.resolveRole(recipientAcis: nil, senderAci: "S", myAci: "S"), .creator)
        XCTAssertEqual(TalerGroupSplit.resolveRole(recipientAcis: nil, senderAci: "S", myAci: "B"), .notAParticipant)
    }

    func testResolveTargetUriPicksNextOpenShareFromOwnIndex() {
        let uris = ["u0", "u1", "u2"]
        // Eigener Anteil offen.
        XCTAssertEqual(TalerGroupSplit.resolveTargetUri(uris: uris, statuses: [nil, nil, nil], startIndex: 1), "u1")
        // Eigener Anteil angenommen: naechster offener mit Umlauf ab eigenem Index.
        XCTAssertEqual(TalerGroupSplit.resolveTargetUri(uris: uris, statuses: [.angenommen, .angenommen, .offen], startIndex: 1), "u2")
        XCTAssertEqual(TalerGroupSplit.resolveTargetUri(uris: uris, statuses: [.offen, .angenommen, .angenommen], startIndex: 1), "u0")
        // Status nil zaehlt als offen.
        XCTAssertEqual(TalerGroupSplit.resolveTargetUri(uris: uris, statuses: [.angenommen, nil, .angenommen], startIndex: 1), "u1")
        // Alles entschieden: kein Knopf.
        XCTAssertNil(TalerGroupSplit.resolveTargetUri(uris: uris, statuses: [.angenommen, .lokalAbgelehnt, .abgelaufen], startIndex: 0))
        XCTAssertNil(TalerGroupSplit.resolveTargetUri(uris: [], statuses: [], startIndex: 0))
    }

    func testCountAcceptedAndAnyOpen() {
        let statuses: [TalerPaymentStatus?] = [.angenommen, .offen, nil, .lokalAbgelehnt]
        XCTAssertEqual(TalerGroupSplit.countAccepted(statuses), 1)
        XCTAssertTrue(TalerGroupSplit.anyOpen(statuses))
        XCTAssertFalse(TalerGroupSplit.anyOpen([.angenommen, .abgelaufen]))
    }

    func testComputeVerifiedTotal() {
        // Ohne Selbst: N Anteile.
        XCTAssertEqual(TalerGroupSplit.computeVerifiedTotal(totalAmount: "30", includeSelf: false, uriCount: 3, perShareAmount: "10"), Decimal(string: "30"))
        // Mit Selbst: N+1 Anteile.
        XCTAssertEqual(TalerGroupSplit.computeVerifiedTotal(totalAmount: "40", includeSelf: true, uriCount: 3, perShareAmount: "10"), Decimal(string: "40"))
        // Abrunden auf 8 Stellen: Differenz bleibt unter der Toleranz 1e-6.
        XCTAssertEqual(TalerGroupSplit.computeVerifiedTotal(totalAmount: "1", includeSelf: false, uriCount: 3, perShareAmount: "0.33333333"), Decimal(string: "1"))
        // Manipulierte Summe: fail-safe nil.
        XCTAssertNil(TalerGroupSplit.computeVerifiedTotal(totalAmount: "99", includeSelf: false, uriCount: 3, perShareAmount: "10"))
        // Fehlende Angaben: nil.
        XCTAssertNil(TalerGroupSplit.computeVerifiedTotal(totalAmount: nil, includeSelf: false, uriCount: 3, perShareAmount: "10"))
        XCTAssertNil(TalerGroupSplit.computeVerifiedTotal(totalAmount: "30", includeSelf: nil, uriCount: 3, perShareAmount: "10"))
        XCTAssertNil(TalerGroupSplit.computeVerifiedTotal(totalAmount: "30", includeSelf: false, uriCount: 3, perShareAmount: nil))
        XCTAssertNil(TalerGroupSplit.computeVerifiedTotal(totalAmount: "30", includeSelf: false, uriCount: 0, perShareAmount: "10"))
        // Unparsbare Werte: nil.
        XCTAssertNil(TalerGroupSplit.computeVerifiedTotal(totalAmount: "30,5", includeSelf: false, uriCount: 3, perShareAmount: "10"))
        XCTAssertNil(TalerGroupSplit.computeVerifiedTotal(totalAmount: "30", includeSelf: false, uriCount: 3, perShareAmount: "abc"))
    }

    func testGroupClaimTrackerTracksOnlyOnce() {
        let suiteName = "TalerCardModelTest.GroupClaimTracker"
        UserDefaults().removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let tracker = TalerGroupClaimTracker(defaults: defaults)
        let uris = ["u0", "u1"]
        XCTAssertFalse(tracker.hasClaimedAny(uris))
        tracker.track("u1")
        XCTAssertTrue(tracker.hasClaimedAny(uris))
        XCTAssertEqual(tracker.claimedOf(uris), ["u1"])
        // Der zweite Anteil wird ueber DIESE Karte nicht mehr angeboten.
        tracker.track("u0")
        XCTAssertEqual(tracker.claimedOf(uris), ["u0", "u1"])
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}
