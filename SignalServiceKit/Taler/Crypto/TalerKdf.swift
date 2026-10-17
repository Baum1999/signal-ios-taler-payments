//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation

/// Talers eigene KDF, portiert aus `TalerKdf.kt` (signal-android) bzw.
/// wallet-core `kdf` (`taler-util/src/taler-crypto.ts`). Kein Standard-HKDF:
/// Extract ueber HMAC-SHA512, Expand ueber HMAC-SHA256, der Blockzaehler steht
/// am *Ende* des Puffers, `info` hinter dem vorangegangenen Block.
public enum TalerKdf {
    private static let blockSize = 32

    public static func derive(outputLength: Int, ikm: Data, salt: Data?, info: Data?) -> Data {
        let effectiveSalt = salt ?? Data(count: 64)
        let effectiveInfo = info ?? Data()

        let prk = Data(HMAC<SHA512>.authenticationCode(for: ikm, using: SymmetricKey(data: effectiveSalt)))
        let prkKey = SymmetricKey(data: prk)

        let blocks = (outputLength + blockSize - 1) / blockSize
        var output = Data()
        output.reserveCapacity(blocks * blockSize)
        var previous = Data()
        for i in 0..<blocks {
            var buffer = Data()
            buffer.append(previous)
            buffer.append(effectiveInfo)
            buffer.append(UInt8(truncatingIfNeeded: i + 1))
            previous = Data(HMAC<SHA256>.authenticationCode(for: buffer, using: prkKey))
            output.append(previous)
        }
        return output.prefix(outputLength)
    }
}
