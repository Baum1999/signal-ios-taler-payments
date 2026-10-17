//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// TalerRefundPayload.build (S9, link-protokoll.md 4, 8): nur status=ready
/// legt einen ENTWURF an (kein automatisches Senden); Header "Refund: " VOR
/// dem Verwendungszweck, Leerzeile, dann die URIs (Android
/// TalerReturnActivity.kt, REFUND-Zweig); URI-Pruefung nur syntaktisch
/// (isExactlyOneUri, kein classify auf PAY_PUSH/PAY_PULL - der Nutzer sieht
/// den Entwurf vor dem Senden), sonst nichts - kein Teilentwurf; JSON vor
/// talerUri mit Rueckfall bei unparbarem JSON oder leerer Liste.
final class TalerRefundPayloadTest: XCTestCase {

    private let payPushUri = "taler://pay-push/exchange.example.org/AAAABBBB"
    private let payPushUri2 = "taler://pay-push/exchange.example.org/CCCCDDDD"
    private let payPullUri = "taler://pay-pull/exchange.example.org/AAAABBBB"

    private func makeReturn(
        status: TalerReturnStatus?,
        talerUri: String? = nil,
        talerPaymentData: String? = nil
    ) -> TalerReturn {
        TalerReturn(
            correlationId: "6f1c2a34-8b1e-4d7a-9c55-0e8f3b2a1d90",
            status: status,
            talerUri: talerUri,
            talerPaymentData: talerPaymentData,
            results: []
        )
    }

    /// Kompaktes TalerPaymentData-JSON (wie Taler es im Ruecksprung schickt).
    private func paymentDataJson(
        legacyText: String = TalerStrings.legacyText,
        uris: [String]
    ) -> String {
        let dict: [String: Any] = ["legacyText": legacyText, "uri": uris]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: ready, JSON-Pfad (Header vor Verwendungszweck)

    func testReadyWithJsonSingleUri() {
        let json = paymentDataJson(uris: [payPushUri])
        let body = TalerRefundPayload.build(from: makeReturn(status: .ready, talerPaymentData: json))
        XCTAssertEqual(
            body,
            "Refund: \(TalerStrings.legacyText)\n\n\(payPushUri)"
        )
    }

    func testReadyWithJsonAndTwoUris() {
        let uris = [payPushUri, payPushUri2]
        let legacy = "Purpose from Taler"
        let json = paymentDataJson(legacyText: legacy, uris: uris)
        let body = TalerRefundPayload.build(
            from: makeReturn(status: .ready, talerUri: payPushUri, talerPaymentData: json)
        )
        // JSON hat Vorrang vor talerUri; jede URI durch eine Leerzeile getrennt.
        XCTAssertEqual(body, "Refund: \(legacy)\n\n" + uris.joined(separator: "\n\n"))
    }

    // MARK: ready, Rueckfall talerUri (aeltere Taler-Versionen)

    func testReadyWithSinglePayPushUri() {
        let body = TalerRefundPayload.build(from: makeReturn(status: .ready, talerUri: payPushUri))
        XCTAssertEqual(body, "Refund: \(payPushUri)")
    }

    func testReadyWithSinglePayPullUri() {
        let body = TalerRefundPayload.build(from: makeReturn(status: .ready, talerUri: payPullUri))
        XCTAssertEqual(body, "Refund: \(payPullUri)")
    }

    // MARK: ungueltige URIs (nur syntaktisches Gate isExactlyOneUri)

    func testJsonWithOneInvalidUriDraftsNothing() {
        let json = paymentDataJson(uris: [payPushUri, "taler://pay-push/x taler://pay-pull/y"])
        XCTAssertNil(TalerRefundPayload.build(from: makeReturn(status: .ready, talerPaymentData: json)))
    }

    func testUriWithSurroundingTextDraftsNothing() {
        XCTAssertNil(TalerRefundPayload.build(
            from: makeReturn(status: .ready, talerUri: "pay taler://pay-push/ex/AAA")
        ))
    }

    func testWithdrawAndRefundUrisDoDraft() {
        // Im Entwurfspfad wird nur syntaktisch geprueft (kein classify auf
        // PAY_PUSH/PAY_PULL): WITHDRAW/REFUND-URIs legen ebenfalls einen
        // Entwurf an - der Nutzer prueft ihn vor dem Senden.
        let withdrawUri = "taler://withdraw/exchange.example.org/AAA"
        let refundUri = "taler://refund/exchange.example.org/AAA"
        let jsonBody = TalerRefundPayload.build(
            from: makeReturn(status: .ready, talerPaymentData: paymentDataJson(uris: [withdrawUri]))
        )
        XCTAssertEqual(jsonBody, "Refund: \(TalerStrings.legacyText)\n\n\(withdrawUri)")
        XCTAssertEqual(
            TalerRefundPayload.build(from: makeReturn(status: .ready, talerUri: refundUri)),
            "Refund: \(refundUri)"
        )
    }

    // MARK: status und fehlende Werte

    func testCancelledDraftsNothingEvenWithUris() {
        XCTAssertNil(TalerRefundPayload.build(
            from: makeReturn(status: .cancelled, talerUri: payPushUri, talerPaymentData: paymentDataJson(uris: [payPushUri]))
        ))
    }

    func testMissingStatusDraftsNothing() {
        XCTAssertNil(TalerRefundPayload.build(from: makeReturn(status: nil, talerUri: payPushUri)))
    }

    func testReadyWithoutAnyUriDraftsNothing() {
        XCTAssertNil(TalerRefundPayload.build(from: makeReturn(status: .ready)))
    }

    // MARK: Rueckfall-Regeln wie beim Senden

    func testReadyWithEmptyJsonListFallsBackToTalerUri() {
        let json = paymentDataJson(uris: [])
        let body = TalerRefundPayload.build(
            from: makeReturn(status: .ready, talerUri: payPushUri, talerPaymentData: json)
        )
        XCTAssertEqual(body, "Refund: \(payPushUri)")
    }

    func testUnparsableJsonFallsBackToTalerUri() {
        let body = TalerRefundPayload.build(
            from: makeReturn(status: .ready, talerUri: payPushUri, talerPaymentData: "{not json")
        )
        XCTAssertEqual(body, "Refund: \(payPushUri)")
    }

    func testParsableJsonWithInvalidUriDoesNotFallBackToTalerUri() {
        let json = paymentDataJson(uris: ["no uri at all"])
        XCTAssertNil(TalerRefundPayload.build(
            from: makeReturn(status: .ready, talerUri: payPushUri, talerPaymentData: json)
        ))
    }
}
