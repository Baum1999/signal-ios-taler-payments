//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Beim "Fuer mich loeschen" einer Taler-Nachricht zusaetzlich jede eigene,
/// noch offene Zahlung im geloeschten Nachrichtenkorpus rein lokal auf
/// LOKAL_ABGEBROCHEN setzen - dieselbe Bedingung wie der Abbrechen-Knopf
/// (`TalerCardActionGate.showCancel`), damit weder fremde noch bereits
/// entschiedene Zahlungen angefasst werden. Wirkt automatisch auch fuer
/// Gruppen-Split-Nachrichten (mehrere URIs im Body, unabhaengig geprueft).
/// Spiegel von `cancelCancelablePaymentsForDeletedMessages`
/// (TalerAcceptRejectActions.kt, signal-android).
///
/// Bewusst rein lokal und sofort, ohne Talers eigene Abbrechen-UI: Loeschen
/// soll den Vorgang ohne weitere Nutzerinteraktion beenden. Kein Netzwerk,
/// keine Rueckerstattung, Signal bewegt kein Geld (Regel 1).
public enum TalerLocalDelete {

    /// Muss in derselben Schreibtransaktion vor dem Loeschen aufgerufen
    /// werden. Erzeugt je abgebrochenem Anteil eine lokale Statuszeile.
    public static func cancelOpenOwnPayments(in interactions: [TSInteraction], tx: DBWriteTransaction) {
        for interaction in interactions {
            guard let message = interaction as? TSMessage, let body = message.body else {
                continue
            }
            for uri in TalerMessageBody.uris(in: body) {
                guard
                    let record = TalerPaymentStore.record(forUri: uri, tx: tx),
                    TalerCardActionGate.showCancel(record)
                else {
                    continue
                }
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                guard TalerPaymentStore.updateStatus(uri: uri, status: .lokalAbgebrochen, now: now, tx: tx) else {
                    continue
                }
                TalerStatusLine.insert(status: .lokalAbgebrochen, threadUniqueId: record.threadUniqueId, tx: tx)
            }
        }
    }
}
