//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Golden-Vektoren fuer die komplette Contract-Entschluesselung, erzeugt mit
/// der Referenz (`wallet-core/packages/taler-util`,
/// `encryptContractForMerge`/`encryptContractForDeposit`) - identisch zu
/// `TalerContractCryptoTest.kt` (signal-android, Branch taler-abort-gap-a).
final class TalerContractCryptoTest: XCTestCase {

    private let contractPrivateKey = try! Crockford.decodeFixed("0440Y5GX4GNK4EA08X75AQ33D9RQGZW6HPA9Q8N9P2VVXHECTFD0", expectedLength: 32)
    private let pursePublicKey = try! Crockford.decodeFixed("XNHH63ZEN13M3YM8A6WKXBFZJQNPSM8XQ0CZGS8C29CV84CA63T0", expectedLength: 32)

    static let pushContractCrock = "1C71250Q38EJ08S654P2YCHN70XKWGA48X54TM20HZKE2VGV0S1ED5P85DABH348J189TBZ6KX57ZDT6GS2JA5AY3EE15C0CQ4RF6C6KTHE635877HMEQ64CNSP291WKAANT5R7GJ638N6VTRQ2HJRJA7DFGS8N21THPWVZAK2BZTW0Y47F3QV9FZHFY9K6A555QNT9PMCHPG6FVAX8MWEFA2Q292VT676ENDGTN21S01CN01BATPZ4GVXQ23Z9T1CQMP8BTZF3TFA3AER9YHT44GC4A7S8"
    static let pullContractCrock = "1C71250Q38EJ08S654P2YCHN70XKWGA48X54TM521C7ENA5HXWCPSN9FC7BJM6012H4KN4HKVMH5TZ9VKYM3Y62X9FA3043MEKSQTZV3ZRAXSBRBR0QCQ2N5MN0NB25QW7HAJT3Z33JYPXC7DNXHA2RDQWYTPACVM0BFZN0AXM68KJYQW75FDTDT0VDQ2RSDPXCH0K5SC9WT1S1J0QZZPY7W5T38R"

    private var pushContract: Data { try! Crockford.decode(Self.pushContractCrock) }
    private var pullContract: Data { try! Crockford.decode(Self.pullContractCrock) }

    func testContractPublicKeyMatchesReference() throws {
        XCTAssertEqual(
            Crockford.encode(try TalerCrypto.eddsaPublicKey(seed: contractPrivateKey)),
            "WG1GK66FTPPHE8Y1D7WNDAGBKTW636TSJAYP2B1AYGMEQHWZHQR0",
        )
    }

    func testDecryptsPayPushContract() {
        XCTAssertEqual(
            TalerContractCrypto.decrypt(encryptedContract: pushContract, pursePublicKey: pursePublicKey, contractPrivateKey: contractPrivateKey, direction: .merge),
            #"{"amount":"KUDOS:12.5","purse_expiration":{"t_s":4102444800},"summary":"Pizza fuer Signal"}"#,
        )
    }

    func testDecryptsPayPullContract() {
        XCTAssertEqual(
            TalerContractCrypto.decrypt(encryptedContract: pullContract, pursePublicKey: pursePublicKey, contractPrivateKey: contractPrivateKey, direction: .deposit),
            #"{"amount":"EUR:3.20","purse_expiration":{"t_s":"never"},"summary":"Kaffee zurueck"}"#,
        )
    }

    func testRejectsContractDecryptedInWrongDirection() {
        XCTAssertNil(TalerContractCrypto.decrypt(encryptedContract: pullContract, pursePublicKey: pursePublicKey, contractPrivateKey: contractPrivateKey, direction: .merge))
    }

    func testRejectsContractForDifferentPurse() {
        var otherPurse = pursePublicKey
        otherPurse[0] ^= 1
        XCTAssertNil(TalerContractCrypto.decrypt(encryptedContract: pushContract, pursePublicKey: otherPurse, contractPrivateKey: contractPrivateKey, direction: .merge))
    }

    func testRejectsTruncatedContract() {
        XCTAssertNil(TalerContractCrypto.decrypt(encryptedContract: pushContract.prefix(20), pursePublicKey: pursePublicKey, contractPrivateKey: contractPrivateKey, direction: .merge))
    }

    func testOwnEncryptionRoundTripsThroughDecrypt() {
        let nonce = Data((0..<24).map { UInt8($0 + 7) })
        let json = #"{"amount":"KUDOS:1","summary":"Test"}"#
        let encrypted = TalerContractCrypto.encrypt(
            contractTermsJson: json,
            pursePublicKey: pursePublicKey,
            contractPrivateKey: contractPrivateKey,
            mergePrivateKey: nil,
            direction: .merge,
            nonce: nonce,
        )!
        XCTAssertEqual(
            TalerContractCrypto.decrypt(encryptedContract: encrypted, pursePublicKey: pursePublicKey, contractPrivateKey: contractPrivateKey, direction: .merge),
            json,
        )
    }
}

