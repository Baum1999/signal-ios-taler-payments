//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation

/// Die zusammengesetzten Taler-Krypto-Operationen fuer den Peer-Contract-Abruf.
/// Gegenstuecke in wallet-core: `eddsaGetPublic`, `keyExchangeEcdhEddsa`,
/// `hash` (`taler-util/src/taler-crypto.ts`); auf Android `TalerCrypto.kt`
/// und `Ed25519.kt`.
///
/// X25519 und Ed25519 kommen aus CryptoKit (RFC 7748/8032, konstantzeitig);
/// nur die Montgomery-Konvertierung ist eigene Arithmetik
/// (`Curve25519Field`).
public enum TalerCrypto {

    public enum Error: Swift.Error {
        case invalidKey
    }

    public static func sha512(_ data: Data) -> Data {
        Data(SHA512.hash(data: data))
    }

    /// Ed25519-Public-Key aus einem 32-Byte-Seed (Taler: `eddsaGetPublic`).
    public static func eddsaPublicKey(seed: Data) throws -> Data {
        guard seed.count == 32 else {
            throw Error.invalidKey
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation
    }

    /// Gemeinsames Geheimnis zwischen einem ECDHE-Privatschluessel und einem
    /// EdDSA-Public-Key: Konvertierung auf die Montgomery-Kurve, X25519, dann
    /// SHA-512 ueber das Ergebnis.
    public static func keyExchangeEcdhEddsa(ecdhPrivateKey: Data, eddsaPublicKey: Data) throws -> Data {
        guard ecdhPrivateKey.count == 32, let montgomery = Curve25519Field.edwardsToMontgomery(eddsaPublicKey) else {
            throw Error.invalidKey
        }
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: ecdhPrivateKey)
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: montgomery)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let sharedBytes = shared.withUnsafeBytes { Data($0) }
        return sha512(sharedBytes)
    }
}
