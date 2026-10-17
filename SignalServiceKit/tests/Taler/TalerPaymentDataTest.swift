//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Faelle 1:1 aus `TalerPaymentDataTest.kt` (signal-android), plus
/// Kompatibilitaet mit dem von Kotlin erzeugten JSON.
final class TalerPaymentDataTest: XCTestCase {

    func testSingleUriJsonBodyReturnsExactlyThatUri() {
        let body = TalerPaymentData(legacyText: "fallback", uri: ["taler://pay-push/exchange.example/AAA"]).jsonString()!
        XCTAssertEqual(TalerMessageBody.uris(in: body), ["taler://pay-push/exchange.example/AAA"])
    }

    func testMultiUriJsonBodyReturnsAllUrisInOrder() {
        let uris = [
            "taler://pay-push/exchange.example/AAA",
            "taler://pay-push/exchange.example/BBB",
            "taler://pay-push/exchange.example/CCC",
        ]
        let body = TalerPaymentData(legacyText: "fallback", uri: uris).jsonString()!
        XCTAssertEqual(TalerMessageBody.uris(in: body), uris)
    }

    func testPlainTextLegacyMessageFallsBackToRegex() {
        XCTAssertEqual(TalerMessageBody.uris(in: "Payment: taler://pay-push/exchange.example/AAA"), ["taler://pay-push/exchange.example/AAA"])
    }

    func testUnrelatedJsonFallsBackToRegex() {
        let body = #"{"foo":"taler://pay-push/exchange.example/AAA "}"#
        XCTAssertEqual(TalerMessageBody.uris(in: body), ["taler://pay-push/exchange.example/AAA"])
    }

    func testJsonWithEmptyUriListFallsBackToRegexFindingNothing() {
        let body = TalerPaymentData(legacyText: "fallback", uri: []).jsonString()!
        XCTAssertEqual(TalerMessageBody.uris(in: body), [])
    }

    func testBlankTextReturnsEmptyList() {
        XCTAssertEqual(TalerMessageBody.uris(in: ""), [])
    }

    func testLegacyTextBeforeUri() {
        let body = "This is a GNU Taler link. Update Signal or copy the URI below " +
            "into the GNU Taler app to make the payment.\n\n" +
            "taler://pay-push/exchange.example/AAA"
        XCTAssertEqual(TalerMessageBody.uris(in: body), ["taler://pay-push/exchange.example/AAA"])
    }

    func testLegacyTextBeforeMultipleUris() {
        let body = "This is a GNU Taler link. Update Signal or copy the URI below " +
            "into the GNU Taler app to make the payment.\n\n" +
            "taler://pay-push/exchange.example/AAA\n\n" +
            "taler://pay-push/exchange.example/BBB"
        XCTAssertEqual(
            TalerMessageBody.uris(in: body),
            ["taler://pay-push/exchange.example/AAA", "taler://pay-push/exchange.example/BBB"],
        )
    }

    func testDecodesKotlinJsonWithoutDefaultFields() {
        // kotlinx.serialization laesst version=1 und null-Felder weg.
        let kotlin = #"{"legacyText":"x","uri":["taler://pay-push/e/A"]}"#
        let decoded = TalerPaymentData.parseOrNil(kotlin)
        XCTAssertEqual(decoded, TalerPaymentData(legacyText: "x", uri: ["taler://pay-push/e/A"]))
    }

    func testDecodesKotlinGroupSplitJson() {
        let kotlin = #"{"legacyText":"x","includeSelf":true,"totalAmount":"30","uri":["taler://pay-push/e/A","taler://pay-push/e/B"]}"#
        let decoded = TalerPaymentData.parseOrNil(kotlin)
        XCTAssertEqual(decoded?.includeSelf, true)
        XCTAssertEqual(decoded?.totalAmount, "30")
        XCTAssertEqual(decoded?.uri.count, 2)
        XCTAssertEqual(decoded?.version, 1)
    }

    func testEncodingOmitsDefaultsLikeKotlin() {
        let json = TalerPaymentData(legacyText: "x", uri: ["taler://pay-push/e/A"]).jsonString()
        XCTAssertEqual(json, #"{"legacyText":"x","uri":["taler://pay-push/e/A"]}"#)
    }

    func testShortHashIsTwelveHexCharactersAndStable() {
        let hash = TalerCorrelation.shortHash("taler://pay-push/exchange.example/AAA")
        XCTAssertEqual(hash.count, 12)
        XCTAssertEqual(hash, TalerCorrelation.shortHash("taler://pay-push/exchange.example/AAA"))
        XCTAssertNotEqual(hash, TalerCorrelation.shortHash("taler://pay-push/exchange.example/BBB"))
    }
}
