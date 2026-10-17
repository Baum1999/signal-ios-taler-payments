//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Zustellstatus einer ausgehenden Taler-Nachricht fuer die Kreis-Icons im
/// Nachricht-Footer und in der Chatliste. Spiegel von
/// `TalerDeliveryStatusPresenter.kt` (signal-android):
///
/// - `nil`: keine Taler-Zahlungs-URI im Nachrichtentext - der Aufrufer zeigt
///   die normalen Haken.
/// - `.paid`: ALLE enthaltenen URIs sind angenommen - eigenstaendiges
///   `TALER_PAID`-Icon.
/// - `.open`: Taler-Zahlung, aber noch nicht vollstaendig angenommen -
///   Platzhalter; der Aufrufer unterscheidet selbst weiter nach
///   pending/delivered/read (zeigt also die normalen Haken).
public enum TalerDeliveryStatus: Equatable, Sendable {
    case paid
    case open

    /// Reine Logik. `uris` sind die Taler-URIs der Nachricht,
    /// `records` die zugehoerigen Vorgaenge in derselben Reihenfolge
    /// (`nil`, wenn es zu einer URI keinen Vorgang gibt). Fehlende Records
    /// zaehlen wie Android als "nicht angenommen".
    public static func compute(uris: [String], records: [TalerPaymentRecord?]) -> TalerDeliveryStatus? {
        guard !uris.isEmpty else {
            return nil
        }
        let allAccepted = uris.indices.allSatisfy { index in
            guard records.indices.contains(index) else {
                return false
            }
            return records[index]?.status == .angenommen
        }
        return allAccepted ? .paid : .open
    }

    /// Ladepfad-Helfer (Chatliste, Footer): `true`, wenn die Nachricht
    /// Taler-URIs enthaelt und ALLE angenommen sind. Nur mit einer
    /// Lese-Transaktion aufrufen, nie im Render-Pfad.
    public static func isPaid(message: TSMessage, tx: DBReadTransaction) -> Bool {
        var uris: [String] = []
        if
            let rowId = message.sqliteRowId,
            let structured = TalerPaymentStore.paymentMessage(interactionId: rowId, tx: tx)
        {
            uris = structured.payload.uris
        } else if let body = message.body, !body.isEmpty {
            uris = TalerMessageBody.uris(in: body)
        }
        guard !uris.isEmpty else {
            return false
        }
        let records = uris.map { TalerPaymentStore.record(forUri: $0, tx: tx) }
        return compute(uris: uris, records: records) == .paid
    }
}
