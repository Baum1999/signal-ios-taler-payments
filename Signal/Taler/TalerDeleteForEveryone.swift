//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// Startet den echten Taler-Abbruch beim "Fuer alle loeschen" (S10, Gap A,
/// Zielbild 6.2). Genau ein Aufruf je Einstiegspunkt, INNERHALB der
/// Schreibtransaktion und VOR dem Loeschen - danach waere der Nachrichtenkoerper
/// (und damit die URIs) weg. Das Loeschen selbst wird weder blockiert noch
/// verzögert: Der compose-abort-Link wird erst nach Abschluss der Transaktion
/// auf dem Main-Thread geöffnet.
///
/// Signal bewegt dabei kein Geld (Regel 1) - abbrechen bestätigt der Nutzer in
/// der Sammel-Bestätigung der Taler-UI. Die URIs sind Inhaberpapiere: Sie
/// erscheinen in keiner Logmeldung und keiner Fehlermeldung.
enum TalerDeleteForEveryone {

    /// Muss in derselben Schreibtransaktion wie das Loeschen, und vor ihm,
    /// aufgerufen werden. Keine betroffenen URIs -> no-op (normales Loeschen).
    /// Taler nicht installiert oder das Oeffnen scheitert -> Fallback wie
    /// "Fuer mich loeschen" (lokal LOKAL_ABGEBROCHEN plus Statuszeile).
    /// Kommt kein Ruecksprung aus Taler, bleibt der Status OFFEN (Zielbild 6.2);
    /// die Ergebnisse uebernimmt TalerReturnHandler (Fall .abort).
    static func abortOwnOpenPayments(in interactions: [TSInteraction], threadUniqueId: String, tx: DBWriteTransaction) {
        // Betroffene URIs in derselben Transaktion ermitteln (Gate-Logik in
        // TalerAbortPlan): erst alle URIs der Nachrichtenkoerper sammeln, dann
        // die Records dazu lesen.
        var uriList: [String] = []
        var seen = Set<String>()
        for interaction in interactions {
            guard let message = interaction as? TSMessage, let body = message.body else {
                continue
            }
            for uri in TalerMessageBody.uris(in: body) where seen.insert(uri).inserted {
                uriList.append(uri)
            }
        }
        let records = uriList.map { TalerPaymentStore.record(forUri: $0, tx: tx) }
        let affectedUris = TalerAbortPlan.affectedUris(records: records)
        guard !affectedUris.isEmpty else {
            return
        }

        // Erst nach Abschluss der Loesch-Transaktion oeffnen; die URIs sind
        // hier bereits kopiert. Main-Dispatch, weil das Oeffnen (und die
        // Installations-Pruefung) UIKit brauchen - die Transaktion selbst
        // kann auf einem Hintergrund-Queue laufen (awaitableWrite).
        let uris = affectedUris
        DispatchQueue.main.async {
            launch(uris: uris, threadUniqueId: threadUniqueId)
        }
    }

    /// Registriert den ABORT-Eintrag im Correlation-Store und oeffnet
    /// `talerlink://compose-abort` (link-protokoll.md 5). Ohne Taler bzw.
    /// bei gescheitertem Oeffnen: lokaler Fallback.
    private static func launch(uris: [String], threadUniqueId: String) {
        // Main-Thread (siehe oben); frisch pruefen wie beim Tippen.
        guard TalerInstallation.refresh() else {
            applyLocalFallback(uris: uris)
            return
        }
        let correlationId = TalerCorrelationStore.shared.register(
            TalerCorrelationEntry(
                intent: .abort,
                threadUniqueId: threadUniqueId,
                uri: nil,
                uris: uris,
                quoteInteractionUniqueId: nil
            )
        )
        let url = TalerLinks.composeAbort(uris: uris, correlationId: correlationId)
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                // Link kam nicht an: Store-Eintrag bleibt ungenutzt und laeuft
                // nach der TTL ab; stattdessen lokaler Fallback, damit das
                // Verhalten nie unter dem heutigen bleibt.
                applyLocalFallback(uris: uris)
            }
        }
    }

    /// Fallback wie "Fuer mich loeschen" (link-protokoll.md 5, Fehlerfall
    /// "Taler nicht installiert"): jede betroffene URI rein lokal auf
    /// LOKAL_ABGEBROCHEN setzen plus lokale Statuszeile - dieselben
    /// Schreibwege wie TalerLocalDelete.cancelOpenOwnPayments. Das kann hier
    /// nicht direkt aufgerufen werden, weil der Nachrichtenkoerper zu diesem
    /// Zeitpunkt schon geloescht ist; die URIs wurden vorher gesichert. Keine
    /// Rueckerstattung, kein Netzwerk - Signal bewegt kein Geld (Regel 1).
    private static func applyLocalFallback(uris: [String]) {
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            for uri in uris {
                guard
                    let record = TalerPaymentStore.record(forUri: uri, tx: tx),
                    // Gate erneut pruefen: seit dem Loeschen kann die Zahlung
                    // angenommen worden sein (nie ANGENOMMEN ueberschreiben).
                    TalerCardActionGate.showCancel(record),
                    TalerPaymentStore.updateStatus(uri: uri, status: .lokalAbgebrochen, now: now, tx: tx)
                else {
                    continue
                }
                // Statuszeile nur beim echten Wechsel (Deduplizierung wie im
                // lokalen Loesch-Hook).
                if record.status != .lokalAbgebrochen {
                    TalerStatusLine.insert(status: .lokalAbgebrochen, threadUniqueId: record.threadUniqueId, tx: tx)
                }
            }
        }
    }
}
