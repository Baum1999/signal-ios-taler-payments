//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Erkennt Taler-URIs (`taler://`, `ext+taler://`, `payto://`) in freiem Text.
/// Spiegel von `TalerUriDetector.kt` (signal-android).
///
/// Reine Textmustererkennung, keine Validierung: eine gefundene URI ist nur
/// ein Kandidat. Ueber Art und Gueltigkeit entscheidet danach
/// `TalerUriParser`.
///
/// `taler+http://` fehlt bewusst: Signal loest erkannte Peer-URIs
/// unaufgefordert beim Exchange auf, das soll nicht im Klartext passieren.
///
/// https-Links nach DD 103 (`https://<host>/link#...`, `TalerHttpsLink`)
/// werden nur fuer die Domains aus `TalerLinkHosts` erkannt.
///
/// Abweichung von Android: Dubletten werden nach dem entpackten Link
/// entfernt, nicht nach dem Rohtext. taler-ios teilt `taler://...` und den
/// gleichwertigen https-Link in einer Nachricht; das ist eine Zahlung, keine
/// zwei.
public enum TalerUriDetector {

    private static let uriRegex: NSRegularExpression = {
        // Gleiches Muster wie Android:
        // (?i)\b(?:taler|ext\+taler|payto)://\S+|https://(?:<hosts>)/link/?#\S+
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(
            pattern: #"\b(?:taler|ext\+taler|payto)://\S+|"# + TalerHttpsLink.linkPrefixPattern + #"\S+"#,
            options: [.caseInsensitive]
        )
    }()

    private static let trailingPunctuation: Set<Character> = [".", ",", ")", "]", "}", "!", "?", ";", ":"]

    public static func findUris(_ text: String) -> [String] {
        let nsText = text as NSString
        var result: [String] = []
        var seen = Set<String>()
        for match in uriRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            var value = nsText.substring(with: match.range)
            while let last = value.last, trailingPunctuation.contains(last) {
                value.removeLast()
            }
            if seen.insert(TalerHttpsLink.unwrap(value)).inserted {
                result.append(value)
            }
        }
        return result
    }

    /// Prueft, ob `text` GENAU eine wohlgeformte Taler-URI ist - der gesamte
    /// String, kein Praefix/Suffix, keine zweite URI. Einziges Gate zwischen
    /// den angreiferkontrollierten Parametern eines Ruecksprungs und einer
    /// echten ausgehenden Nachricht.
    public static func isExactlyOneUri(_ text: String) -> Bool {
        guard let first = findUris(text).first else {
            return false
        }
        return first == text
    }
}