/// Resolver-Ablauf mit gefakten Exchange-Antworten auf Basis der
/// Golden-Vektoren (kein Netz).
final class TalerPeerContractResolverTest: XCTestCase {

    private let contractPrivCrock = "0440Y5GX4GNK4EA08X75AQ33D9RQGZW6HPA9Q8N9P2VVXHECTFD0"
    private let pursePubCrock = "XNHH63ZEN13M3YM8A6WKXBFZJQNPSM8XQ0CZGS8C29CV84CA63T0"
    private let contractPubCrock = "WG1GK66FTPPHE8Y1D7WNDAGBKTW636TSJAYP2B1AYGMEQHWZHQR0"

    private func resolver(_ responses: [String: TalerPeerContractResolver.HTTPResult], failing: Bool = false) -> TalerPeerContractResolver {
        TalerPeerContractResolver(
            fetch: { url in
                if failing { throw URLError(.notConnectedToInternet) }
                return responses[url.absoluteString] ?? .notFound
            },
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
        )
    }

    private func contractJson(_ econtract: String) -> TalerPeerContractResolver.HTTPResult {
        .ok(Data(#"{"purse_pub":"\#(pursePubCrock)","econtract":"\#(econtract)"}"#.utf8))
    }

    func testParsesUriWithPathAndQuery() {
        let parsed = TalerPeerContractResolver.parse("taler://pay-push/exchange.example/sub/\(contractPrivCrock)?correlationId=x")
        XCTAssertEqual(parsed?.kind, .payPush)
        XCTAssertEqual(parsed?.exchangeBaseUrl, "https://exchange.example/sub/")
        XCTAssertEqual(parsed?.contractPrivateKey.count, 32)
    }

    func testParseRejectsNonPeerUrisAndBadKeys() {
        XCTAssertNil(TalerPeerContractResolver.parse("taler://pay/merchant.example/abc"))
        XCTAssertNil(TalerPeerContractResolver.parse("taler://pay-push/exchange.example/SHORT"))
        XCTAssertNil(TalerPeerContractResolver.parse("taler://pay-push/\(contractPrivCrock)"))
    }

    func testResolvesAcceptedPayPush() async {
        let base = "https://exchange.example/"
        let result = await resolver([
            "\(base)contracts/\(contractPubCrock)": contractJson(TalerContractCryptoTest.pushContractCrock),
            "\(base)purses/\(pursePubCrock)/deposit": .ok(Data(#"{"merge_timestamp":{"t_s":1700000000},"deposit_timestamp":{"t_s":1690000000}}"#.utf8)),
        ]).resolve("taler://pay-push/exchange.example/\(contractPrivCrock)")

        XCTAssertEqual(result, .result(TalerPaymentPreview(
            uriKind: .payPush,
            status: .angenommen,
            amount: "12.5",
            currency: "KUDOS",
            exchangeBaseUrl: base,
            summary: "Pizza fuer Signal",
            expirationTimestamp: 4_102_444_800_000,
        )))
    }

    func testResolvesOpenPayPullWithNeverExpiration() async {
        let base = "https://exchange.example/"
        let result = await resolver([
            "\(base)contracts/\(contractPubCrock)": contractJson(TalerContractCryptoTest.pullContractCrock),
            "\(base)purses/\(pursePubCrock)/merge": .ok(Data(#"{"merge_timestamp":{"t_s":1700000000}}"#.utf8)),
        ]).resolve("taler://pay-pull/exchange.example/\(contractPrivCrock)")

        XCTAssertEqual(result, .result(TalerPaymentPreview(
            uriKind: .payPull,
            status: .offen,
            amount: "3.20",
            currency: "EUR",
            exchangeBaseUrl: base,
            summary: "Kaffee zurueck",
            expirationTimestamp: nil,
        )))
    }

    func testMissingContractMeansExpired() async {
        let result = await resolver([:]).resolve("taler://pay-push/exchange.example/\(contractPrivCrock)")
        XCTAssertEqual(result, .failed(.abgelaufen))
    }

    func testTransportErrorMeansOffline() async {
        let result = await resolver([:], failing: true).resolve("taler://pay-push/exchange.example/\(contractPrivCrock)")
        XCTAssertEqual(result, .offline)
    }

    func testWrongDirectionMeansInvalid() async {
        let base = "https://exchange.example/"
        let result = await resolver([
            "\(base)contracts/\(contractPubCrock)": contractJson(TalerContractCryptoTest.pullContractCrock),
        ]).resolve("taler://pay-push/exchange.example/\(contractPrivCrock)")
        XCTAssertEqual(result, .failed(.ungueltig))
    }

    func testMalformedUriIsInvalid() async {
        let result = await resolver([:]).resolve("taler://pay-push/exchange.example/nope")
        XCTAssertEqual(result, .failed(.ungueltig))
    }

    func testSplitAmount() {
        XCTAssertTrue(TalerPeerContractResolver.splitAmount("KUDOS:1.5") == ("1.5", "KUDOS"))
        XCTAssertTrue(TalerPeerContractResolver.splitAmount("1.5") == ("1.5", nil))
    }
}
