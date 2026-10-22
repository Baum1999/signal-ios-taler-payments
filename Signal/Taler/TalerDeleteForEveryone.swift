//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
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
        // Nachrichtenbezogene Metadaten nur, wenn genau eine Nachricht
        // betroffen ist; bei einer Mehrfachauswahl nur Chat-Angaben.
        let messages = interactions.compactMap { $0 as? TSMessage }.filter { message in
            message.body.map { !TalerMessageBody.uris(in: $0).isEmpty } ?? false
        }
        let meta = TalerAbortLauncher.meta(
            reason: .delete,
            message: messages.count == 1 ? messages[0] : nil,
            threadUniqueId: threadUniqueId,
            uris: affectedUris,
            tx: tx
        )

        // Erst nach Abschluss der Loesch-Transaktion oeffnen; die URIs sind
        // hier bereits kopiert. Main-Dispatch, weil das Oeffnen (und die
        // Installations-Pruefung) UIKit brauchen - die Transaktion selbst
        // kann auf einem Hintergrund-Queue laufen (awaitableWrite).
        DispatchQueue.main.async {
            TalerAbortLauncher.launch(
                uris: affectedUris,
                meta: meta,
                threadUniqueId: threadUniqueId,
                fallsBackLocally: true
            )
        }
    }

    /// Fallback wie "Fuer mich loeschen" (link-protokoll.md 5, Fehlerfall
    /// "Taler nicht installiert"): jede betroffene URI rein lokal auf
    /// LOKAL_ABGEBROCHEN setzen plus lokale Statuszeile - dieselben
    /// Schreibwege wie TalerLocalDelete.cancelOpenOwnPayments. Das kann hier
    /// nicht direkt aufgerufen werden, weil der Nachrichtenkoerper zu diesem
    /// Zeitpunkt schon geloescht ist; die URIs wurden vorher gesichert. Keine
    /// Rueckerstattung, kein Netzwerk - Signal bewegt kein Geld (Regel 1).
    static func applyLocalFallback(uris: [String]) {
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

/// Startet `talerlink://compose-abort` fuer "Fuer alle loeschen" und das
/// Menue-Abbrechen mehrerer Anteile (Multi-URI-Link 5.2). Mehr als
/// `TalerAbortPlan.maxUrisPerLink` URIs gehen in Stapeln; den naechsten
/// startet TalerReturnHandler nach dem Ruecksprung des vorherigen.
enum TalerAbortLauncher {

    /// Registriert den ABORT-Eintrag des ersten Stapels und oeffnet den Link.
    /// Ohne Taler bzw. bei gescheitertem Oeffnen: `fallsBackLocally` -> lokal
    /// LOKAL_ABGEBROCHEN fuer alle URIs, sonst der Hinweis "Taler nicht
    /// installiert".
    static func launch(uris: [String], meta: TalerAbortMeta?, threadUniqueId: String, fallsBackLocally: Bool) {
        let batches = TalerAbortPlan.batches(uris)
        guard !batches.isEmpty else {
            return
        }
        open(batches: batches, meta: meta, threadUniqueId: threadUniqueId, fallsBackLocally: fallsBackLocally)
    }

    /// Naechster Stapel nach einem Ruecksprung. Leicht verzoegert, damit
    /// Signal nach dem Ruecksprung erst im Vordergrund ist.
    static func launchNext(_ continuation: TalerAbortContinuation, threadUniqueId: String) {
        guard !continuation.remainingBatches.isEmpty else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            open(
                batches: continuation.remainingBatches,
                meta: continuation.meta,
                threadUniqueId: threadUniqueId,
                fallsBackLocally: continuation.fallsBackLocally
            )
        }
    }

    private static func open(batches: [[String]], meta: TalerAbortMeta?, threadUniqueId: String, fallsBackLocally: Bool) {
        let allUris = batches.flatMap { $0 }
        // Frisch pruefen wie beim Tippen.
        guard TalerInstallation.refresh() else {
            notReachable(uris: allUris, fallsBackLocally: fallsBackLocally)
            return
        }
        let remaining = Array(batches.dropFirst())
        let correlationId = TalerCorrelationStore.shared.register(
            TalerCorrelationEntry(
                intent: .abort,
                threadUniqueId: threadUniqueId,
                uri: nil,
                uris: batches[0],
                quoteInteractionUniqueId: nil,
                abortContinuation: remaining.isEmpty ? nil : TalerAbortContinuation(
                    remainingBatches: remaining,
                    meta: meta,
                    fallsBackLocally: fallsBackLocally
                )
            )
        )
        let url = TalerLinks.composeAbort(uris: batches[0], meta: meta, correlationId: correlationId)
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                // Link kam nicht an: Store-Eintrag bleibt ungenutzt und laeuft
                // nach der TTL ab.
                notReachable(uris: allUris, fallsBackLocally: fallsBackLocally)
            }
        }
    }

    private static func notReachable(uris: [String], fallsBackLocally: Bool) {
        if fallsBackLocally {
            TalerDeleteForEveryone.applyLocalFallback(uris: uris)
        } else {
            OWSActionSheets.showActionSheet(
                title: TalerStrings.alertTalerNotInstalledTitle,
                message: TalerStrings.alertTalerNotInstalledBody
            )
        }
    }

    /// Anzeige-Metadaten (spec-multi-uri-link.md 3.1). Chat-Angaben immer,
    /// Split-Angaben nur mit `message` (genau eine betroffene Nachricht).
    /// Waehrung und Zweck stammen aus den eigenen Records der URIs, nur wenn
    /// sie eindeutig sind.
    static func meta(reason: TalerAbortReason, message: TSMessage?, threadUniqueId: String, uris: [String], tx: DBReadTransaction) -> TalerAbortMeta {
        var meta = TalerAbortMeta(reason: reason)
        if let thread = TSThread.fetchViaCache(uniqueId: threadUniqueId, transaction: tx) {
            meta.isGroup = thread.isGroupThread
            meta.recipientHint = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
            meta.memberCount = (thread as? TSGroupThread)?.groupModel.groupMembers.count
        }
        let records = uris.compactMap { TalerPaymentStore.record(forUri: $0, tx: tx) }
        let currencies = Set(records.compactMap(\.currency))
        if currencies.count == 1 {
            meta.currency = currencies.first
        }
        let summaries = Set(records.compactMap(\.summary).filter { !$0.isEmpty })
        if summaries.count == 1 {
            meta.summary = summaries.first
        }
        guard let message else {
            return meta
        }
        meta.sentAt = message.timestamp
        if let rowId = message.sqliteRowId, let payload = TalerPaymentStore.paymentMessage(interactionId: rowId, tx: tx)?.payload {
            meta.isGroupSplit = payload.isGroupSplit
            meta.includeSelf = payload.includeSelf
            meta.splitCount = payload.uris.count
            meta.totalAmount = payload.totalAmount
        }
        return meta
    }
}
