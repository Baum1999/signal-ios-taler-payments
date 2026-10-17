//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Long-Press-Aktionen fuer Taler-Nachrichten. Spiegel von `TalerMenuActions`
/// (signal-android): jede Aktion liest den Zustand beim Klick frisch neu,
/// statt sich auf den beim Menue-Aufbau berechneten Snapshot zu verlassen.
/// Die Block-Closures halten nur die uniqueId, nie ein Zwischenergebnis.
enum TalerMessageActions {

    // MARK: - Menueaufbau

    /// Haengt an `MessageActions.textActions` an: ersetzt fuer Taler-
    /// Nachrichten das normale Kopieren und Weiterleiten durch die vier
    /// Eintraege aus Zielbild 4.9 (Als Bild weiterleiten, Als Text
    /// weiterleiten, Als Bild kopieren, Als Transkript kopieren) und ergaenzt
    /// die bedingten Aktionen Ablehnen/Abbrechen/Aktualisieren/Rueckerstatten.
    /// Das Long-Press-Menue betrifft immer genau EINE Nachricht; ohne
    /// Taler-URI im Body gibt es `actions` unveraendert zurueck.
    static func adjust(
        _ actions: [MessageAction],
        itemViewModel: CVItemViewModelImpl,
        delegate: MessageActionsDelegate
    ) -> [MessageAction] {
        guard
            let message = itemViewModel.interaction as? TSMessage,
            TalerMenuGate.hasTalerUris(body: message.body)
        else {
            return actions
        }
        let targets = SSKEnvironment.shared.databaseStorageRef.read { tx in
            TalerMenuState.targets(for: message, tx: tx)
        }
        // Die Closures halten nur die uniqueId, nie das Model oder ein
        // Zwischenergebnis; jede Aktion liest den Zustand beim Klick frisch.
        let messageUniqueId = message.uniqueId
        // Das normale Weiterleiten wird fuer Taler-Nachrichten durch
        // "Als Text weiterleiten" ersetzt (mit Inhaberpapier-Warnung), dazu
        // kommt "Als Bild weiterleiten" ohne URI (Zielbild 4.9).
        let canForward = actions.contains { $0.actionType == .forward }
        // Das normale Kopieren wird fuer Taler-Nachrichten durch "Als Bild
        // kopieren" plus das Transkript ersetzt (Android
        // onCopyAsImageFromMenu/onCopyAsTextFromMenu).
        var adjusted = actions.filter { $0.actionType != .copy && $0.actionType != .forward }
        if canForward {
            adjusted.append(
                MessageAction(
                    .talerForwardImage,
                    accessibilityLabel: TalerStrings.menuForwardAsImage,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "taler_forward_image"),
                    contextMenuTitle: TalerStrings.menuForwardAsImage,
                    contextMenuAttributes: [],
                    block: { [weak delegate] _ in
                        TalerMessageActions.forwardAsImage(messageUniqueId: messageUniqueId, delegate: delegate)
                    }
                )
            )
            adjusted.append(
                MessageAction(
                    .talerForwardText,
                    accessibilityLabel: TalerStrings.menuForwardAsText,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "taler_forward_text"),
                    contextMenuTitle: TalerStrings.menuForwardAsText,
                    contextMenuAttributes: [],
                    block: { [weak delegate] _ in
                        TalerMessageActions.forwardAsText(itemViewModel: itemViewModel, messageUniqueId: messageUniqueId, delegate: delegate)
                    }
                )
            )
        }
        if itemViewModel.canCopyOrShareOrSpeakText {
            adjusted.append(
                MessageAction(
                    .talerCopyImage,
                    accessibilityLabel: TalerStrings.menuCopyAsImage,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "taler_copy_image"),
                    contextMenuTitle: TalerStrings.menuCopyAsImage,
                    contextMenuAttributes: [],
                    block: { _ in
                        TalerMessageActions.copyAsImage(messageUniqueId: messageUniqueId)
                    }
                )
            )
            adjusted.append(
                MessageAction(
                    .talerCopyTranscript,
                    accessibilityLabel: TalerStrings.menuCopyTranscript,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "taler_copy_transcript"),
                    contextMenuTitle: TalerStrings.menuCopyTranscript,
                    contextMenuAttributes: [],
                    block: { _ in
                        TalerMessageActions.copyTranscript(messageUniqueId: messageUniqueId)
                    }
                )
            )
        }
        if targets.showReject {
            adjusted.append(
                MessageAction(
                    .talerReject,
                    accessibilityLabel: TalerStrings.menuReject,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "taler_reject"),
                    contextMenuTitle: TalerStrings.menuReject,
                    contextMenuAttributes: [.destructive],
                    block: { _ in
                        TalerMessageActions.reject(messageUniqueId: messageUniqueId)
                    }
                )
            )
        }
        if targets.showCancel {
            adjusted.append(
                MessageAction(
                    .talerCancel,
                    accessibilityLabel: TalerStrings.menuCancel,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "taler_cancel"),
                    contextMenuTitle: TalerStrings.menuCancel,
                    contextMenuAttributes: [],
                    block: { _ in
                        TalerMessageActions.cancel(messageUniqueId: messageUniqueId)
                    }
                )
            )
        }
        if targets.showRefresh {
            adjusted.append(
                MessageAction(
                    .talerRefresh,
                    accessibilityLabel: TalerStrings.menuRefresh,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "taler_refresh"),
                    contextMenuTitle: TalerStrings.menuRefresh,
                    contextMenuAttributes: [],
                    block: { _ in
                        TalerMessageActions.refresh(messageUniqueId: messageUniqueId)
                    }
                )
            )
        }
        if targets.showRefund {
            adjusted.append(
                MessageAction(
                    .talerRefund,
                    accessibilityLabel: TalerStrings.menuRefund,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "message_action", name: "taler_refund"),
                    contextMenuTitle: TalerStrings.menuRefund,
                    contextMenuAttributes: [],
                    block: { _ in
                        TalerMessageActions.refund(messageUniqueId: messageUniqueId)
                    }
                )
            )
        }
        return adjusted
    }

    // MARK: - Aktionen

    /// Ablehnen: rein lokal nicht mehr verfolgen. Der Absender wird nicht
    /// benachrichtigt, es fliesst kein Geld zurueck (Regel 1).
    static func reject(messageUniqueId: String) {
        let rejectUri = SSKEnvironment.shared.databaseStorageRef.read { tx -> String? in
            guard let message = TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx) else {
                return nil
            }
            return TalerMenuState.targets(for: message, tx: tx).rejectUri
        }
        guard let rejectUri else {
            return
        }
        OWSActionSheets.showConfirmationAlert(
            title: TalerStrings.rejectDialogTitle,
            message: TalerStrings.rejectDialogMessage,
            proceedTitle: TalerStrings.rejectDialogConfirm,
            proceedStyle: .destructive,
        ) { _ in
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
                // Ziel frisch lesen - der Dialog war offen, der Vorgang kann
                // sich inzwischen geaendert haben; nur noch anwenden, wenn er
                // wirklich noch OFFEN ist (sonst stiller Abbruch).
                guard
                    let record = TalerPaymentStore.record(forUri: rejectUri, tx: tx),
                    record.status == .offen
                else {
                    return
                }
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                guard TalerPaymentStore.updateStatus(uri: rejectUri, status: .lokalAbgelehnt, now: now, tx: tx) else {
                    return
                }
                TalerStatusLine.insert(status: .lokalAbgelehnt, threadUniqueId: record.threadUniqueId, tx: tx)
                TalerPaymentManager.touchInteractions(forUri: rejectUri, tx: tx)
            }
        }
    }

    /// Abbrechen: oeffnet Talers eigene Abbrechen-UI fuer den eigenen,
    /// offenen Anteil. Signal bewegt dabei kein Geld - bestaetigt wird nur
    /// in der Taler-UI durch den Nutzer (Regel 1). Der Status aendert sich
    /// erst durch Taler bzw. den Exchange, nie lokal.
    static func cancel(messageUniqueId: String) {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            guard let message = TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx) else {
                return
            }
            let targets = TalerMenuState.targets(for: message, tx: tx)
            for uri in targets.cancelUris {
                TalerCardActions.cancel(uri: uri, threadUniqueId: message.uniqueThreadId)
            }
        }
    }

    /// Aktualisieren: sofortiger manueller Abruf je Anteil. Bewusst kein
    /// `requestFastPoll` - der 2-s-Takt ist fuer den Ruecksprung aus Taler.
    static func refresh(messageUniqueId: String) {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            guard let message = TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx) else {
                return
            }
            let targets = TalerMenuState.targets(for: message, tx: tx)
            for uri in targets.cancelUris {
                TalerPaymentManager.shared.requestRefresh(uri: uri, trigger: .manual)
            }
        }
    }

    /// Als Transkript kopieren: den Body unverändert in die eigene
    /// Zwischenablage (Android `Util.copyToClipboard(context, body)`).
    static func copyTranscript(messageUniqueId: String) {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            UIPasteboard.general.string = TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx)?.body
        }
    }

    /// Als Bild kopieren: Karte offscreen als PNG (ohne URI, ohne Knoepfe)
    /// in die Zwischenablage (Android `TalerMenuActions.onCopyAsImageFromMenu`).
    static func copyAsImage(messageUniqueId: String) {
        TalerCardSnapshot.copyToPasteboard(messageUniqueId: messageUniqueId)
    }

    /// Als Text weiterleiten: die rohe(n) URI(s) im normalen
    /// Weiterleiten-Fluss (Android `TalerForwardGate.forwardAsText`). Ist
    /// mindestens ein Anteil OFFEN, vorher Bestaetigung - dann wird ein
    /// Inhaberpapier weitergegeben (wer den Link zuerst oeffnet, kann genau
    /// DIESEN Anteil einloesen). Der Zustand wird beim Klick frisch gelesen;
    /// die URI selbst erscheint in keiner Meldung.
    static func forwardAsText(itemViewModel: CVItemViewModelImpl, messageUniqueId: String, delegate: MessageActionsDelegate?) {
        let needsWarning = SSKEnvironment.shared.databaseStorageRef.read { tx -> Bool in
            guard
                let message = TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx),
                let body = message.body
            else {
                return false
            }
            let statuses = TalerMessageBody.uris(in: body).map { uri in
                TalerPaymentStore.record(forUri: uri, tx: tx)?.status
            }
            return TalerForwardGate.needsOpenShareWarning(statuses: statuses)
        }
        if needsWarning {
            OWSActionSheets.showConfirmationAlert(
                message: TalerStrings.forwardWarningMessage,
                proceedTitle: TalerStrings.menuForwardAsText
            ) { _ in
                delegate?.messageActionsForwardItem(itemViewModel)
            }
        } else {
            delegate?.messageActionsForwardItem(itemViewModel)
        }
    }

    /// Als Bild weiterleiten: Karte offscreen als PNG (ohne URI) und als
    /// Bild-Anhang ueber den normalen Weiterleiten-Dialog verschicken
    /// (Android `TalerForwardGate.attachPaymentSnapshot`). Signal bewegt
    /// dabei kein Geld (Regel 1); die Karte zeigt nur verifizierte Daten.
    static func forwardAsImage(messageUniqueId: String, delegate: MessageActionsDelegate?) {
        guard
            let fromViewController = delegate as? UIViewController,
            let forwardDelegate = delegate as? ForwardMessageDelegate,
            let attachment = TalerCardSnapshot.pngAttachment(messageUniqueId: messageUniqueId)
        else {
            return
        }
        ForwardMessageViewController.present(
            forTalerCardImage: attachment,
            from: fromViewController,
            delegate: forwardDelegate
        )
    }

    /// Rueckerstatten (S9): oeffnet Talers eigene Rueckerstattungs-UI
    /// (compose-refund) fuer einen von diesem Geraet angenommenen Anteil.
    /// Signal bewegt kein Geld - die Rueckerstattung legt der Nutzer in der
    /// Taler-UI fest (Regel 1). Der Zustand wird beim Klick frisch gelesen;
    /// ohne passenden Anteil passiert nichts. Pro refundUri ein eigener
    /// Aufruf wie Android (TalerMenuActions.onRefundFromMenu iteriert alle
    /// Anteile); bei mehreren bleibt es wie beim Abbrechen beim jeweils
    /// zuletzt geoeffneten Link. Die URIs werden nur innerhalb des DB-Reads
    /// ermittelt; UIApplication.open laeuft erst NACH dem Read.
    static func refund(messageUniqueId: String) {
        // Beim Tippen frisch pruefen (zentraler Cache, siehe TalerInstallation).
        guard TalerInstallation.refresh() else {
            OWSActionSheets.showActionSheet(
                title: TalerStrings.alertTalerNotInstalledTitle,
                message: TalerStrings.alertTalerNotInstalledBody
            )
            return
        }
        let launches: [(originalUri: String, threadUniqueId: String, quoteInteractionUniqueId: String)] =
            SSKEnvironment.shared.databaseStorageRef.read { tx in
                guard let message = TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx) else {
                    return []
                }
                let targets = TalerMenuState.targets(for: message, tx: tx)
                return targets.refundUris.map { uri in
                    (originalUri: uri, threadUniqueId: message.uniqueThreadId, quoteInteractionUniqueId: message.uniqueId)
                }
            }
        for launch in launches {
            TalerMessageActions.launchRefund(
                originalUri: launch.originalUri,
                threadUniqueId: launch.threadUniqueId,
                quoteInteractionUniqueId: launch.quoteInteractionUniqueId
            )
        }
    }

    /// Registriert den REFUND-Eintrag (Original-URI plus Interaktions-ID der
    /// Originalnachricht, damit die Rueckerstattung als Zitat-Antwort
    /// vorbereitet werden kann) und oeffnet compose-refund. Schlaegt das
    /// Oeffnen fehl, laeuft der Store-Eintrag nach der TTL ungenutzt ab; es
    /// wird nichts gesendet. Die URIs sind Inhaberpapiere und erscheinen in
    /// keiner Logmeldung.
    private static func launchRefund(originalUri: String, threadUniqueId: String, quoteInteractionUniqueId: String) {
        let correlationId = TalerCorrelationStore.shared.register(
            TalerCorrelationEntry(
                intent: .refund,
                threadUniqueId: threadUniqueId,
                uri: originalUri,
                uris: [],
                quoteInteractionUniqueId: quoteInteractionUniqueId
            )
        )
        let url = TalerLinks.composeRefund(originalUri: originalUri, correlationId: correlationId)
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                DispatchQueue.main.async {
                    OWSActionSheets.showActionSheet(
                        title: TalerStrings.alertTalerNotInstalledTitle,
                        message: TalerStrings.alertTalerNotInstalledBody
                    )
                }
            }
        }
    }
}
