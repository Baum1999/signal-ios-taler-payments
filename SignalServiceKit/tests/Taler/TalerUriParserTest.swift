//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Faelle 1:1 aus `TalerUriParserTest.kt` (signal-android/taler-android).
final class TalerUriParserTest: XCTestCase {

    func testClassifiesPayPush() {
        XCTAssertEqual(TalerUriParser.classify("taler://pay-push/exchange.example/abc"), .payPush)
    }

    func testClassifiesPayPullWithExtTalerScheme() {
        XCTAssertEqual(TalerUriParser.classify("ext+taler://pay-pull/exchange.example/abc"), .payPull)
    }

    func testClassifiesPayAndPayTemplate() {
        XCTAssertEqual(TalerUriParser.classify("taler://pay/merchant.example/abc"), .pay)
        XCTAssertEqual(TalerUriParser.classify("taler://pay-template/merchant.example/abc"), .pay)
    }

    func testClassifiesWithdrawAndWithdrawExchange() {
        XCTAssertEqual(TalerUriParser.classify("taler://withdraw/exchange.example/abc"), .withdraw)
        XCTAssertEqual(TalerUriParser.classify("taler://withdraw-exchange/exchange.example/abc"), .withdraw)
    }

    func testClassifiesRefund() {
        XCTAssertEqual(TalerUriParser.classify("taler://refund/merchant.example/abc"), .refund)
    }

    func testIsCaseInsensitive() {
        XCTAssertEqual(TalerUriParser.classify("TALER://PAY-PUSH/exchange.example/abc"), .payPush)
    }

    func testRejectsUnknownScheme() {
        XCTAssertNil(TalerUriParser.classify("https://pay-push/exchange.example/abc"))
    }

    func testRejectsUnknownAction() {
        XCTAssertNil(TalerUriParser.classify("taler://not-a-real-action/exchange.example/abc"))
    }

    func testClassifiesTalerHttpButDetectorIgnoresIt() {
        XCTAssertEqual(TalerUriParser.classify("taler+http://pay-push/exchange.example/abc"), .payPush)
        XCTAssertEqual(TalerUriDetector.findUris("taler+http://pay-push/exchange.example/abc"), [])
    }

    func testRawValuesMatchAndroidEnumNames() {
        // Teil des Link-Protokolls (direction=...) und des DB-Formats.
        XCTAssertEqual(TalerUriKind.allCases.map(\.rawValue), ["PAY_PUSH", "PAY_PULL", "PAY", "WITHDRAW", "REFUND"])
    }
}
