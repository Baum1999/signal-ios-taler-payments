//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Die offiziellen GNU-Taler-Testvektoren (`taler-exchange-tvg`) - identisch
/// zu `TalerCryptoVectorTest.kt` (signal-android), dort aus
/// `wallet-core/packages/taler-util/src/taler-crypto.test.ts` und
/// `xsalsa20poly1305.test.ts` uebernommen.
final class TalerCryptoVectorTest: XCTestCase {

    func testCrockfordRoundTrip() throws {
        let input = "Hello, World"
        let encoded = Crockford.encode(Data(input.utf8))
        XCTAssertEqual(String(data: try Crockford.decode(encoded), encoding: .utf8), input)
    }

    func testHashCodeVector() throws {
        let input = "91JPRV3F5GG4EKJN41A62V35E8"
        let expected = "CW96WR74JS8T53EC8GKSGD49QKH4ZNFTZXDAWMMV5GJ1E4BM6B8GPN5NVHDJ8ZVXNCW7Q4WBYCV61HCA3PZC2YJD850DT29RHHN7ESR"
        XCTAssertEqual(Crockford.encode(TalerCrypto.sha512(try Crockford.decode(input))), expected)
    }

    func testEddsaPublicKeyVector() throws {
        let privateKey = "9TM70AKDTS57AWY9JK2J4TMBTMW6K62WHHGZWYDG0VM5ABPZKD40"
        let publicKey = "8GSJZ649T2PXMKZC01Y4ANNBE7MF14QVK9SQEC4E46ZHKCVG8AS0"
        XCTAssertEqual(Crockford.encode(try TalerCrypto.eddsaPublicKey(seed: try Crockford.decode(privateKey))), publicKey)
    }

    func testKdfVector() throws {
        let salt = "94KPT83PCNS7J83KC5P78Y8"
        let ikm = "94KPT83MD1JJ0WV5CDS6AX10D5Q70XBM41NPAY90DNGQ8SBJD5GPR"
        let context = "94KPT83141HPYVKMCNW78833D1TPWTSC41GPRWVF41NPWVVQDRG62WS04XMPWSKF4WG6JVH0EHM6A82J8S1G"
        let expected = "GTMR4QT05Z9WF5HKVG0WK9RPXGHSMHJNW377G9GJXCA8B0FEKPF4D27RJMSJZYWSQNTBJ5EYVV7ZW18B48Z0JVJJ80RHB706Y96Q358"

        let derived = TalerKdf.derive(
            outputLength: 64,
            ikm: try Crockford.decode(ikm),
            salt: try Crockford.decode(salt),
            info: try Crockford.decode(context),
        )
        XCTAssertEqual(Crockford.encode(derived), expected)
    }

    func testKeyExchangeVector() throws {
        let ecdhePrivate = "4AFZWMSGTVCHZPQ0R81NWXDCK4N58G7SDBBE5KXE080Y50370JJG"
        let eddsaPrivate = "1KG54M8T3X8BSFSZXCR3SQBSR7Y9P53NX61M864S7TEVMJ2XVPF0"
        let eddsaPublic = "7BXWKG6N224C57RTDV8XEAHR108HG78NMA995BE8QAT5GC1S7E80"
        let keyMaterial = "PKZ42Z56SVK2796HG1QYBRJ6ZQM2T9QGA3JA4AAZ8G7CWK9FPX175Q9JE5P0ZAX3HWWPHAQV4DPCK10R9X3SAXHRV0WF06BHEC2ZTKR"

        XCTAssertEqual(Crockford.encode(try TalerCrypto.eddsaPublicKey(seed: try Crockford.decode(eddsaPrivate))), eddsaPublic)
        XCTAssertEqual(
            Crockford.encode(try TalerCrypto.keyExchangeEcdhEddsa(
                ecdhPrivateKey: try Crockford.decode(ecdhePrivate),
                eddsaPublicKey: try Crockford.decode(eddsaPublic),
            )),
            keyMaterial,
        )
    }

    func testSecretBoxStaysNaClCompatible() {
        let key = Data((0..<32).map { UInt8($0) })
        let nonce = Data((0..<24).map { UInt8($0 + 32) })
        let message = Data("GNU Taler Noble migration".utf8)
        let ciphertext = Self.hex("dcc697b8d4db9561740a192bf466eac4" + "b6171885194636f37b151b016e24d2d4d4dbdaf9906d4a1bd2")

        XCTAssertEqual(XSalsa20Poly1305.open(ciphertext, nonce: nonce, key: key), message)
        XCTAssertEqual(XSalsa20Poly1305.seal(message, nonce: nonce, key: key), ciphertext)
    }

    func testSecretBoxRejectsTamperedCiphertext() {
        let key = Data((0..<32).map { UInt8($0) })
        let nonce = Data((0..<24).map { UInt8($0 + 32) })
        var ciphertext = Self.hex("dcc697b8d4db9561740a192bf466eac4" + "b6171885194636f37b151b016e24d2d4d4dbdaf9906d4a1bd2")
        ciphertext[0] ^= 1
        XCTAssertNil(XSalsa20Poly1305.open(ciphertext, nonce: nonce, key: key))
    }

    func testSecretBoxRoundTripAcrossSeveralBlocks() {
        let key = Data((0..<32).map { UInt8(255 - $0) })
        let nonce = Data((0..<24).map { UInt8($0 * 3) })
        let message = Data((0..<300).map { UInt8($0 % 251) })
        let sealed = XSalsa20Poly1305.seal(message, nonce: nonce, key: key)!
        XCTAssertEqual(XSalsa20Poly1305.open(sealed, nonce: nonce, key: key), message)
    }

    func testCrockfordNormalizesAmbiguousCharacters() throws {
        // 8 Zeichen = 40 Bit = 5 Bytes ohne Restbits.
        XCTAssertEqual(try Crockford.decode("O1iLu000"), try Crockford.decode("0111V000"))
        XCTAssertThrowsError(try Crockford.decode("01"), "Restbits ungleich 0 sind ungueltig")
        XCTAssertThrowsError(try Crockford.decodeFixed("0", expectedLength: 32))
    }

    static func hex(_ value: String) -> Data {
        var data = Data()
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            data.append(UInt8(value[index..<next], radix: 16)!)
            index = next
        }
        return data
    }
}
