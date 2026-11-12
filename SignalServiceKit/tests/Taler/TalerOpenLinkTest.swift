//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// `taler-open` nach docs/cross-platform/link-protokoll.md 12: Hash wie der
/// OwnUriStore-Schluessel in Taler-iOS, Erkennung von Scheme/Host, strenge
/// Hash-Pruefung, Reihenfolge und Obergrenze, Zuordnung zur bekannten URI.
final class TalerOpenLinkTest: XCTestCase {

    private let push = "taler://pay-push/exchange.example.org/7Q4XK2"
    private let pushHash = "b128b650d7a36d51ebef90db845d6eff7c01cc99c6246b5179743c1d7c176147"
    private let pull = "taler://pay-pull/exchange.example.org/BBBB"
    private let pullHash = "cc50c43eff63012e647a5808223fae212472d70d0243f32e8971f64ae212104e"

    private func url(_ query: String, host: String = "taler-open") -> URL {
        URL(string: "\(TalerLinks.returnScheme)://\(host)?\(query)")!
    }

    func testHashIsSha256HexOfTheExactUri() {
        XCTAssertEqual(TalerOpenLink.uriHash(push), pushHash)
        XCTAssertEqual(TalerOpenLink.uriHash(pull), pullHash)
    }

    func testRecognisesSchemeAndHostCaseInsensitively() {
        XCTAssertTrue(TalerOpenLink.isOpenUrl(url("v=1&uriHash=\(pushHash)")))
        XCTAssertTrue(TalerOpenLink.isOpenUrl(URL(string: "\(TalerLinks.returnScheme.uppercased())://TALER-OPEN?uriHash=\(pushHash)")!))
        XCTAssertFalse(TalerOpenLink.isOpenUrl(url("uriHash=\(pushHash)", host: "taler-return")))
        XCTAssertFalse(TalerOpenLink.isOpenUrl(URL(string: "taler://taler-open?uriHash=\(pushHash)")!))
    }

    func testParsesValidHashesInOrderWithoutDuplicates() {
        let link = url("v=1&uriHash=\(pullHash)&uriHash=\(pushHash.uppercased())&uriHash=\(pullHash)")
        XCTAssertEqual(TalerOpenLink.parseHashes(link), [pullHash, pushHash])
    }

    func testDropsInvalidHashesOnly() {
        let tooShort = String(pushHash.dropLast())
        let notHex = String(pushHash.dropLast()) + "g"
        let link = url("uriHash=\(tooShort)&uriHash=\(notHex)&uriHash=&uriHash=\(pullHash)")
        XCTAssertEqual(TalerOpenLink.parseHashes(link), [pullHash])
        XCTAssertEqual(TalerOpenLink.parseHashes(url("uriHash=\(tooShort)")), [])
        XCTAssertEqual(TalerOpenLink.parseHashes(url("v=1")), [])
    }

    func testIgnoresOtherHosts() {
        XCTAssertEqual(TalerOpenLink.parseHashes(url("uriHash=\(pushHash)", host: "taler-return")), [])
    }

    func testLimitsTheNumberOfHashes() {
        let hashes = (0..<40).map { TalerOpenLink.uriHash("taler://pay-push/exchange.example.org/\($0)") }
        let link = url(hashes.map { "uriHash=\($0)" }.joined(separator: "&"))
        XCTAssertEqual(TalerOpenLink.parseHashes(link), Array(hashes.prefix(TalerOpenLink.maxHashes)))
    }

    func testFirstMatchingUriFollowsLinkOrder() {
        let known = [push, pull]
        XCTAssertEqual(TalerOpenLink.firstMatchingUri(hashes: [pullHash, pushHash], knownUris: known), pull)
        XCTAssertEqual(TalerOpenLink.firstMatchingUri(hashes: [String(repeating: "0", count: 64), pushHash], knownUris: known), push)
        XCTAssertNil(TalerOpenLink.firstMatchingUri(hashes: [pushHash], knownUris: [pull]))
    }
}
