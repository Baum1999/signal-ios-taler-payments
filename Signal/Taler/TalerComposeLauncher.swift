//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Startet den compose-send-Flow (Paket S4): der Taler-Knopf im
/// Anhang-Menue oeffnet `talerlink://compose-send` in GNU Taler. Signal fragt
/// dabei weder Betrag noch Zweck ab (Regel: Signal kennt keine Taler-Betraege)
/// und gibt nur unbedenkliche Kontextinfo mit (link-protokoll.md 3). Die
/// Richtung (Senden/Anfordern) waehlt der Nutzer in Talers eigenem Screen;
/// `direction` ist nur die Anfangsstellung des Toggles.
///
/// Vor dem Oeffnen wird der SEND-Eintrag im Correlation-Store registriert;
/// nach dem Ruecksprung verschickt TalerReturnHandler die Nachricht. Kein
/// Einschraenken auf das Primaergeraet - verknuepfte Geraete duerfen senden.
enum TalerComposeLauncher {

    @MainActor
    static func startSend(thread: TSThread, from vc: UIViewController) {
        // Notiz an mich: wie das Android-Gate (AttachmentKeyboardFragment /
        // Backstop in TalerReturnActivity.kt) wird "Notiz an mich" nicht
        // bedient - hier mit Hinweis statt still.
        if thread.isNoteToSelf {
            OWSActionSheets.showActionSheet(
                title: TalerStrings.noteToSelfUnsupportedTitle,
                message: TalerStrings.noteToSelfUnsupportedMessage,
                fromViewController: vc,
            )
            return
        }

        // Nur anbieten/oeffnen, wenn Taler den Scheme ueberhaupt registriert
        // hat (LSApplicationQueriesSchemes enthaelt talerlink). Beim Tippen
        // frisch pruefen - zentraler Cache, siehe TalerInstallation.
        guard TalerInstallation.refresh() else {
            OWSActionSheets.showActionSheet(
                title: TalerStrings.talerNotInstalledTitle,
                message: TalerStrings.talerNotInstalledMessage,
                fromViewController: vc,
            )
            return
        }

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

        // Anzeigename des Chats (nur Anzeige-Hilfe in Taler, untrusted dort).
        let recipientHint = databaseStorage.read { tx in
            SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
        }

        let isGroup = thread.isGroupThread
        // Anzahl Gruppenmitglieder inkl. mir (nur Gruppe, wie Android
        // participantIds.size; TSGroupModel.groupMembers enthaelt auch mich).
        let memberCount = (thread as? TSGroupThread)?.groupModel.groupMembers.count

        // Verschwinde-Timer des Threads in Sekunden, 0 = aus.
        let disappearingMessagesSeconds = databaseStorage.read { tx in
            DependenciesBridge.shared.disappearingMessagesConfigurationStore.durationSeconds(for: thread, tx: tx)
        }

        // Kontext des Ruecksprungs vormerken; correlationId vergibt der Store.
        let correlationId = TalerCorrelationStore.shared.register(
            TalerCorrelationEntry(
                intent: .send,
                threadUniqueId: thread.uniqueId,
                uri: nil,
                uris: [],
                quoteInteractionUniqueId: nil
            )
        )

        let url = TalerLinks.composeSend(
            recipientHint: recipientHint,
            isGroup: isGroup,
            memberCount: isGroup ? memberCount : nil,
            disappearingMessagesSeconds: disappearingMessagesSeconds,
            direction: .payPush,
            correlationId: correlationId
        )

        // Schlaegt das Oeffnen fehl, bleibt der Store-Eintrag ungenutzt und
        // laeuft nach der TTL ab; es wird nichts gesendet (link-protokoll.md 3,
        // Fehlerfall "Taler nicht installiert").
        UIApplication.shared.open(url)
    }
}
