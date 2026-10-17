//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation

/// Nicht umkehrbarer Kurz-Hash einer Taler-URI, ausschliesslich fuer
/// Log-Korrelation. Die URI selbst ist ein Inhaberpapier und darf nirgends
/// im Klartext landen (kein Log, keine Fehlermeldung). Spiegel von
/// `TalerCorrelation.shortHash` (signal-android): SHA-256, 12 Hex-Zeichen.
public enum TalerCorrelation {
    public static func shortHash(_ uri: String) -> String {
        let digest = SHA256.hash(data: Data(uri.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }
}
