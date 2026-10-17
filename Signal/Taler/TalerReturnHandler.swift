//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit
import SignalUI

/// Empfaenger des Ruecksprungs `TalerLinks.returnUri` (Paket S4).
/// Der Eingriff in UrlOpener.swift beschraenkt sich auf die Erkennung von
/// Scheme/Host; ALLE Entscheidungen trifft dieser Handler anhand des Intents
/// aus dem Correlation-Store (link-protokoll.md 8, Regel 4).
///
/// Eiserne Regeln dabei: Signal bestaetigt hier keine Zahlung (Taler hat
/// laengst committet - das Senden der Nachricht ist nur die Mitteilung), der
/// `status` wird nie angezeigt, und keine URI landet in einem Log. Ist die
/// correlationId unbekannt, abgelaufen oder schon benutzt, wird der
/// Ruecksprung still verworfen.
enum TalerReturnHandler {

    /// Behandelt einen Ruecksprung. Liefert true, wenn die URL als
    /// Taler-Ruecksprung konsumiert wurde (auch wenn nichts weiter passiert).
    @MainActor
    static func handle(_ url: URL) -> Bool {
        // UrlOpener hat Scheme/Host bereits geprueft; parse kann nur an einer
        // fehlenden correlationId scheitern. Auch dann: still konsumieren,
        // keine sichtbare Reaktion ("immer beenden, nie sichtbar abstuerzen").
        guard let ret = TalerReturn.parse(url) else {
            return true
        }

        // single-use: take entfernt den Eintrag immer; bei unbekannter,
        // abgelaufener oder replayter ID gibt es nichts. Kein Log mit der
        // correlationId oder einer URI - nur eine neutrale Warnzeile.
        guard let entry = TalerCorrelationStore.shared.take(ret.correlationId) else {
            Logger.warn("Taler-Ruecksprung mit unbekannter oder abgelaufener correlationId - ignoriert")
            return true
        }

        switch entry.intent {
        case .send:
            sendPaymentMessage(ret, threadUniqueId: entry.threadUniqueId)

        case .acceptOrCancel:
            // status egal (Taler ruft ihn auch als reinen Trigger auf): nur
            // Fast-Poll der URI aus dem Store-Eintrag - der echte Zustand
            // kommt aus Contract/Exchange, nie aus dem Link.
            if let uri = entry.uri {
                TalerPaymentManager.shared.requestFastPoll(uri: uri)
            }

        case .refund:
            // REFUND (S9): Taler hat die Rueckerstattung laengst committet -
            // Signal legt KEINE Nachricht automatisch an (link-protokoll.md 4:
            // kein automatisches Senden). Stattdessen wird ein ENTWURF als
            // Zitat-Antwort auf die Originalnachricht gespeichert (Header
            // "Refund: " vor dem Verwendungszweck) und der Chat geoeffnet; ob
            // gesendet wird, entscheidet der Nutzer.
            prepareRefundDraft(
                ret,
                threadUniqueId: entry.threadUniqueId,
                quoteInteractionUniqueId: entry.quoteInteractionUniqueId
            )

        case .abort:
            // ABORT (S10, Gap A, link-protokoll.md 9): Ergebnisse pro URI
            // uebernehmen, aber nur fuer URIs aus dem Store-Eintrag
            // (Ziel-Validierung).
            applyAbortResults(ret.results, entry: entry)
        }
        return true
    }

    // MARK: - ABORT

