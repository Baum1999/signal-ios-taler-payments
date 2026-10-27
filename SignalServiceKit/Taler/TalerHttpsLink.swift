//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// https-Links fuer Taler-Aktionen nach DD 103 "HTTPS Links for Wallet
/// Actions": `https://<host>/link#<aktion>`, gleichwertig `#taler://<aktion>`
/// und `#/<aktion>`. Spiegel von `net.taler.wallet.link.TalerHttpsLink`
/// (signal-android). Signal erzeugt solche Links nur im Klartext seiner
/// Zahlungsnachrichten (`TalerSendPayload`, `TalerRefundPayload`); taler-ios
/// teilt Pay-Push/Pay-Pull in dieser Form.
///
/// Der Payload steht im Fragment und wird lokal gelesen, ohne
/// Netzwerkanfrage. Nur Hosts aus `TalerLinkHosts.acceptedHosts` mit exakt dem
/// Pfad `/link` (bzw. `/link/`), keine beliebigen https-Links.
public enum TalerHttpsLink {

    private static let talerScheme = "taler://"

    /// Regex-Quelltext fuer den Anfang eines akzeptierten Links bis
    /// einschliesslich `#`. Aufrufer haengen ihre eigene Endzeichen-Klasse an
    /// und matchen case-insensitiv (TalerUriDetector).
    public static let linkPrefixPattern: String =
        "https://(?:"
        + TalerLinkHosts.acceptedHosts.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        + ")/link/?#"

    private static let linkRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: "^" + linkPrefixPattern + "(.*)$", options: [.caseInsensitive])
    }()

    // Kurzform ohne Schema: muss mit einem Aktionsnamen + "/" beginnen
    // (pay-push/..., withdraw/...), damit z.B. "javascript:..." nicht zu
    // "taler://javascript:..." wird.
    private static let shortFormRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: "^[A-Za-z0-9-]+/.*$")
    }()

    private static func isShortForm(_ text: String) -> Bool {
        shortFormRegex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// `taler://<aktion>` -> `https://<wrapHost>/link#<aktion>`. Bewusst kein
    /// Percent-Encoding: alle Zeichen eines `taler://`-Links sind im Fragment
    /// zulaessig.
    public static func wrap(_ talerUri: String) -> String {
        let trimmed = talerUri.trimmingCharacters(in: .whitespacesAndNewlines)
        let fragment = trimmed.lowercased().hasPrefix(talerScheme) ? String(trimmed.dropFirst(talerScheme.count)) : trimmed
        return "https://\(TalerLinkHosts.wrapHost)/link#\(fragment)"
    }

    /// Klartext-Form einer URI fuer Zahlungsnachrichten: `taler://` als
    /// https-Link (anklickbar in jedem Client), alles andere (payto://, ...)
    /// unveraendert.
    public static func messageLink(_ uri: String) -> String {
        uri.lowercased().hasPrefix(talerScheme) ? wrap(uri) : uri
    }

    /// Gibt den eingebetteten `taler://`-Link zurueck, falls `uri` ein
    /// akzeptierter DD-103-Link ist - sonst `uri` getrimmt, aber unveraendert.
    /// Das gilt auch fuer leere Fragmente oder fremde Schemata im Fragment;
    /// die Klassifizierung als "keine Taler-Aktion" bleibt Aufgabe von
    /// `TalerUriParser.classify`.
    public static func unwrap(_ uri: String) -> String {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        let nsTrimmed = trimmed as NSString
        guard let match = linkRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsTrimmed.length)) else {
            return trimmed
        }
        let fragment = nsTrimmed.substring(with: match.range(at: 1))
        let lower = fragment.lowercased()
        if lower.hasPrefix(talerScheme) || lower.hasPrefix("ext+" + talerScheme) {
            return fragment
        }
        if fragment.hasPrefix("/"), isShortForm(String(fragment.dropFirst())) {
            return "taler:/" + fragment
        }
        if isShortForm(fragment) {
            return talerScheme + fragment
        }
        return trimmed
    }
}
