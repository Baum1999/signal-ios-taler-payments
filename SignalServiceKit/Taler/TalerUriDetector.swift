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
public enum TalerUriDetector {

    private static let uriRegex: NSRegularExpression = {
        // Gleiches Muster wie Android: (?i)\b(?:taler|ext\+taler|payto)://\S+
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: #"\b(?:taler|ext\+taler|payto)://\S+"#, options: [.caseInsensitive])
    }()

    private static let trailingPunctuation: Set<Character> = [".", ",", ")", "]", "}", "!", "?", ";", ":"]

    public static func findUris(_ text: String) -> [String] {
        let nsText = text as NSString
        var result: [String] = []
        for match in uriRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            var value = nsText.substring(with: match.range)
            while let last = value.last, trailingPunctuation.contains(last) {
                value.removeLast()
            }
            if !result.contains(value) {
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
