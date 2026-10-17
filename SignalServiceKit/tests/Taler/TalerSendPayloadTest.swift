//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// TalerSendPayload.build nach docs/cross-platform/link-protokoll.md (3, 8):
/// nur status=ready sendet; JSON vor talerUri mit Rueckfall bei unparbarem
/// JSON oder leerer Liste; JEDE URI muss isExactlyOneUri UND PAY_PUSH/PAY_PULL
/// sein, sonst wird nichts gesendet (kein Teilversand); Body wie Android
/// (TalerReturnActivity.kt: legacyText + Leerzeile + URIs mit Leerzeile,
/// Rueckfallpfad als Einzeiler "Payment sent/requested: ...").
final class TalerSendPayloadTest: XCTestCase {

    private let payPushUri = "taler://pay-push/exchange.example.org/AAAABBBB"
    private let payPushUri2 = "taler://pay-push/exchange.example.org/CCCCDDDD"
    private let payPushUri3 = "taler://pay-push/exchange.example.org/EEEEFFFF"
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
        uris: [String],
        includeSelf: Bool? = nil,
        totalAmount: String? = nil
    ) -> String {
        var dict: [String: Any] = ["legacyText": legacyText, "uri": uris]
        dict["includeSelf"] = includeSelf
        dict["totalAmount"] = totalAmount
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: ready, eine URI (Rueckfall talerUri)

    func testReadyWithSinglePayPushUri() {
        let result = TalerSendPayload.build(from: makeReturn(status: .ready, talerUri: payPushUri))
        XCTAssertNotNil(result)
        XCTAssertEqual(
            result?.body,
            "Payment sent: \(TalerStrings.wireKindPayPush) (\(payPushUri))"
        )
        XCTAssertEqual(result?.payload.uris, [payPushUri])
        XCTAssertEqual(result?.payload.version, 1)
        XCTAssertFalse(result!.payload.isGroupSplit)
        XCTAssertNil(result?.payload.includeSelf)
        XCTAssertNil(result?.payload.totalAmount)
    }

    func testReadyWithSinglePayPullUriUsesRequestWording() {
        let result = TalerSendPayload.build(from: makeReturn(status: .ready, talerUri: payPullUri))
        XCTAssertEqual(
            result?.body,
            "Payment requested: \(TalerStrings.wireKindPayPull) (\(payPullUri))"
        )
        XCTAssertEqual(result?.payload.uris, [payPullUri])
    }

    // MARK: ready, JSON mit drei URIs (Gruppen-Split)

    func testReadyWithJsonAndThreeUris() {
        let uris = [payPushUri, payPushUri2, payPushUri3]
        let legacy = "Legacy text from Taler"
        let json = paymentDataJson(
            legacyText: legacy,
            uris: uris,
            includeSelf: true,
            totalAmount: "10"
        )
        let result = TalerSendPayload.build(
            from: makeReturn(status: .ready, talerUri: payPushUri, talerPaymentData: json)
        )
        // JSON hat Vorrang vor talerUri.
        XCTAssertEqual(result?.body, legacy + "\n\n" + uris.joined(separator: "\n\n"))
        XCTAssertEqual(result?.payload.uris, uris)
        XCTAssertEqual(result?.payload.version, 1)
        XCTAssertTrue(result!.payload.isGroupSplit)
        XCTAssertEqual(result?.payload.includeSelf, true)
        XCTAssertEqual(result?.payload.totalAmount, "10")
    }

    func testReadyWithJsonSingleUriIsNoGroupSplit() {
        let json = paymentDataJson(uris: [payPushUri])
        let result = TalerSendPayload.build(from: makeReturn(status: .ready, talerPaymentData: json))
        XCTAssertFalse(result!.payload.isGroupSplit)
        XCTAssertEqual(result?.body, TalerStrings.legacyText + "\n\n" + payPushUri)
    }

    // MARK: ungueltige URIs

    func testJsonWithOneInvalidUriSendsNothing() {
        // "taler://pay-push/x zwei URIs" ist nicht genau eine URI.
        let json = paymentDataJson(uris: [payPushUri, "taler://pay-push/x taler://pay-pull/y"])
        XCTAssertNil(TalerSendPayload.build(from: makeReturn(status: .ready, talerPaymentData: json)))
    }

    func testUriWithSurroundingTextSendsNothing() {
        XCTAssertNil(TalerSendPayload.build(from: makeReturn(status: .ready, talerUri: "pay taler://pay-push/ex/AAA")))
    }

    func testWithdrawUriSendsNothing() {
        // WITHDRAW ist keine Zahlungs-URI: nicht senden, auch nicht im JSON-Pfad.
        let json = paymentDataJson(uris: ["taler://withdraw/exchange.example.org/AAA"])
        XCTAssertNil(TalerSendPayload.build(from: makeReturn(status: .ready, talerPaymentData: json)))
        XCTAssertNil(TalerSendPayload.build(
            from: makeReturn(status: .ready, talerUri: "taler://withdraw/exchange.example.org/AAA")
        ))
    }

    func testRefundUriSendsNothing() {
        XCTAssertNil(TalerSendPayload.build(
            from: makeReturn(status: .ready, talerUri: "taler://refund/exchange.example.org/AAA")
        ))
    }

    // MARK: status und fehlende Werte

    func testCancelledSendsNothingEvenWithUris() {
        XCTAssertNil(TalerSendPayload.build(
            from: makeReturn(status: .cancelled, talerUri: payPushUri, talerPaymentData: paymentDataJson(uris: [payPushUri]))
        ))
    }

    func testMissingStatusSendsNothing() {
        XCTAssertNil(TalerSendPayload.build(from: makeReturn(status: nil, talerUri: payPushUri)))
    }

    func testReadyWithoutAnyUriSendsNothing() {
        XCTAssertNil(TalerSendPayload.build(from: makeReturn(status: .ready)))
    }

    func testReadyWithEmptyJsonListFallsBackToTalerUri() {
        let json = paymentDataJson(uris: [])
        let result = TalerSendPayload.build(
            from: makeReturn(status: .ready, talerUri: payPushUri, talerPaymentData: json)
        )
        XCTAssertEqual(result?.payload.uris, [payPushUri])
    }

    func testReadyWithEmptyJsonListAndNoTalerUriSendsNothing() {
        let json = paymentDataJson(uris: [])
        XCTAssertNil(TalerSendPayload.build(from: makeReturn(status: .ready, talerPaymentData: json)))
    }

    func testUnparsableJsonFallsBackToTalerUri() {
        let result = TalerSendPayload.build(
            from: makeReturn(status: .ready, talerUri: payPushUri, talerPaymentData: "{not json")
        )
        XCTAssertEqual(result?.payload.uris, [payPushUri])
    }

    func testParsableJsonWithInvalidUriDoesNotFallBackToTalerUri() {
        let json = paymentDataJson(uris: ["no uri at all"])
        XCTAssertNil(TalerSendPayload.build(
            from: makeReturn(status: .ready, talerUri: payPushUri, talerPaymentData: json)
        ))
    }
}
