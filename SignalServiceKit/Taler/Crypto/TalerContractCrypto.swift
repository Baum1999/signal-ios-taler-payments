//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Entschluesselt die Contract-Terms einer Peer-Zahlung, wie sie der Exchange
/// unter `contracts/$CONTRACT_PUB` ausliefert. Gegenstueck zu wallet-cores
/// `decryptContractForMerge`/`decryptContractForDeposit` und zu
/// `TalerContractCrypto.kt` (signal-android).
///
///  - `keySeed = SHA-512(X25519(contractPriv, toMontgomery(purse_pub)))`
///  - `key = kdf(32, ikm = keySeed, salt = nonce, info = "p2p-merge-contract" | "p2p-deposit-contract")`
///  - `econtract = nonce(24) || secretbox`
///  - Klartext: `uint32BE tag | uint32BE contentLength | mergePriv (32, nur pay-push) | zlib(JSON + "\0")`
public enum TalerContractCrypto {
    private static let nonceSize = 24
    private static let headerSize = 8
    private static let mergePrivateKeySize = 32
    private static let maxContractTermsLength: UInt32 = 1024 * 1024 * 40

    public enum Direction: Sendable {
        /// pay-push: der Empfaenger fuehrt die Purse zusammen.
        case merge
        /// pay-pull: der Schuldner zahlt in die Purse ein.
        case deposit

        var formatTag: UInt32 { self == .merge ? 0 : 1 }
        var kdfInfo: String { self == .merge ? "p2p-merge-contract" : "p2p-deposit-contract" }
        var payloadOffset: Int { self == .merge ? headerSize + mergePrivateKeySize : headerSize }

        public init?(_ kind: TalerUriKind) {
            switch kind {
            case .payPush: self = .merge
            case .payPull: self = .deposit
            default: return nil
            }
        }
    }

    /// Contract-Terms-JSON, oder `nil`, wenn das Chiffrat nicht zu Schluessel
    /// und Richtung passt oder formal ungueltig ist.
    public static func decrypt(encryptedContract: Data, pursePublicKey: Data, contractPrivateKey: Data, direction: Direction) -> String? {
        let encrypted = Data(encryptedContract)
        guard encrypted.count > nonceSize else {
            return nil
        }
        guard let keySeed = try? TalerCrypto.keyExchangeEcdhEddsa(ecdhPrivateKey: contractPrivateKey, eddsaPublicKey: pursePublicKey) else {
            return nil
        }
        let nonce = encrypted.prefix(nonceSize)
        let key = TalerKdf.derive(outputLength: 32, ikm: keySeed, salt: Data(nonce), info: Data(direction.kdfInfo.utf8))
        guard let plaintext = XSalsa20Poly1305.open(Data(encrypted.dropFirst(nonceSize)), nonce: Data(nonce), key: key) else {
            return nil
        }
        let bytes = [UInt8](plaintext)
        guard bytes.count > direction.payloadOffset else {
            return nil
        }
        guard readUInt32BigEndian(bytes, 0) == direction.formatTag else {
            return nil
        }
        let contentLength = readUInt32BigEndian(bytes, 4)
        guard contentLength >= 1, contentLength <= maxContractTermsLength else {
            return nil
        }
        guard let inflated = TalerZlib.inflate(Data(bytes[direction.payloadOffset...]), expectedLength: Int(contentLength)) else {
            return nil
        }
        // Die Referenz haengt vor dem Komprimieren ein '\0' an.
        return String(data: inflated.dropLast(), encoding: .utf8)
    }

    /// Gegenrichtung (wallet-core `encryptContractForMerge`/`ForDeposit`) -
    /// nur fuer Tests.
    static func encrypt(contractTermsJson: String, pursePublicKey: Data, contractPrivateKey: Data, mergePrivateKey: Data?, direction: Direction, nonce: Data) -> Data? {
        guard let keySeed = try? TalerCrypto.keyExchangeEcdhEddsa(ecdhPrivateKey: contractPrivateKey, eddsaPublicKey: pursePublicKey) else {
            return nil
        }
        var raw = Data(contractTermsJson.utf8)
        raw.append(0)
        guard let compressed = TalerZlib.deflate(raw) else {
            return nil
        }
        var plaintext = Data()
        appendUInt32BigEndian(&plaintext, direction.formatTag)
        appendUInt32BigEndian(&plaintext, UInt32(raw.count))
        if direction == .merge {
            plaintext.append(mergePrivateKey ?? Data(count: mergePrivateKeySize))
        }
        plaintext.append(compressed)
        let key = TalerKdf.derive(outputLength: 32, ikm: keySeed, salt: nonce, info: Data(direction.kdfInfo.utf8))
        guard let box = XSalsa20Poly1305.seal(plaintext, nonce: nonce, key: key) else {
            return nil
        }
        return nonce + box
    }

    private static func readUInt32BigEndian(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    private static func appendUInt32BigEndian(_ data: inout Data, _ value: UInt32) {
        data.append(contentsOf: [UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)])
    }
}
