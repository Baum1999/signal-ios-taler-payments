//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Ersetzt den Rohtext einer Taler-Zahlungsnachricht (Klartext plus volle
/// taler://-URI) in sekundaeren Anzeigeoberflaechen - Chatlisten-Vorschau,
/// Benachrichtigungs-Banner - durch ein kurzes, lokalisiertes Label. Die
/// In-Chat-Karte bleibt unberuehrt; Details (URI, Kopieren, QR) liefert sie.
///
/// Spiegel von `TalerPreviewText.kt` (signal-android): gleiche Faelle, gleiche
/// Reihenfolge, Kommentare verweisen aufeinander. Bewusster Unterschied: der
/// strukturierte Payload (Feld 9000) wird hier NICHT benutzt - ein Lookup in
/// TalerPaymentStore waere ein DB-Zugriff im Renderpfad, und die Body-Heuristik
/// deckt jede Fork-gesendete Zahlung (alle enthalten URI + bekanntes Format).
///
/// Die Send-/Request-/Bestaetigungsformate sind Wire-Konstanten
/// (`TalerStrings.sendMessageFormat` etc., nicht lokalisiert) - deshalb kann
/// dieser Helper ohne UIKit/App-Kontext auskommen und reiner Swift-Code sein.
///
/// Keine Betraege, Kontonamen oder Status-Suffixe im Label: Signal kennt keine
/// Taler-Salden, und Status-Lookups pro Vorschau-Zeile waeren N DB-Zugriffe.
/// Die Vorschau sagt nur "es ist eine Taler-Zahlung dieser Art".
public enum TalerPreviewText {

    /// Liefert das lokalisierte Vorschau-Label fuer [body], oder nil, wenn der
    /// Body keine Taler-Zahlungsnachricht ist (der Aufrufer zeigt dann den
    /// normalen Body).
    ///
    /// Reihenfolge (Spiegel zu Android, dort `labelRes`):
    /// 1. Bestaetigungsformat - exakter Volltext-Match per
    ///    `TalerConfirmationDetector.match` -> Statuszeilen-Label.
    /// 2. Aeltere Fork-Versionen: `TalerPaymentData` als JSON im Body (dessen
    ///    `uri`-Liste ist die autoritative Quelle, `TalerUriDetector` haengt
    ///    auf dem kompakten JSON JSON-Syntax an die URIs).
    /// 3. Body-Heuristik: Resttext (Body abzueglich aller gefundenen URIs)
    ///    muss leer oder exakt einem der bekannten Protokollsaetze sein -
    ///    nutzergeschriebener Text um eine URI bleibt vollstaendig sichtbar.
    public static func previewLabel(body: String) -> String? {
        if TalerConfirmationDetector.match(body) != nil {
            return TalerStrings.statusLineAccepted
        }

        if let paymentData = TalerPaymentData.parseOrNil(body), !paymentData.uri.isEmpty {
            return label(forUris: paymentData.uri)
        }

        let uris = TalerUriDetector.findUris(body)
        guard !uris.isEmpty else {
            return nil
        }

        let rest = normalizeWhitespace(removeUris(body, uris))
        if rest.isEmpty {
            return label(forUris: uris)
        }

        if matchesFormat(rest, TalerStrings.acceptConfirmationFormat) {
            return TalerStrings.statusLineAccepted
        }
        if matchesFormat(rest, TalerStrings.sendMessageFormat) || matchesFormat(rest, TalerStrings.requestMessageFormat) {
            return label(forUris: uris)
        }
        if rest == normalizeWhitespace(TalerStrings.legacyText) {
            return label(forUris: uris)
        }

        return nil
    }

    /// Label je nach URI-Anzahl: mehr als eine URI ist ein Gruppen-Split
    /// (`previewGroupSplit`), sonst Kind-Label der ersten URI. Nicht
    /// klassifizierbare URIs (z. B. payto://) fallen auf kindUnknown -
    /// kein Crash, keine URI im Label. Spiegel zu labelForUris (Android).
    private static func label(forUris uris: [String]) -> String {
        if uris.count > 1 {
            return TalerStrings.previewGroupSplit
        }
        switch TalerUriParser.classify(uris[0]) {
        case .payPush: return TalerStrings.kindPayPush
        case .payPull: return TalerStrings.kindPayPull
        case .pay: return TalerStrings.kindPay
        case .withdraw: return TalerStrings.kindWithdraw
        case .refund: return TalerStrings.kindRefund
        case nil: return TalerStrings.kindUnknown
        }
    }

    /// Vergleicht den normalisierten Resttext gegen ein Wire-Nachrichtenformat
    /// (`acceptConfirmationFormat` / `sendMessageFormat` / `requestMessageFormat`):
    /// Das ERSTE "%@" steht fuer das Wire-Kind-Label, das zweite fuer die URI
    /// (im Resttext entfaellt es). Spiegel zu matchesFormat (Android, dort gegen
    /// alle sechs lokalisierten Kind-Labels; hier sind die Wire-Kind-Labels feste
    /// Konstanten, sendbar sind nur payPush/payPull - TalerSendPayload.sendableKind).
    private static func matchesFormat(_ normalizedRest: String, _ format: String) -> Bool {
        guard let labelRange = format.range(of: "%@") else {
            return false
        }
        let kindLabels = [TalerStrings.wireKindPayPush, TalerStrings.wireKindPayPull]
        return kindLabels.contains { kindLabel in
            let expected = String(format[..<labelRange.lowerBound]) + kindLabel + String(format[labelRange.upperBound...])
            return normalizedRest == normalizeWhitespace(expected.replacingOccurrences(of: "%@", with: ""))
        }
    }

    /// Spiegel zu removeUris (Android).
    private static func removeUris(_ body: String, _ uris: [String]) -> String {
        var rest = body
        for uri in uris {
            rest = rest.replacingOccurrences(of: uri, with: "")
        }
        return rest
    }

    /// trim plus zusammengefallene Leerzeichen - Spiegel zu normalizeWhitespace (Android).
    private static func normalizeWhitespace(_ text: String) -> String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
