//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Pruefung und Body-Bau eines REFUND-Ruecksprungs (link-protokoll.md 4, 8):
/// entscheidet, OB Signal einen Rueckerstattungs-Entwurf vorbereitet, und baut
/// dessen Klartext-Body. Reine Logik ohne UIKit, damit sie ohne App testbar
/// ist. Speichern als Entwurf (Text plus Zitat-Antwort auf die
/// Originalnachricht) und Oeffnen des Chats macht die UI (TalerReturnHandler,
/// Signal-Target) - KEIN automatisches Senden wie beim SEND-Intent: der Nutzer
/// verschickt selbst (link-protokoll.md Abschnitt 4).
///
/// Body exakt wie Android (TalerReturnActivity.kt, REFUND-Zweig): der Header
/// "Refund: " VOR dem Taler-seitigen Verwendungszweck (legacyText), Leerzeile,
/// dann die URIs im Klartext - Text-zuerst, damit legacyText ("copy the URI
/// below") stimmt und TalerUriDetector die URIs einzeln findet. Rueckfall ohne
/// JSON (aeltere Taler-Versionen): Header direkt vor der URI.
///
/// Alle Eingaben sind angreiferkontrolliert. Da der Body nur als lokaler
/// Entwurf gespeichert wird (der Nutzer prueft ihn vor dem Senden), besteht
/// die URI-Pruefung nur aus `TalerUriDetector.isExactlyOneUri` je URI -
/// anders als beim SEND-Intent kein classify auf PAY_PUSH/PAY_PULL. Schlaegt
/// EINE URI fehl, wird NICHTS vorbereitet - kein Teilentwurf, kein Rueckfall
/// auf talerUri.
public enum TalerRefundPayload {

    /// Praeft einen REFUND-Ruecksprung und liefert den Entwurfs-Body, oder
    /// nil, wenn kein Entwurf angelegt werden darf:
    /// - `status` nicht `ready` (auch `cancelled` mit mitgeschickter URI),
    /// - weder gueltiges `talerPaymentData` noch gueltiges `talerUri`,
    /// - eine URI syntaktisch ungueltig (keine "genau eine URI").
    ///
    /// Prioritaet wie Android: `talerPaymentData` (JSON) vor `talerUri`; ist
    /// das JSON nicht parsbar oder seine URI-Liste leer, gilt `talerUri` als
    /// Rueckfall.
    public static func build(from ret: TalerReturn) -> String? {
        // Nur ready: bei cancelled (oder fehlendem/unbekanntem Status) passiert
        // nichts, selbst wenn talerUri/talerPaymentData mitgeschickt wurden.
        guard ret.status == .ready else {
            return nil
        }

        if let json = ret.talerPaymentData, let paymentData = TalerPaymentData.parseOrNil(json) {
            if !paymentData.uri.isEmpty {
                // Die JSON-Liste ist autoritativ: besteht eine ihrer URIs die
                // Pruefung nicht, wird kein Entwurf angelegt, ohne Rueckfall.
                return build(
                    uris: paymentData.uri,
                    legacyText: paymentData.legacyText
                )
            }
            // Parsbar, aber leere URI-Liste: Rueckfall auf talerUri.
        }

        if let uri = ret.talerUri {
            return buildFromSingleUri(uri)
        }
        return nil
    }

    /// JSON-Pfad: Header + Taler-seitiger Verwendungszweck ZUERST, Leerzeile,
    /// dann die URIs (jeweils durch eine Leerzeile getrennt) - derselbe Aufbau
    /// wie beim Senden, nur mit Header vor legacyText.
    private static func build(uris: [String], legacyText: String) -> String? {
        for uri in uris {
            guard TalerUriDetector.isExactlyOneUri(uri) else {
                return nil
            }
        }
        return String(format: TalerStrings.refundMessageFormat, legacyText)
            + "\n\n" + uris.joined(separator: "\n\n")
    }

    /// Rueckfall-Pfad ohne JSON (aeltere Taler-Versionen): Header direkt vor
    /// der URI (Android: getString(TalerFork_refund_message, talerUri)).
    private static func buildFromSingleUri(_ uri: String) -> String? {
        guard TalerUriDetector.isExactlyOneUri(uri) else {
            return nil
        }
        return String(format: TalerStrings.refundMessageFormat, uri)
    }
}
