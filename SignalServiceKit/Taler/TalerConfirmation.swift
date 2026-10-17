//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Treffer einer erkannten Bestaetigungsnachricht.
public struct TalerConfirmationMatch: Equatable, Sendable {
    public let uri: String
    public let kind: TalerUriKind

    init(uri: String, kind: TalerUriKind) {
        self.uri = uri
        self.kind = kind
    }
}

/// Baut und erkennt die 1:1-Bestaetigungsnachricht
/// ("Payment for %@ accepted (%@)", englisch fest, nicht lokalisiert).
/// Spiegel von `TalerConfirmationDetector.kt` und dem Wortlaut aus
/// `TalerUriRefreshJob.maybeSendAcceptConfirmation` (signal-android).
///
/// Erkennung per exaktem Volltext-Match gegen das Bestaetigungsformat mit
/// jedem Peer-Art-Label und der im Text eingebetteten Taler-URI. Nur die
/// beiden Peer-Arten: zu pay/withdraw/refund fuehrt Signal keinen Vorgang,
/// ein Treffer koennte also nie gegen einen Datensatz abgeglichen werden.
/// Ein Treffer ist kein Vertrauensbeweis (der Text koennte auch manuell
/// getippt sein) - der Aufrufer verwirft ihn, wenn sich zur URI keine
/// passende eigene Zahlung in der DB findet.
public enum TalerConfirmationDetector {

    private static let matchableKinds: [(kind: TalerUriKind, label: String)] = [
        (.payPush, TalerStrings.wireKindPayPush),
        (.payPull, TalerStrings.wireKindPayPull),
    ]

    /// Wortlaut einer Bestaetigung fuer Art und URI - dasselbe Format, das
    /// die Gegenseite per `TalerConfirmationDetector.match` wiedererkennt.
    public static func body(kind: TalerUriKind, uri: String) -> String? {
        guard let label = wireLabel(for: kind) else {
            return nil
        }
        return String(format: TalerStrings.acceptConfirmationFormat, label, uri)
    }

    /// Nicht lokalisiertes Art-Label fuer den Nachrichtentext (Protokoll).
    private static func wireLabel(for kind: TalerUriKind) -> String? {
        switch kind {
        case .payPush:
            return TalerStrings.wireKindPayPush
        case .payPull:
            return TalerStrings.wireKindPayPull
        case .pay, .withdraw, .refund:
            return nil
        }
    }

    /// Liefert den Treffer, wenn `text` exakt einer Bestaetigungsnachricht
    /// entspricht (genau eine URI im Text, Volltext-Match mit einem der
    /// Peer-Art-Labels).
    public static func match(_ text: String) -> TalerConfirmationMatch? {
        let uris = TalerUriDetector.findUris(text)
        guard uris.count == 1 else {
            return nil
        }
        let uri = uris[0]
        for entry in matchableKinds
        where text == String(format: TalerStrings.acceptConfirmationFormat, entry.label, uri) {
            return TalerConfirmationMatch(uri: uri, kind: entry.kind)
        }
        return nil
    }
}

/// Speichert erkannte Bestaetigungsnachrichten des Empfangspfads.
/// Spiegel von `TalerConfirmationTracker.kt` (signal-android).
///
/// Die im Text mitgeschickte URI ist Uebergangsloesung, solange das
/// Chat-Protokoll kein eigenes Referenzfeld erlaubt - sie dient hier
/// ausschliesslich als DB-Schluessel, um die eigene Zahlung wiederzufinden,
/// nicht als vertrauenswuerdige Quelle. Ein Treffer wird deshalb nur
/// uebernommen, wenn zur URI bereits eine bekannte eigene Zahlung
/// (`isOwnPayment`) passenden Kinds im selben Chat existiert - sonst bleibt
/// die Nachricht ganz normaler Text.
public enum TalerConfirmationTracker {

    /// Muss in derselben Schreibtransaktion wie das Einfuegen der Nachricht
    /// aufgerufen werden (die Nachricht braucht eine `sqliteRowId`).
    /// Gruppen werden ausgeschlossen (spiegelbildlich zur Sendebedingung in
    /// TalerConfirmationSender); `triggerRefresh` ist nur ein Test-Hook.
    public static func track(
        body: String?,
        threadUniqueId: String,
        isGroupThread: Bool,
        interactionId: Int64,
        tx: DBWriteTransaction,
        triggerRefresh: @escaping (String) -> Void = { uri in
            TalerPaymentManager.shared.requestRefresh(uri: uri, trigger: .manual)
        }
    ) {
        guard !isGroupThread, let body, !body.isEmpty, let match = TalerConfirmationDetector.match(body) else {
            return
        }
        guard let record = TalerPaymentStore.record(forUri: match.uri, tx: tx) else {
            return
        }
        guard
            record.threadUniqueId == threadUniqueId,
            record.uriKind == match.kind,
            record.isOwnPayment
        else {
            return
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        TalerPaymentStore.insertConfirmation(interactionId: interactionId, uri: match.uri, now: now, tx: tx)
        // Sofortiger Abruf, damit die eigene Karte den neuen Zustand zeigt
        // (die URI selbst landet in keinem Log).
        tx.addSyncCompletion {
            triggerRefresh(match.uri)
        }
    }
}
