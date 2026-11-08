//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalServiceKit
import SignalUI

/// Empfaenger von `TalerLinks.returnScheme://taler-open` (link-protokoll.md
/// 12): Taler oeffnet damit aus seiner Transaktionsliste die Signal-Nachricht
/// zu einer Zahlung - Reaktionen und Antworten danach sind sofort sichtbar,
/// eine Erinnerung ist eine normale Antwort im Chat.
///
/// Der Link enthaelt nur Hashes der Zahlungs-URIs. Signal sucht die URI
/// unter den eigenen Vorgaengen, springt zur aeltesten Nachricht mit dieser
/// URI im Chat des Vorgangs und fragt den Status aller URIs dieser Nachricht
/// sofort beim Exchange ab. Aus dem Link wird kein Status uebernommen
/// (link-protokoll.md 2.5): jede App kann diesen Link oeffnen. Keine URI
/// landet im Log.
enum TalerOpenHandler {

    private struct Target {
        let threadUniqueId: String
        /// nil, wenn die Nachricht geloescht oder verschwunden ist - dann
        /// oeffnet sich nur der Chat.
        let interactionUniqueId: String?
        let uris: [String]
    }

    @MainActor
    static func handle(_ url: URL) {
        let hashes = TalerOpenLink.parseHashes(url)
        guard !hashes.isEmpty else {
            Logger.warn("taler-open ohne gueltigen uriHash - ignoriert")
            return
        }
        SSKEnvironment.shared.databaseStorageRef.asyncRead(
            block: { tx in Self.target(hashes: hashes, tx: tx) },
            completion: { target in
                DispatchQueue.main.async {
                    guard let target else {
                        OWSActionSheets.showActionSheet(
                            title: TalerStrings.openPaymentNotFoundTitle,
                            message: TalerStrings.openPaymentNotFoundMessage,
                        )
                        return
                    }
                    // Sofort synchron: einmal frisch beim Exchange nachsehen,
                    // die Karte aktualisiert sich ueber die Datenbank.
                    for uri in target.uris {
                        TalerPaymentManager.shared.requestRefresh(uri: uri, trigger: .manual)
                    }
                    SignalApp.shared.presentConversationForThread(
                        threadUniqueId: target.threadUniqueId,
                        focusMessageId: target.interactionUniqueId,
                        animated: true,
                    )
                }
            },
        )
    }

    private static func target(hashes: [String], tx: DBReadTransaction) -> Target? {
        guard
            let uri = TalerOpenLink.firstMatchingUri(hashes: hashes, knownUris: TalerPaymentStore.allUris(tx: tx)),
            let record = TalerPaymentStore.record(forUri: uri, tx: tx)
        else {
            return nil
        }
        // Aelteste Nachricht mit dieser URI im Chat des Vorgangs: die
        // Zahlungsnachricht selbst, nicht eine spaetere Kopie.
        let id = InteractionRecord.columnName(.id)
        let sql = """
            SELECT i.\(id) AS interactionId, i.\(InteractionRecord.columnName(.uniqueId)) AS interactionUniqueId
            FROM \(InteractionRecord.databaseTableName) AS i
            JOIN TalerPaymentInteraction AS t ON t.interactionId = i.\(id)
            WHERE t.uri = ? AND i.\(InteractionRecord.columnName(.threadUniqueId)) = ?
            ORDER BY i.\(id) ASC
            LIMIT 1
            """
        let row = try? Row.fetchOne(tx.database, sql: sql, arguments: [uri, record.threadUniqueId])
        let interactionId: Int64? = row?["interactionId"]
        let interactionUniqueId: String? = row?["interactionUniqueId"]
        let uris = interactionId.map { TalerPaymentStore.uris(forInteractionId: $0, tx: tx) } ?? []
        return Target(
            threadUniqueId: record.threadUniqueId,
            interactionUniqueId: interactionUniqueId,
            uris: uris.isEmpty ? [uri] : uris,
        )
    }
}
