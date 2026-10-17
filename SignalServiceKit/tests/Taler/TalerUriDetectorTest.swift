//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Faelle 1:1 aus `TalerUriDetectorTest.kt` (signal-android).
final class TalerUriDetectorTest: XCTestCase {

    func testFindsMultipleUrisInOneText() {
        let text = "Hier: taler://pay-push/exchange.example/AAA und dann noch taler://pay-pull/exchange.example/BBB"
        XCTAssertEqual(
            TalerUriDetector.findUris(text),
            ["taler://pay-push/exchange.example/AAA", "taler://pay-pull/exchange.example/BBB"],
        )
    }

    func testStripsTrailingPunctuationAtSentenceEnd() {
        let expected = ["taler://pay-push/exchange.example/AAA"]
        XCTAssertEqual(TalerUriDetector.findUris("Schau mal: taler://pay-push/exchange.example/AAA."), expected)
        XCTAssertEqual(TalerUriDetector.findUris("taler://pay-push/exchange.example/AAA!"), expected)
        XCTAssertEqual(TalerUriDetector.findUris("(taler://pay-push/exchange.example/AAA)"), expected)
        XCTAssertEqual(TalerUriDetector.findUris("taler://pay-push/exchange.example/AAA?"), expected)
        XCTAssertEqual(TalerUriDetector.findUris("[taler://pay-push/exchange.example/AAA]"), expected)
    }

    func testDeduplicatesRepeatedUri() {
        let text = "taler://pay-push/exchange.example/AAA taler://pay-push/exchange.example/AAA"
        XCTAssertEqual(TalerUriDetector.findUris(text), ["taler://pay-push/exchange.example/AAA"])
    }

    func testFindsAllThreeSchemes() {
        let text = "taler://pay-push/x ext+taler://pay-pull/y payto://iban/DE1234567890"
        XCTAssertEqual(TalerUriDetector.findUris(text).count, 3)
    }

    func testIsCaseInsensitiveForSchemeDetection() {
        XCTAssertEqual(TalerUriDetector.findUris("TALER://pay-push/exchange.example/AAA").count, 1)
    }

    func testReturnsEmptyListForTextWithoutUris() {
        XCTAssertEqual(TalerUriDetector.findUris("Hallo, wie geht es dir?"), [])
    }

    func testReturnsEmptyListForEmptyBody() {
        XCTAssertEqual(TalerUriDetector.findUris(""), [])
    }

    func testCleanSingleUriReturnsTrue() {
        XCTAssertTrue(TalerUriDetector.isExactlyOneUri("taler://pay-push/exchange.example/abc123"))
    }

    func testUriWithGarbageTextBeforeItReturnsFalse() {
        XCTAssertFalse(TalerUriDetector.isExactlyOneUri("hello taler://pay-push/exchange.example/abc123"))
    }

    func testUriWithGarbageTextAfterItReturnsFalse() {
        XCTAssertFalse(TalerUriDetector.isExactlyOneUri("taler://pay-push/exchange.example/abc123 world"))
    }

    func testUriWithEmbeddedWhitespaceReturnsFalse() {
        XCTAssertFalse(TalerUriDetector.isExactlyOneUri("taler://pay-push/exchange.example/abc 123"))
    }

    func testEmptyStringReturnsFalse() {
        XCTAssertFalse(TalerUriDetector.isExactlyOneUri(""))
    }

    func testTwoUrisGluedTogetherIsASingleGreedyMatch() {
        // Gleiche Regex-Eigenheit wie auf Android: \S+ ist gierig, zwischen
        // "abc123" und "taler://" gibt es keine Wortgrenze.
        XCTAssertTrue(TalerUriDetector.isExactlyOneUri(
            "taler://pay-push/exchange.example/abc123taler://pay-push/exchange.example/def456",
        ))
    }

    func testTwoUrisSeparatedByWhitespaceReturnsFalse() {
        XCTAssertFalse(TalerUriDetector.isExactlyOneUri(
            "taler://pay-push/exchange.example/abc123 taler://pay-push/exchange.example/def456",
        ))
    }

    func testPaytoUriAloneStillReturnsTrue() {
        XCTAssertTrue(TalerUriDetector.isExactlyOneUri("payto://iban/DE1234567890/?message=test"))
    }

    func testLegacyTextBeforeUriIsFound() {
        // Android-Fix 09e5a3f5cc: Legacy-Text vor der URI.
        let body = "This is a GNU Taler link. Update Signal or copy the URI below into the GNU Taler app to make the payment.\n\ntaler://pay-push/exchange.example/AAA"
        XCTAssertEqual(TalerUriDetector.findUris(body), ["taler://pay-push/exchange.example/AAA"])
    }
}
