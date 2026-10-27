//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Bruecke zwischen `TalerDeliveryStatus` (reine Logik, SignalServiceKit)
/// und den Status-Icons im Nachricht-Footer, in der Chatliste und in den
/// Nachrichtendetails (Zielbild 4.7). Rangfolge wie Android
/// (`ConversationItemFooter`): fehlgeschlagene, pausierte und laufende Sends
/// behalten ihr Icon, `offen` zeigt die Kreis-Varianten von
/// gesendet/zugestellt/gelesen, "alle URIs angenommen" das eigenstaendige
/// `TALER_PAID`-Icon.
enum TalerDeliveryStatusUI {

    static let sentIconName = "message_status_taler_sent"
    static let deliveredIconName = "message_status_taler_delivered"
    static let readIconName = "message_status_taler_read"
    static let paidIconName = "message_status_taler_paid"

    /// Icon fuer einen Sende-Zustand einer Taler-Nachricht, `nil`, wenn der
    /// Aufrufer sein normales Icon behalten soll (keine Taler-Nachricht oder
    /// kein abgeschlossener Sende-Zustand).
    static func iconName(status: MessageReceiptStatus, talerStatus: TalerDeliveryStatus?) -> String? {
        guard let talerStatus else {
            return nil
        }
        switch status {
        case .uploading, .sending, .pending, .failed:
            return nil
        case .sent, .skipped, .delivered, .read, .viewed:
            break
        }
        if talerStatus == .paid {
            return paidIconName
        }
        switch status {
        case .read, .viewed:
            return readIconName
        case .delivered:
            return deliveredIconName
        default:
            return sentIconName
        }
    }

    /// Footer: nutzt die Transaktion des CVComponentState-Aufbaus (Ladepfad,
    /// analog zur Taler-Karte aus S3), nie den Render-Pfad.
    static func footerIndicator(
        for message: TSOutgoingMessage,
        status: MessageReceiptStatus,
        transaction: DBReadTransaction
    ) -> CVComponentFooter.StatusIndicator? {
        guard
            !message.wasRemotelyDeleted,
            let imageName = iconName(
                status: status,
                talerStatus: TalerDeliveryStatus.status(message: message, tx: transaction)
            )
        else {
            return nil
        }
        return CVComponentFooter.StatusIndicator(imageName: imageName, isAnimated: false)
    }

    /// Chatliste: `talerStatus` kommt aus `ChatListInfo.lastMessageTalerStatus`
    /// (Ladepfad), hier findet kein DB-Zugriff statt.
    static func chatListImage(status: MessageReceiptStatus, talerStatus: TalerDeliveryStatus?) -> UIImage? {
        iconName(status: status, talerStatus: talerStatus).flatMap { UIImage(named: $0) }
    }

    /// Nachrichtendetails: Kopf-Icon einer Empfaengergruppe. Wie Android
    /// (`RecipientHeaderViewHolder`) nur die Kreis-Varianten pro Gruppe, kein
    /// "bezahlt" - das gilt fuer die Nachricht, nicht fuer einzelne Empfaenger.
    static func detailSectionIconName(status: MessageReceiptStatus, isTalerPayment: Bool) -> String? {
        guard status != .skipped else {
            return nil
        }
        return iconName(status: status, talerStatus: isTalerPayment ? .open : nil)
    }
}
