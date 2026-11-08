//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation

/// Link Taler -> Signal "zur Zahlungsnachricht springen"
/// (link-protokoll.md 12): `<returnScheme>://taler-open?v=1&uriHash=<hex>`.
///
/// Taler schickt nicht die Zahlungs-URI (ein Inhaberpapier, das iOS an jede
/// App geben koennte, die das Scheme registriert), sondern nur deren
/// SHA-256. Signal findet die URI unter den eigenen Vorgaengen wieder. Der
/// Link loest nur Navigation und einen Status-Abruf aus, keine Geldbewegung
/// und keine Statusaenderung: ein gefaelschter Link kann hoechstens einen
/// Chat oeffnen, in dem eine Zahlung mit genau diesem Hash liegt.
public enum TalerOpenLink {

    public static let host = "taler-open"

    /// Mehr Hashes werden ignoriert (ein Gruppen-Split hat nie mehr Anteile
    /// pro Nachricht, spec-multi-uri-link.md).
    public static let maxHashes = 32

    /// SHA-256 ueber die UTF-8-Bytes der URI, 64 Hex-Zeichen klein -
    /// dieselbe Rechnung wie der Schluessel des `OwnUriStore` in Taler-iOS.
    public static func uriHash(_ uri: String) -> String {
        SHA256.hash(data: Data(uri.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Scheme `TalerLinks.returnScheme` und Host `taler-open`, Gross-/
    /// Kleinschreibung egal.
    public static func isOpenUrl(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme?.lowercased() == TalerLinks.returnScheme
            && components.host?.lowercased() == host
    }

    /// Alle gueltigen `uriHash`-Werte in Link-Reihenfolge, ohne Duplikate,
    /// hoechstens `maxHashes`. Ungueltige Werte (nicht genau 64 Hex-Zeichen)
    /// werden einzeln verworfen. Leer = Link ignorieren. `v` wird nicht
    /// ausgewertet: groessere Versionen werden genauso gelesen.
    public static func parseHashes(_ url: URL) -> [String] {
        guard isOpenUrl(url),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else {
            return []
        }
        var hashes: [String] = []
        for item in items where item.name == "uriHash" {
            guard let value = item.value?.lowercased(), isHash(value), !hashes.contains(value) else {
                continue
            }
            hashes.append(value)
            if hashes.count == maxHashes {
                break
            }
        }
        return hashes
    }

    /// Erste bekannte URI, deren Hash im Link steht, in Link-Reihenfolge.
    public static func firstMatchingUri(hashes: [String], knownUris: [String]) -> String? {
        var byHash: [String: String] = [:]
        for uri in knownUris {
            byHash[uriHash(uri)] = uri
        }
        return hashes.lazy.compactMap { byHash[$0] }.first
    }

    private static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}
