//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Pruefung und Aufbereitung eines SEND-Ruecksprungs (link-protokoll.md 3, 8):
/// entscheidet, OB Signal eine Zahlungsnachricht verschickt, und baut den
/// Klartext-Body plus die Payload fuer Proto-Feld 9000. Reine Logik ohne
/// UIKit, damit sie ohne App testbar ist. Das eigentliche Versenden macht die
/// UI (TalerReturnHandler, Signal-Target) ueber den normalen Text-Sendepfad.
///
/// Alle Eingaben sind angreiferkontrolliert (link-protokoll.md 2.5): der
/// `status` ist nur ein Trigger und wird nie angezeigt. Jede URI muss sowohl
/// `TalerUriDetector.isExactlyOneUri` bestehen (der ganze String ist genau
/// eine URI) als auch von `TalerUriParser.classify` als PAY_PUSH oder PAY_PULL
/// erkannt werden; schlaegt EINE URI fehl, wird NICHTS gesendet - kein
/// Teilversand, kein Rueckfall auf talerUri (link-protokoll.md 8,
/// Fehlerfall-Tabelle).
public enum TalerSendPayload {

    /// Praeft einen SEND-Ruecksprung und liefert Body und Feld-9000-Payload,
    /// oder nil, wenn nichts gesendet werden darf:
    /// - `status` nicht `ready` (auch `cancelled` mit mitgeschickter URI),
    /// - weder gueltiges `talerPaymentData` noch gueltiges `talerUri`,
    /// - eine URI ungueltig oder nicht PAY_PUSH/PAY_PULL (z. B. withdraw).
    ///
    /// Prioritaet wie Android (TalerReturnActivity.kt): `talerPaymentData`
    /// (JSON) vor `talerUri`; ist das JSON nicht parsbar oder seine URI-Liste
    /// leer, gilt `talerUri` als Rueckfall fuer aeltere Taler-Versionen.
    public static func build(from ret: TalerReturn) -> (body: String, payload: TalerPaymentPayload)? {
        // Nur ready: bei cancelled (oder fehlendem/unbekanntem Status) passiert
        // nichts, selbst wenn talerUri/talerPaymentData mitgeschickt wurden.
        guard ret.status == .ready else {
            return nil
        }

        if let json = ret.talerPaymentData, let paymentData = TalerPaymentData.parseOrNil(json) {
            if !paymentData.uri.isEmpty {
                // Die JSON-Liste ist autoritativ: besteht eine ihrer URIs die
                // Pruefung nicht, wird nichts gesendet (Rueckgabe nil), ohne
                // Rueckfall auf talerUri.
                return build(
                    uris: paymentData.uri,
                    legacyText: paymentData.legacyText,
                    includeSelf: paymentData.includeSelf,
                    totalAmount: paymentData.totalAmount
                )
            }
            // Parsbar, aber leere URI-Liste: Rueckfall auf talerUri
            // (link-protokoll.md 3, Regel 2).
        }

        if let uri = ret.talerUri {
            return buildFromSingleUri(uri)
        }
        return nil
    }

    /// JSON-Pfad (Gruppen-Split: mehrere URIs). Body wie Android
    /// (TalerReturnActivity.kt, sendComposedPaymentWithData): erst der
    /// Legacy-Text, Leerzeile, dann die URIs - jeweils durch eine Leerzeile
    /// getrennt, damit TalerUriDetector sie einzeln findet und der Klartext
    /// lesbar bleibt (der Legacy-Text sagt "copy the URI below", das stimmt
    /// nur mit den URIs NACH dem Text).
    private static func build(
        uris: [String],
        legacyText: String,
        includeSelf: Bool?,
        totalAmount: String?
    ) -> (body: String, payload: TalerPaymentPayload)? {
        for uri in uris {
            guard sendableKind(uri) != nil else {
                return nil
            }
        }
        let body = legacyText + "\n\n" + uris.joined(separator: "\n\n")
        let payload = TalerPaymentPayload(
            uris: uris,
            version: 1,
            isGroupSplit: uris.count > 1,
            includeSelf: includeSelf,
            totalAmount: totalAmount
        )
        return (body, payload)
    }

    /// Rueckfall-Pfad ohne JSON (aeltere Taler-Versionen): eine URI, Body als
    /// lokalisierter Einzeiler wie Android (sendComposedPayment), plus Feld
    /// 9000 mit genau dieser URI (link-protokoll.md 3, Regel 5).
    private static func buildFromSingleUri(_ uri: String) -> (body: String, payload: TalerPaymentPayload)? {
        guard let kind = sendableKind(uri) else {
            return nil
        }
        let kindLabel = kind == .payPull ? TalerStrings.wireKindPayPull : TalerStrings.wireKindPayPush
        let format = kind == .payPull ? TalerStrings.requestMessageFormat : TalerStrings.sendMessageFormat
        let body = String(format: format, kindLabel, uri)
        return (body, TalerPaymentPayload(uris: [uri], version: 1, isGroupSplit: false))
    }

    /// Einziges Gate zwischen den angreiferkontrollierten Werten des
    /// Ruecksprungs und einer echten ausgehenden Nachricht: syntaktisch genau
    /// eine URI UND Zahlungs-Art (PAY_PUSH/PAY_PULL). Alles andere (PAY,
    /// WITHDRAW, REFUND, ext+taler, payto) wird nicht gesendet.
    private static func sendableKind(_ uri: String) -> TalerUriKind? {
        guard TalerUriDetector.isExactlyOneUri(uri) else {
            return nil
        }
        guard let kind = TalerUriParser.classify(uri) else {
            return nil
        }
        return (kind == .payPush || kind == .payPull) ? kind : nil
    }
}
