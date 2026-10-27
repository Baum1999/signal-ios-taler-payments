//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Faelle aus `TalerHttpsLinkTest.kt` (taler-android, unwrap-Teil) plus die
/// iOS-Aufrufstellen (classify, Resolver, Links, Detector).
final class TalerHttpsLinkTest: XCTestCase {

    private let rawPush = "taler://pay-push/exchange.example/ABC"

    func testUnwrapsAllThreeDd103Forms() {
        XCTAssertEqual(TalerHttpsLink.unwrap("https://wallet.taler.net/link#pay-push/exchange.example/ABC"), rawPush)
        XCTAssertEqual(TalerHttpsLink.unwrap("https://wallet.taler.net/link#/pay-push/exchange.example/ABC"), rawPush)
        XCTAssertEqual(TalerHttpsLink.unwrap("https://wallet.taler.net/link#taler://pay-push/exchange.example/ABC"), rawPush)
        XCTAssertEqual(TalerHttpsLink.unwrap("https://wallet.taler.net/link/#pay-push/exchange.example/ABC"), rawPush)
    }

    func testUnwrapKeepsExtTaler() {
        XCTAssertEqual(
            TalerHttpsLink.unwrap("https://wallet.taler.net/link#ext+taler://pay-push/x/A"),
            "ext+taler://pay-push/x/A"
        )
    }

    func testUnwrapIsCaseInsensitiveForSchemeAndHost() {
        XCTAssertEqual(TalerHttpsLink.unwrap("HTTPS://WALLET.TALER.NET/link#pay-push/exchange.example/ABC"), rawPush)
        XCTAssertEqual(TalerHttpsLink.unwrap("https://wallet.taler.net/link#TALER://pay-push/x/A"), "TALER://pay-push/x/A")
    }

    func testReturnsInputUnchangedForNonLinks() {
        let inputs = [
            "taler://pay-push/exchange.example/ABC",
            "https://wallet.taler.net/link#",
            "https://wallet.taler.net/link#https://evil.example",
            "https://wallet.taler.net/link#javascript:alert(1)",
            "https://wallet.taler.net/link#/javascript:alert(1)",
            "https://wallet.taler.net/link?x=1#pay-push/x/A",
            "https://wallet.taler.net:443/link#pay-push/x/A",
            "https://wallet.taler.net/linkx#pay-push/x/A",
            "https://wallet.taler.net.evil.example/link#pay-push/x/A",
            "https://wallet.taler.net@evil.example/link#pay-push/x/A",
            "https://evil.example/link#pay-push/x/A",
            "https://wallet.taler.net/r?u=taler://pay-push/x/A",
        ]
        for input in inputs {
            XCTAssertEqual(TalerHttpsLink.unwrap(input), input, input)
        }
    }

    // MARK: Aufrufstellen

    func testClassifyUnwrapsFirst() {
        XCTAssertEqual(TalerUriParser.classify("https://wallet.taler.net/link#pay-push/exchange.example/ABC"), .payPush)
        XCTAssertEqual(TalerUriParser.classify("https://wallet.taler.net/link#pay-pull/exchange.example/ABC"), .payPull)
        XCTAssertNil(TalerUriParser.classify("https://example.com/pay-push/x"))
        XCTAssertNil(TalerUriParser.classify("https://evil.example/link#pay-push/x/A"))
        XCTAssertNil(TalerUriParser.classify("https://wallet.taler.net/link#javascript:alert(1)"))
    }

    func testResolverParsesWrappedLinkLikeRawUri() {
        let key = "0440Y5GX4GNK4EA08X75AQ33D9RQGZW6HPA9Q8N9P2VVXHECTFD0"
        let raw = TalerPeerContractResolver.parse("taler://pay-push/exchange.example/\(key)")
        XCTAssertNotNil(raw)
        XCTAssertEqual(TalerPeerContractResolver.parse("https://wallet.taler.net/link#pay-push/exchange.example/\(key)"), raw)
    }

    func testActionLinkUsesUnwrappedUri() {
        let url = TalerLinks.actionLink(
            forTalerUri: "https://wallet.taler.net/link#pay-push/exchange.example.org/7Q4XK2",
            correlationId: "c"
        )
        XCTAssertEqual(
            url?.absoluteString,
            "talerlink://pay-push/exchange.example.org/7Q4XK2?correlationId=c&returnUri=\(TalerLinks.returnScheme)%3A%2F%2Ftaler-return"
        )
    }

    func testComposeLinksSendUnwrappedUris() {
        let wrapped = "https://wallet.taler.net/link#pay-push/exchange.example.org/AAAA"
        let encodedRaw = "taler%3A%2F%2Fpay-push%2Fexchange.example.org%2FAAAA"
        let abort = TalerLinks.composeAbort(uris: [wrapped], correlationId: "c").absoluteString
        XCTAssertTrue(abort.contains("uri=\(encodedRaw)&"), abort)
        let refund = TalerLinks.composeRefund(originalUri: wrapped, correlationId: "c").absoluteString
        XCTAssertTrue(refund.contains("originalUri=\(encodedRaw)&"), refund)
    }

    func testDetectorFindsHttpsLink() {
        XCTAssertEqual(
            TalerUriDetector.findUris("Schau mal: https://wallet.taler.net/link#pay-push/exchange.example/AAA."),
            ["https://wallet.taler.net/link#pay-push/exchange.example/AAA"]
        )
        XCTAssertTrue(TalerUriDetector.isExactlyOneUri("https://wallet.taler.net/link#pay-push/exchange.example/AAA"))
    }

    func testDetectorIgnoresOtherDomains() {
        XCTAssertEqual(TalerUriDetector.findUris("https://wallet.taler.net.evil.example/link#pay-push/x/A"), [])
        XCTAssertEqual(TalerUriDetector.findUris("https://evil.example/link#pay-push/x/A"), [])
    }

    /// taler-ios teilt `taler://...` und den gleichwertigen https-Link in
    /// einer Nachricht - das ist eine Zahlung, die erste Form gewinnt.
    func testDetectorDeduplicatesRawAndWrappedForm() {
        let text = "taler://pay-push/exchange.example/AAA\nhttps://wallet.taler.net/link#pay-push/exchange.example/AAA"
        XCTAssertEqual(TalerUriDetector.findUris(text), ["taler://pay-push/exchange.example/AAA"])
    }

    func testAbortResultsMapBackToWrappedOriginal() {
        let wrapped = "https://wallet.taler.net/link#pay-push/ex/A"
        let updates = TalerAbortPlan.apply(
            results: [TalerAbortResult(uri: "taler://pay-push/ex/A", outcome: .expired)],
            allowed: [wrapped]
        )
        XCTAssertEqual(updates.map(\.uri), [wrapped])
    }

    // MARK: wrap (Klartext der Zahlungsnachrichten)

    func testWrapUsesWrapHostAndRoundTrips() {
        let wrapped = TalerHttpsLink.wrap(rawPush)
        XCTAssertEqual(wrapped, "https://\(TalerLinkHosts.wrapHost)/link#pay-push/exchange.example/ABC")
        XCTAssertEqual(TalerHttpsLink.unwrap(wrapped), rawPush)
    }

    func testMessageLinkWrapsOnlyTaler() {
        XCTAssertEqual(TalerHttpsLink.messageLink(rawPush), TalerHttpsLink.wrap(rawPush))
        XCTAssertEqual(TalerHttpsLink.messageLink("payto://iban/DE00"), "payto://iban/DE00")
    }

}
