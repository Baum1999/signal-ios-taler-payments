//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Reine Entscheidungslogik des echten Abbruchs beim "Fuer alle loeschen"
/// (S10, Gap A, Zielbild 6.2; Spiegel der Logik aus dem Android-Plan
/// 2026-09-28-taler-payment-delete-abort.md: `eligibleUris` und
/// `TalerAbortResults.toPaymentStatus`). Kein DB-Zugriff, kein UIKit: Der
/// Aufrufer liest die Records in seiner Transaktion und schreibt die
/// Ergebnisse selbst. URIs sind Inhaberpapiere und werden nie geloggt.
public enum TalerAbortPlan {

    /// URIs, fuer die das Abbruch-Gate gilt (eigene, noch offene pay-push,
    /// `TalerCardActionGate.showCancel`) - nur diese darf Signal Taler zum
    /// Abbrechen vorlegen. Eintraege ohne Record (URI nicht verifiziert),
    /// fremde, bereits entschiedene oder nicht-pay-push-Zahlungen fallen
    /// heraus; Dubletten werden einmalig uebernommen, die Reihenfolge bleibt
    /// erhalten.
    public static func affectedUris(records: [TalerPaymentRecord?]) -> [String] {
        var seen = Set<String>()
        var uris: [String] = []
        for record in records {
            guard let record, TalerCardActionGate.showCancel(record), seen.insert(record.uri).inserted else {
                continue
            }
            uris.append(record.uri)
        }
        return uris
    }

    /// Bildet die Ergebnisse des Ruecksprungs auf Statusaenderungen ab
    /// (link-protokoll.md 9): `aborted` -> UNGUELTIG, `expired` ->
    /// ABGELAUFEN, `already_claimed` und `declined` -> keine erzwungene
    /// Aenderung (`nil`; der Aufrufer stoesst stattdessen einen Refresh an -
    /// der echte Zustand kommt aus Contract/Exchange, nie aus dem Link).
    /// Ergebnisse mit einer URI, die nicht in `allowed` steht, werden
    /// komplett ignoriert (Ziel-Validierung). Die Reihenfolge des
    /// Ruecksprungs bleibt erhalten.
    public static func apply(results: [TalerAbortResult], allowed: [String]) -> [(uri: String, status: TalerPaymentStatus?)] {
        let allowedUris = Set(allowed)
        var updates: [(uri: String, status: TalerPaymentStatus?)] = []
        for result in results {
            guard allowedUris.contains(result.uri) else {
                continue
            }
            switch result.outcome {
            case .aborted:
                updates.append((result.uri, .ungueltig))
            case .expired:
                updates.append((result.uri, .abgelaufen))
            case .alreadyClaimed, .declined:
                updates.append((result.uri, nil))
            }
        }
        return updates
    }
}
