//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Welcher Signal-Flow hinter einer correlationId steht. Rohwerte sind Teil
/// des Link-Protokolls und werden nicht umbenannt. Spiegel von
/// `TalerCorrelationIntent` (signal-android), um `ABORT` erweitert (Gap A).
public enum TalerCorrelationIntent: String, CaseIterable {
    case acceptOrCancel = "ACCEPT_OR_CANCEL"
    case send = "SEND"
    case refund = "REFUND"
    case abort = "ABORT"
}

/// Kontext, den Signal beim Oeffnen eines Links unter der correlationId
/// ablegt und beim Ruecksprung wieder entnimmt. Die URIs darin sind
/// Inhaberpapiere: Sie werden nie geloggt (Regel 4, auch nicht gekuerzt -
/// in Logs hoechstens `TalerCorrelation.shortHash(uri)`).
public struct TalerCorrelationEntry: Equatable {
    public let intent: TalerCorrelationIntent
    /// Thread, zu dem der Ruecksprung zurueckfuehren soll.
    public let threadUniqueId: String
    /// ACCEPT_OR_CANCEL, REFUND: die betroffene URI.
    public let uri: String?
    /// ABORT: alle abzubrechenden URIs in der Reihenfolge des Links, sonst [].
    public let uris: [String]
    /// REFUND: Interaktions-ID der Originalnachricht, wenn die
    /// Rueckerstattung als Zitat-Antwort vorbereitet werden soll.
    public let quoteInteractionUniqueId: String?

    public init(intent: TalerCorrelationIntent,
                threadUniqueId: String,
                uri: String? = nil,
                uris: [String] = [],
                quoteInteractionUniqueId: String? = nil) {
        self.intent = intent
        self.threadUniqueId = threadUniqueId
        self.uri = uri
        self.uris = uris
        self.quoteInteractionUniqueId = quoteInteractionUniqueId
    }
}

/// correlationId -> Eintrag, nur im Speicher (ueberlebt keinen Prozess-Neustart),
/// TTL 15 Minuten ab register, `take` ist single-use und entfernt immer -
/// auch abgelaufene Eintraege (link-protokoll.md 2.4). Thread-sicher per Lock.
/// Spiegel von `TalerCorrelationStore` (signal-android). Bekannte, geteilte
/// Grenze: Bei SEND und REFUND committet Taler vor dem Ruecksprung; geht der
/// Eintrag vorher verloren, existiert eine bezahlte Uberweisung ohne Nachricht
/// in Signal. Keine URI wird jemals geloggt.
public final class TalerCorrelationStore {

    /// Prozessweiter Singleton fuer die Flows in der App.
    /// Tests benutzen eigene Instanzen mit injizierter Uhr.
    public static let shared: TalerCorrelationStore = TalerCorrelationStore()

    private let ttl: TimeInterval
    private let now: () -> Date
    private let lock = NSLock()
    private var entries: [String: StoredEntry] = [:]

    private struct StoredEntry {
        let entry: TalerCorrelationEntry
        let createdAt: Date
    }

    public init(ttl: TimeInterval = 15 * 60, now: @escaping () -> Date = Date.init) {
        self.ttl = ttl
        self.now = now
    }

    /// Legt einen Eintrag an und gibt eine neue correlationId zurueck
    /// (UUID-String in Kleinbuchstaben, wie Android `UUID.randomUUID()`).
    public func register(_ entry: TalerCorrelationEntry) -> String {
        let correlationId = UUID().uuidString.lowercased()
        lock.lock()
        defer { lock.unlock() }
        entries[correlationId] = StoredEntry(entry: entry, createdAt: now())
        return correlationId
    }

    /// Single-use: entfernt den Eintrag immer und liefert ihn nur zurueck,
    /// wenn die ID bekannt und noch nicht abgelaufen ist; sonst nil. Ein
    /// zweiter Ruecksprung mit derselben ID (Replay) findet nichts mehr.
    public func take(_ correlationId: String) -> TalerCorrelationEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard let stored = entries.removeValue(forKey: correlationId) else {
            return nil
        }
        // Wie Android (TalerCorrelationStore.kt): abgelaufen ist strikt
        // groesser als TTL; genau TTL gilt noch als gueltig.
        guard now().timeIntervalSince(stored.createdAt) <= ttl else {
            return nil
        }
        return stored.entry
    }
}
