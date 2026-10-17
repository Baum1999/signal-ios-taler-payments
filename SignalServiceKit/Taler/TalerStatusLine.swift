//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// userInfo-Key, unter dem `TalerStatusLine.insert` den Rohwert des
/// `TalerPaymentStatus` in der Info-Message ablegt. NSString ist bei der
/// Archivierung von `infoMessageUserInfo` zugelassen; ein Swift-Extension-Key
/// genuegt, ObjC bleibt unangetastet (Entscheidung E7, Variante A).
extension InfoMessageUserInfoKey {
    static let talerPaymentStatus = InfoMessageUserInfoKey(rawValue: "InfoMessageUserInfoKeyTalerPaymentStatus")
}

/// Lokale Statuszeile im Chat (Entscheidung E7, Variante A): eine
/// `TSInfoMessage` vom Typ `.talerPaymentUpdate` mit dem Status im userInfo.
/// Spiegel von `insertLocalStatusLine` (signal-android).
///
/// Es wird nichts gesendet (kein MessageSenderJobQueue, kein Sync) - die
/// Zeile ist rein lokal und gehoert auch nicht ins Backup. Der Status wird
/// im Klartext-Rohwert gespeichert, nicht der lokalisierte Text; so folgt
/// die Anzeige einer Spaeteren Sprachumstellung.
public enum TalerStatusLine {

    /// Fuegt die Statuszeile in den Thread ein. Nur ANGENOMMEN, ABGELAUFEN,
    /// LOKAL_ABGELEHNT, LOKAL_ABGEBROCHEN; sonst no-op. Ist der Thread weg,
    /// passiert nichts.
    public static func insert(status: TalerPaymentStatus, threadUniqueId: String, tx: DBWriteTransaction) {
        guard Self.hasStatusLine(status) else {
            return
        }
        guard let thread = TSThread.fetchViaCache(uniqueId: threadUniqueId, transaction: tx) else {
            return
        }
        // Verschwinde-Frist des Threads uebernehmen (Vorbild
        // PinnedMessageManager): Version nur mitgeben, wenn eine Dauer
        // gesetzt ist, sonst startet der Timer nicht.
        let config = DependenciesBridge.shared.disappearingMessagesConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: tx)
        let infoMessage = TSInfoMessage(
            thread: thread,
            messageType: .talerPaymentUpdate,
            expireTimerVersion: config.durationSeconds > 0 ? config.timerVersion : nil,
            expiresInSeconds: config.durationSeconds,
            infoMessageUserInfo: [.talerPaymentStatus: status.rawValue]
        )
        infoMessage.anyInsert(transaction: tx)
        // Rein informativ: keine ungelesene Statuszeile, kein Unread-Badge.
        infoMessage.markAsRead(
            atTimestamp: NSDate.ows_millisecondTimeStamp(),
            thread: thread,
            circumstance: .onThisDevice,
            shouldClearNotifications: false,
            transaction: tx
        )
    }

    /// Anzeigetext je Status (lokalisiert, erst zur Anzeigezeit aufgeloest).
    /// `nil` fuer Status ohne Zeile.
    public static func text(for status: TalerPaymentStatus) -> String? {
        switch status {
        case .angenommen: return TalerStrings.statusLineAccepted
        case .abgelaufen: return TalerStrings.statusLineExpired
        case .lokalAbgelehnt: return TalerStrings.statusLineDeclined
        case .lokalAbgebrochen: return TalerStrings.statusLineCancelled
        case .offen, .unbekanntOffline, .ungueltig: return nil
        }
    }

    /// Anzeigetext einer gespeicherten Statuszeile (liest den userInfo-Key).
    static func text(for message: TSInfoMessage) -> String {
        guard
            let raw: String = message.infoMessageValue(forKey: .talerPaymentStatus),
            let status = TalerPaymentStatus(rawValue: raw),
            let text = text(for: status)
        else {
            owsFailDebug("Statuszeile ohne gueltigen Status")
            return ""
        }
        return text
    }

    private static func hasStatusLine(_ status: TalerPaymentStatus) -> Bool {
        text(for: status) != nil
    }
}
