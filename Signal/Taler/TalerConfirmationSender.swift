//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Sendet die 1:1-Bestaetigungsnachricht ("Payment for ... accepted (...)",
/// englisch fest), wenn eine EINGEHENDE pay-push-Zahlung dieses Geraets
/// ANGENOMMEN wurde. Implementiert `TalerPaymentManagerDelegate`; Spiegel von
/// `TalerUriRefreshJob.maybeSendAcceptConfirmation` (signal-android).
///
/// Eiserne Regeln: Signal bestaetigt hier keine Zahlung (Taler hat laengst
/// committet - das Senden ist nur die Mitteilung an die Gegenseite), und die
/// URI landet ausschliesslich im Nachrichtentext (den die Gegenseite per
/// exaktem Vergleich wiedererkennt), in keinem Log.
final class TalerConfirmationSender: TalerPaymentManagerDelegate {

    static let shared = TalerConfirmationSender()

    private init() {}

    // MARK: - TalerPaymentManagerDelegate

    func talerPayment(
        _ record: TalerPaymentRecord,
        didTransition transition: TalerPaymentTransition,
        tx: DBWriteTransaction,
    ) {
        guard transition.previous == .offen, transition.current == .angenommen else {
            return
        }
        // Nur EIGENE Annahme eines pay-push: dieselbe Bedingung wie fuer den
        // Annehmen-Knopf. Self-Chat braucht keinen zusaetzlichen Ausschluss
        // (dann ist isOwnPayment ohnehin true, siehe Android Bug 2 Fix).
        guard record.uriKind == .payPush, !record.isOwnPayment else {
            return
        }
        // Nur 1:1-Chats - in Gruppen wird keine Bestaetigung gesendet.
        let thread = DependenciesBridge.shared.threadStore.fetchThread(uniqueId: record.threadUniqueId, tx: tx)
        guard thread is TSContactThread else {
            return
        }
        ThreadUtil.enqueueSendQueue.enqueue { [uri = record.uri, threadUniqueId = record.threadUniqueId] in
            await Self.sendConfirmation(uri: uri, threadUniqueId: threadUniqueId)
        }
    }

    // MARK: - Senden

    /// Verschickt die Bestaetigung ueber denselben Text-Sendepfad wie
    /// TalerReturnHandler (SerialTaskQueue, Body-Validierung,
    /// UnpreparedOutgoingMessage.prepare, MessageSenderJobQueue). Wird nichts
    /// gesendet (bereits bestaetigt, Thread weg), passiert nichts.
    private static func sendConfirmation(uri: String, threadUniqueId: String) async {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

        let thread = databaseStorage.read { tx in
            DependenciesBridge.shared.threadStore.fetchThread(uniqueId: threadUniqueId, tx: tx)
        }
        guard let thread, thread is TSContactThread else {
            return
        }

        guard
            let body = TalerConfirmationDetector.body(kind: .payPush, uri: uri),
            let validatedBody = try? await DependenciesBridge.shared.attachmentContentValidator
                .prepareOversizeTextIfNeeded(MessageBody(text: body, ranges: .empty))
        else {
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

        let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(message, body: validatedBody)

        await databaseStorage.awaitableWrite { tx in
            // Dedupe, pro URI hoechstens eine Bestaetigung (auch ueber
            // App-Neustarts): vor dem Senden auf eine bereits gesendete
            // (ausgehende) Bestaetigung pruefen - atomar in derselben
            // Schreibtransaktion wie das Einfuegen.
            let confirmedIds = TalerPaymentStore.confirmationInteractionIds(forUri: uri, tx: tx)
            let confirmed = TalerPaymentManager.interactions(rowIds: confirmedIds, tx: tx)
            guard !confirmed.contains(where: { $0 is TSOutgoingMessage }) else {
                return
            }

            guard let preparedMessage = try? unpreparedMessage.prepare(tx: tx) else {
                return
            }
            if let interactionId = message.sqliteRowId {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                TalerPaymentStore.insertConfirmation(interactionId: interactionId, uri: uri, now: now, tx: tx)
            }
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
        }
    }
}
