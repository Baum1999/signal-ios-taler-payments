//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Bruecke zwischen `TalerDeliveryStatus` (reine Logik, SignalServiceKit)
/// und den Status-Icons im Nachricht-Footer und in der Chatliste (Zielbild
/// 4.7). Rangfolge wie Android (`ConversationItemFooter`): fehlgeschlagene
/// Nachrichten behalten ihr Fehler-Icon, `offen` behaelt die normalen Haken,
/// nur "alle URIs angenommen" zeigt das eigenstaendige `TALER_PAID`-Icon.
enum TalerDeliveryStatusUI {

    static let paidIconName = "message_status_taler_paid"

    /// Footer: nutzt die Transaktion des CVComponentState-Aufbaus (Ladepfad,
    /// analog zur Taler-Karte aus S3), nie den Render-Pfad.
    static func footerPaidIndicator(
        for message: TSOutgoingMessage,
        transaction: DBReadTransaction
    ) -> CVComponentFooter.StatusIndicator? {
        guard !message.wasRemotelyDeleted, isPaid(message: message, transaction: transaction) else {
            return nil
        }
        return CVComponentFooter.StatusIndicator(imageName: paidIconName, isAnimated: false)
    }

    /// Chatliste: `isPaid` kommt aus `ChatListInfo.lastMessageTalerPaid`
    /// (Ladepfad), hier findet kein DB-Zugriff statt. Nur abgeschlossene
    /// Sende-Zustaende; fehlgeschlagene, pausierte und laufende Sends
    /// behalten ihr bisheriges Icon.
    static func chatListPaidImage(status: MessageReceiptStatus, isPaid: Bool) -> UIImage? {
        guard isPaid else {
            return nil
        }
        switch status {
        case .sent, .skipped, .delivered, .read, .viewed:
            return UIImage(named: paidIconName)
        case .uploading, .sending, .pending, .failed:
            return nil
        }
    }

    /// `true`, wenn der Nachrichtentext Taler-URIs enthaelt und ALLE davon
    /// angenommen sind. Die URIs werden wie auf Android nicht nach
    /// Verfolgbarkeit gefiltert: eine unbeantwortete URI verhindert das
    /// bezahlt-Icon.
    private static func isPaid(message: TSOutgoingMessage, transaction: DBReadTransaction) -> Bool {
        TalerDeliveryStatus.isPaid(message: message, tx: transaction)
    }
}
