//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Spiegel der Review-Focus-Faelle aus dem Plan
/// 2026-10-02-taler-preview-chatlist-notification.md und von
/// `TalerPreviewTextTest.kt` (signal-android): Die Vorschau darf die rohe URI
/// aus Chatliste und Banner entfernen, aber niemals nutzergeschriebenen Text
/// um eine URI verschlucken.
final class TalerPreviewTextTest: XCTestCase {

    private let payPushUri = "taler://pay-push/exchange.example/AAA"
    private let payPullUri = "taler://pay-pull/exchange.example/BBB"
    private let paytoUri = "payto://iban/DE89370400440532013000"

    private func sendBody(_ uri: String? = nil) -> String {
        String(format: TalerStrings.sendMessageFormat, TalerStrings.wireKindPayPush, uri ?? payPushUri)
    }

    private func requestBody(_ uri: String? = nil) -> String {
        String(format: TalerStrings.requestMessageFormat, TalerStrings.wireKindPayPull, uri ?? payPullUri)
    }

    private func confirmationBody(_ uri: String? = nil) -> String {
        String(format: TalerStrings.acceptConfirmationFormat, TalerStrings.wireKindPayPush, uri ?? payPushUri)
    }

    private func legacyBody(_ uris: [String]) -> String {
        TalerStrings.legacyText + "\n\n" + uris.joined(separator: "\n\n")
    }

    // MARK: Wire-Formate ohne Payload

    func testSendFormatYieldsPayPushLabel() {
        XCTAssertEqual(TalerPreviewText.previewLabel(body: sendBody()), TalerStrings.kindPayPush)
    }

    func testRequestFormatYieldsPayPullLabel() {
        XCTAssertEqual(TalerPreviewText.previewLabel(body: requestBody()), TalerStrings.kindPayPull)
    }

    func testConfirmationFormatYieldsAcceptedStatusLabel() {
        XCTAssertEqual(TalerPreviewText.previewLabel(body: confirmationBody()), TalerStrings.statusLineAccepted)
    }

    // MARK: Gruppen-Split (mit und ohne Payload - iOS kennt nur die Heuristik)

    func testGroupSplitWithoutPayloadYieldsGroupSplitLabel() {
        let body = legacyBody([payPushUri, payPullUri, "taler://pay-push/exchange.example/CCC"])
        XCTAssertEqual(TalerPreviewText.previewLabel(body: body), TalerStrings.previewGroupSplit)
    }

    // MARK: Nutzertext bleibt sichtbar

    func testUserTextWithUriIsNotATalerMessage() {
        XCTAssertNil(TalerPreviewText.previewLabel(body: "Schau mal, Geld für dich: \(payPushUri)"))
        XCTAssertNil(TalerPreviewText.previewLabel(body: "Hey, look at this: \(payPushUri)"))
        XCTAssertNil(TalerPreviewText.previewLabel(body: "payment: \(payPushUri), please"))
    }

    func testPlainTextAndEmptyBodyAreNotTalerMessages() {
        XCTAssertNil(TalerPreviewText.previewLabel(body: "Hello"))
        XCTAssertNil(TalerPreviewText.previewLabel(body: ""))
        XCTAssertNil(TalerPreviewText.previewLabel(body: "  \n  "))
    }

    // MARK: payto:// wird erkannt, aber nicht klassifiziert

    func testPaytoUriYieldsUnknownLabel() {
        XCTAssertEqual(TalerPreviewText.previewLabel(body: paytoUri), TalerStrings.kindUnknown)
    }

    // MARK: Aeltere Fork-Versionen: TalerPaymentData als JSON im Body

    func testLegacyJsonBodyYieldsLabel() {
        let json = #"{"legacyText":"This is a GNU Taler link.","version":1,"uri":["\#(payPushUri)"]}"#
        XCTAssertEqual(TalerPreviewText.previewLabel(body: json), TalerStrings.kindPayPush)
    }

    func testLegacyJsonBodyWithMultipleUrisYieldsGroupSplitLabel() {
        let json = #"{"legacyText":"This is a GNU Taler link.","version":1,"uri":["\#(payPushUri)","\#(payPullUri)"]}"#
        XCTAssertEqual(TalerPreviewText.previewLabel(body: json), TalerStrings.previewGroupSplit)
    }

    // MARK: Normalisierung und nackte URIs

    func testWhitespaceVariationsStillMatchTheSendFormat() {
        let body = "Payment sent:  \(TalerStrings.wireKindPayPush)  (\(payPushUri))"
        XCTAssertEqual(TalerPreviewText.previewLabel(body: body), TalerStrings.kindPayPush)
    }

    func testBareUriYieldsKindLabel() {
        XCTAssertEqual(TalerPreviewText.previewLabel(body: payPullUri), TalerStrings.kindPayPull)
    }

    func testExtTalerUriIsDetected() {
        XCTAssertEqual(
            TalerPreviewText.previewLabel(body: "ext+taler://pay-push/exchange.example/AAA"),
            TalerStrings.kindPayPush
        )
    }
}
