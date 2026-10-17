//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Gemeinsame Erkennung und Nachverfolgung fuer Taler-URIs in Nachrichten -
/// von Empfangs-, Sync-Transcript- und Sendepfad genutzt, damit alle Seiten
/// eines Chats (und verknuepfte Geraete) denselben Vorgang lokal fuehren.
/// Spiegel von `TalerPaymentTracker.kt` (signal-android).
///
/// Nachverfolgt (Vorgang, Karte, Polling) werden nur `pay-push`/`pay-pull`:
/// nur fuer diese kann Signal den Zustand selbst beim Exchange ermitteln.
public enum TalerPaymentTracker {

    public static func isTrackable(_ uri: String) -> Bool {
        let kind = TalerUriParser.classify(uri)
        return kind == .payPush || kind == .payPull
    }

    /// Muss in derselben Schreibtransaktion wie das Einfuegen der Nachricht
    /// aufgerufen werden (die Nachricht braucht eine `sqliteRowId`).
    ///
    /// - Parameters:
    ///   - structured: `DataMessage.talerPayment` (Feld 9000), falls vorhanden;
    ///     sonst wird `body` ausgewertet (aeltere/fremde Clients).
    ///   - isOwnPayment: eigener Sendepfad oder Sync-Transcript = `true`,
    ///     Empfangspfad = `false`. Wird beim Anlegen gesetzt und von
    ///     spaeteren Abrufen nie ueberschrieben.
    public static func track(
        message: TSMessage,
        body: String?,
        structured: TalerPaymentPayload?,
        isOwnPayment: Bool,
        tx: DBWriteTransaction,
    ) {
        guard let interactionId = message.sqliteRowId else {
            return
        }
        let uris: [String]
        if let structured, !structured.uris.isEmpty {
            uris = structured.uris
            TalerPaymentStore.insertPaymentMessage(interactionId: interactionId, payload: structured, tx: tx)
        } else if let body, !body.isEmpty {
            uris = TalerMessageBody.uris(in: body)
        } else {
            uris = []
        }
        guard !uris.isEmpty else {
            return
        }
        TalerPaymentStore.link(interactionId: interactionId, uris: uris, tx: tx)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var newUris: [String] = []
        for uri in uris where isTrackable(uri) {
            if TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: message.uniqueThreadId, isOwnPayment: isOwnPayment, now: now, tx: tx) {
                newUris.append(uri)
            }
        }
        if !newUris.isEmpty {
            tx.addSyncCompletion {
                TalerPaymentManager.shared.didDetectNewUris(newUris)
            }
        }
    }

    public static func structuredPayload(from proto: SSKProtoDataMessageTalerPayment?) -> TalerPaymentPayload? {
        guard let proto, !proto.uris.isEmpty else {
            return nil
        }
        return TalerPaymentPayload(
            uris: proto.uris,
            version: proto.hasVersion ? Int(proto.version) : 1,
            isGroupSplit: proto.hasIsGroupSplit ? proto.isGroupSplit : false,
            includeSelf: proto.hasIncludeSelf ? proto.includeSelf : nil,
            totalAmount: proto.totalAmount,
        )
    }

    public static func buildProto(from payload: TalerPaymentPayload) -> SSKProtoDataMessageTalerPayment? {
        let builder = SSKProtoDataMessageTalerPayment.builder()
        builder.setUris(payload.uris)
        builder.setVersion(UInt32(payload.version))
        builder.setIsGroupSplit(payload.isGroupSplit)
        if let includeSelf = payload.includeSelf {
            builder.setIncludeSelf(includeSelf)
        }
        if let totalAmount = payload.totalAmount {
            builder.setTotalAmount(totalAmount)
        }
        return builder.buildInfallibly()
    }
}

/// Uebergabe der strukturierten Payload einer gerade entstehenden
/// ausgehenden Nachricht an den Sendepfad (`UnpreparedOutgoingMessage`), wo
/// sie in derselben Transaktion wie das Einfuegen der Nachricht persistiert
/// wird. Ersetzt Androids `MessageExtras.talerPayment`.
public final class TalerPendingOutgoingPayloads {
    public static let shared = TalerPendingOutgoingPayloads()

    private let lock = NSLock()
    private var payloads: [String: TalerPaymentPayload] = [:]

    public func register(_ payload: TalerPaymentPayload, forMessageUniqueId uniqueId: String) {
        lock.lock()
        defer { lock.unlock() }
        payloads[uniqueId] = payload
    }

    public func take(forMessageUniqueId uniqueId: String) -> TalerPaymentPayload? {
        lock.lock()
        defer { lock.unlock() }
        return payloads.removeValue(forKey: uniqueId)
    }
}