    /// Uebernimmt die Abbruch-Ergebnisse der result-Variante (S10, Gap A):
    /// `aborted` -> UNGUELTIG, `expired` -> ABGELAUFEN,
    /// `already_claimed`/`declined` erzwingen nichts, loesen aber einen
    /// manuellen Refresh aus (der echte Zustand kommt aus Contract/Exchange,
    /// nie aus dem Link). URIs ohne Ergebnis bleiben unveraendert. Statuszeilen
    /// nur nach E7-Regeln, falls TalerStatusLine fuer den Status eine Zeile
    /// vorsieht (UNGUELTIG hat keine, ABGELAUFEN eine), sonst keine. Kein
    /// Loggen einer URI.
    private static func applyAbortResults(_ results: [TalerAbortResult], entry: TalerCorrelationEntry) {
        let updates = TalerAbortPlan.apply(results: results, allowed: entry.uris)

        // already_claimed/declined: nichts erzwingen, nur Refresh.
        for update in updates where update.status == nil {
            TalerPaymentManager.shared.requestRefresh(uri: update.uri, trigger: .manual)
        }

        let statusUpdates = updates.filter { $0.status != nil }
        guard !statusUpdates.isEmpty else {
            return
        }
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            for (uri, status) in statusUpdates {
                guard
                    let status,
                    let record = TalerPaymentStore.record(forUri: uri, tx: tx),
                    TalerPaymentStore.updateStatus(uri: uri, status: status, now: now, tx: tx)
                else {
                    continue
                }
                if record.status != status {
                    // Statuszeile nach E7, falls der Status eine vorsieht.
                    TalerStatusLine.insert(status: status, threadUniqueId: record.threadUniqueId, tx: tx)
                    // Nachrichten mit derselben URI (zitierte/weitergeleitete
                    // Kopien) neu rendern; die geloeschte Nachricht ist weg.
                    TalerPaymentManager.touchInteractions(forUri: uri, tx: tx)
                }
            }
        }
    }

    // MARK: - SEND

    /// Verschickt die Zahlungsnachricht (Klartext-Body plus Proto-Feld 9000)
    /// in den Thread des Store-Eintrags - ueber denselben Sendeweg, den Signal
    /// auch fuer normale Textnachrichten nutzt (SerialTaskQueue, body-Validie-
    /// rung, UnpreparedOutgoingMessage.prepare, MessageSenderJobQueue), siehe
    /// ThreadUtil (SignalServiceKit) und ThreadUtil+SignalUI. Verschwindende
    /// Nachrichten des Threads gelten dadurch automatisch. Wird nichts
    /// gesendet (cancelled, ungueltige URI, Thread weg), passiert nichts.
    private static func sendPaymentMessage(_ ret: TalerReturn, threadUniqueId: String) {
        guard let content = TalerSendPayload.build(from: ret) else {
            // cancelled, fehlende URI oder eine URI bestand die Pruefung nicht:
            // nichts senden, keine sichtbare Aenderung im Chat.
            return
        }

        ThreadUtil.enqueueSendQueue.enqueue {
            let databaseStorage = SSKEnvironment.shared.databaseStorageRef

            // Defense-in-depth wie Android (TalerReturnActivity.kt): nur
            // 1:1-Chats und Gruppen, keine "Notiz an mich".
            let thread = databaseStorage.read { tx in
                DependenciesBridge.shared.threadStore.fetchThread(uniqueId: threadUniqueId, tx: tx)
            }
            guard let thread,
                  thread is TSContactThread || thread is TSGroupThread,
                  !thread.isNoteToSelf else {
                return
            }

            // Body-Validierung wie beim normalen Text-Senden (Oversize-Text
            // faellt bei Taler-URIs real nicht an, der Pfad bleibt aber
            // identisch). ValidatedMessageBody ist schon inline-faehig.
            guard let validatedBody = try? await DependenciesBridge.shared.attachmentContentValidator
                .prepareOversizeTextIfNeeded(MessageBody(text: content.body, ranges: .empty)) else {
                return
            }

            let message = databaseStorage.read { tx in
                let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread, messageBody: validatedBody)
                // Verschwinde-Timer des Threads wie bei jeder Textnachricht.
                let dmConfig = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                    .fetchOrBuildDefault(for: .thread(thread), tx: tx)
                builder.expiresInSeconds = dmConfig.durationSeconds
                builder.expireTimerVersion = NSNumber(value: dmConfig.timerVersion)
                return builder.build(transaction: tx)
            }

            // Feld-9000-Payload vormerken, BEVOR die Nachricht vorbereitet
            // wird: UnpreparedOutgoingMessage nimmt sie beim Einfuegen ab und
            // persistiert sie in derselben Transaktion (TalerPaymentTracker.
            // track, isOwnPayment true). Sie wird nicht in den Body kodiert.
            TalerPendingOutgoingPayloads.shared.register(content.payload, forMessageUniqueId: message.uniqueId)
            let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(message, body: validatedBody)

            await databaseStorage.awaitableWrite { tx in
                guard let preparedMessage = try? unpreparedMessage.prepare(tx: tx) else {
                    return
                }
                SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
                if
                    let messageForIntent = preparedMessage.messageForIntentDonation(tx: tx),
                    let thread = messageForIntent.thread(tx: tx)
                {
                    thread.donateSendMessageIntent(for: messageForIntent, transaction: tx)
                }
            }
        }
    }

    // MARK: - REFUND

    /// Speichert die Rueckerstattung als ENTWURF (Body mit Header vor dem
    /// Verwendungszweck) und oeffnet den Chat - wie Android
    /// (TalerReturnActivity.kt, REFUND-Zweig: Draft-Table statt Senden) und
    /// link-protokoll.md Abschnitt 4. Es wird nichts automatisch verschickt;
    /// der Zitat-Bezug zeigt auf die Originalnachricht. Ist die
    /// Originalnachricht inzwischen weg, wird der Entwurf ohne Zitat
    /// gespeichert; ist der Thread weg, wird verworfen. Beim spaeteren Senden
    /// durch den Nutzer erfasst der vorhandene Hook in
    /// UnpreparedOutgoingMessage.prepare (TalerPaymentTracker.track mit
    /// structured: nil, Body-Parsing) die URI als eigene Zahlung dieses
    /// Geraets - derselbe Weg wie bei jeder manuell getippten Taler-Nachricht.
    private static func prepareRefundDraft(_ ret: TalerReturn, threadUniqueId: String, quoteInteractionUniqueId: String?) {
        guard let body = TalerRefundPayload.build(from: ret) else {
            // cancelled, fehlende URI oder eine URI bestand die Pruefung nicht:
            // keinen Entwurf anlegen, keine sichtbare Aenderung.
            return
        }

        // Draft speichern und danach den Chat oeffnen. Die Completion laeuft
        // auf der Main-Queue; der Chat liest den Entwurf beim Laden frisch
        // aus der DB (bzw. per reloadDraft, falls er schon offen ist).
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
            // Defense-in-depth wie beim Senden (TalerReturnActivity.kt): nur
            // 1:1-Chats und Gruppen, keine "Notiz an mir". Thread weg ->
            // Entwurf verwerfen.
            guard
                let thread = DependenciesBridge.shared.threadStore.fetchThread(uniqueId: threadUniqueId, tx: tx),
                thread is TSContactThread || thread is TSGroupThread,
                !thread.isNoteToSelf
            else {
                return false
            }

            // Zitat-Bezug wie beim Speichern des Reply-Entwurfs beim Verlassen
            // der Konversation (ConversationViewController+
            // ConversationInputToolbarDelegate): Zeitstempel plus Autor-ACI
            // der Originalnachricht, Aufloesung beim Laden ueber
            // ConversationViewController+UI.buildDraftQuotedReply.
            // Originalnachricht oder Autor nicht mehr bestimmbar ->
            // Entwurf ohne Zitat.
            var replyInfo: ThreadReplyInfo?
            if
                let quoteInteractionUniqueId,
                let originalMessage = TSMessage.fetchMessageViaCache(uniqueId: quoteInteractionUniqueId, transaction: tx)
            {
                let authorAci: Aci?
                if let incoming = originalMessage as? TSIncomingMessage {
                    authorAci = incoming.authorAddress.aci
                } else if originalMessage is TSOutgoingMessage {
                    authorAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aci
                } else {
                    authorAci = nil
                }
                if let authorAci {
                    replyInfo = ThreadReplyInfo(timestamp: originalMessage.timestamp, author: authorAci)
                }
            }

            // updateWithDraft schreibt Text- und Zitat-Entwurf des Threads in
            // einer Transaktion - derselbe Weg wie beim Verlassen der
            // Konversation. Ein eventuell vorhandener Edit-Entwurf wird
            // bewusst verworfen (Android ersetzt die Drafts ebenfalls
            // komplett, DraftTable.replaceDrafts).
            thread.updateWithDraft(
                draftMessageBody: MessageBody(text: body, ranges: .empty),
                replyInfo: replyInfo,
                editTargetTimestamp: nil,
                transaction: tx
            )
            return true
        } completion: { didPersistDraft in
            if didPersistDraft {
                SignalApp.shared.presentConversationForThread(
                    threadUniqueId: threadUniqueId,
                    action: .updateDraft,
                    animated: true
                )
            }
        }
    }
}
