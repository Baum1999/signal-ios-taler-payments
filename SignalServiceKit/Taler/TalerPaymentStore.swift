//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Eine Zeile aus `TalerPayment` - ein Vorgang pro Taler-URI, nicht pro
/// Nachricht (doppelt zugestellte, zitierte, weitergeleitete Nachrichten mit
/// derselben URI sind derselbe Vorgang). Spiegel von `TalerPaymentRecord`
/// (signal-android).
public struct TalerPaymentRecord: Equatable, Sendable {
    public var uri: String
    public var threadUniqueId: String
    public var uriKind: TalerUriKind?
    public var status: TalerPaymentStatus
    public var amount: String?
    public var currency: String?
    public var exchangeBaseUrl: String?
    public var summary: String?
    /// Millisekunden seit 1970.
    public var createdAt: Int64
    public var lastCheckedAt: Int64?
    /// Millisekunden seit 1970 des letzten tatsaechlichen Statuswechsels
    /// (nil, solange der Status nie gewechselt wurde).
    public var statusChangedAt: Int64?
    public var consecutiveFailures: Int
    public var isOwnPayment: Bool

    public init(
        uri: String,
        threadUniqueId: String,
        uriKind: TalerUriKind?,
        status: TalerPaymentStatus,
        amount: String? = nil,
        currency: String? = nil,
        exchangeBaseUrl: String? = nil,
        summary: String? = nil,
        createdAt: Int64,
        lastCheckedAt: Int64? = nil,
        statusChangedAt: Int64? = nil,
        consecutiveFailures: Int = 0,
        isOwnPayment: Bool,
    ) {
        self.uri = uri
        self.threadUniqueId = threadUniqueId
        self.uriKind = uriKind
        self.status = status
        self.amount = amount
        self.currency = currency
        self.exchangeBaseUrl = exchangeBaseUrl
        self.summary = summary
        self.createdAt = createdAt
        self.lastCheckedAt = lastCheckedAt
        self.statusChangedAt = statusChangedAt
        self.consecutiveFailures = consecutiveFailures
        self.isOwnPayment = isOwnPayment
    }
}

public struct TalerPaymentPollCandidate: Equatable, Sendable {
    public var uri: String
    public var lastCheckedAt: Int64?
    public var consecutiveFailures: Int
}

/// Strukturierte Zahlungsdaten einer Nachricht (`DataMessage.talerPayment`,
/// Feld 9000). Spiegel von `TalerPaymentMessageRecord` (signal-android).
public struct TalerPaymentMessageRecord: Equatable, Sendable {
    public var interactionId: Int64
    public var payload: TalerPaymentPayload
}

/// Ergebnis von `applyPreviewAndRecordTransition`.
public struct TalerPaymentTransition: Equatable, Sendable {
    /// Status vor dem Schreiben.
    public var previous: TalerPaymentStatus
    /// Neuer Status (unveraendert, wenn ein lokaler Endzustand geschuetzt wurde).
    public var current: TalerPaymentStatus
    /// Erst-Erreichen von ANGENOMMEN/ABGELAUFEN - Anlass fuer eine lokale Statuszeile.
    public var reachedTerminalStatus: Bool
}

/// Datenzugriff auf die Taler-Tabellen (Migration `addTalerPaymentTables`).
/// Spiegel von `TalerPaymentTable`/`TalerPaymentMessageTable`/
/// `TalerConfirmationMessageTable` (signal-android), plus
/// `TalerPaymentInteraction` als URI->Nachricht-Zuordnung (iOS braucht sie,
/// um nach einem Statuswechsel genau die betroffenen Zellen neu zu rendern).
public enum TalerPaymentStore {

    static let statusLineTerminalStatuses: Set<TalerPaymentStatus> = [.angenommen, .abgelaufen]

    // MARK: - Schema

    static func createTables(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS TalerPayment (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uri TEXT NOT NULL UNIQUE,
                threadUniqueId TEXT NOT NULL,
                uriKind TEXT,
                status TEXT NOT NULL,
                amount TEXT,
                currency TEXT,
                exchangeBaseUrl TEXT,
                summary TEXT,
                createdAt INTEGER NOT NULL,
                lastCheckedAt INTEGER,
                consecutiveFailures INTEGER NOT NULL DEFAULT 0,
                isOwnPayment INTEGER NOT NULL DEFAULT 0
            )
            """)
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS TalerPayment_threadUniqueId ON TalerPayment (threadUniqueId)")
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS TalerPaymentMessage (
                interactionId INTEGER PRIMARY KEY NOT NULL
                    REFERENCES model_TSInteraction (id) ON DELETE CASCADE ON UPDATE CASCADE,
                uris TEXT NOT NULL,
                version INTEGER NOT NULL,
                isGroupSplit INTEGER NOT NULL DEFAULT 0,
                includeSelf INTEGER,
                totalAmount TEXT
            )
            """)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS TalerPaymentInteraction (
                interactionId INTEGER NOT NULL
                    REFERENCES model_TSInteraction (id) ON DELETE CASCADE ON UPDATE CASCADE,
                uri TEXT NOT NULL,
                PRIMARY KEY (interactionId, uri)
            )
            """)
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS TalerPaymentInteraction_uri ON TalerPaymentInteraction (uri)")
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS TalerConfirmationMessage (
                interactionId INTEGER PRIMARY KEY NOT NULL
                    REFERENCES model_TSInteraction (id) ON DELETE CASCADE ON UPDATE CASCADE,
                uri TEXT NOT NULL,
                matchedAt INTEGER NOT NULL
            )
            """)
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS TalerConfirmationMessage_uri ON TalerConfirmationMessage (uri)")
    }

    // MARK: - TalerPayment

    /// Legt einen neuen Vorgang an, falls `uri` noch nicht bekannt ist.
    /// `true`, wenn tatsaechlich neu angelegt (Aufrufer soll dann abrufen).
    /// `isOwnPayment` kommt vom Aufrufer, weil nur der die Richtung kennt.
    @discardableResult
    public static func upsertDetected(uri: String, threadUniqueId: String, isOwnPayment: Bool, now: Int64, tx: DBWriteTransaction) -> Bool {
        failIfThrows {
            try tx.database.execute(
                sql: """
                    INSERT OR IGNORE INTO TalerPayment (uri, threadUniqueId, status, isOwnPayment, createdAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [uri, threadUniqueId, TalerPaymentStatus.unbekanntOffline.rawValue, isOwnPayment ? 1 : 0, now],
            )
            return tx.database.changesCount > 0
        }
    }

    /// Schreibt eine Exchange-Vorschau und entscheidet in derselben
    /// Transaktion, ob ein Endzustand erstmals erreicht wurde (Android-Fix
    /// `97500b14e5`: kein doppeltes "abgelaufen" bei parallelen Abrufen).
    /// `nil`, wenn es den Vorgang nicht gibt. Ein lokaler Endzustand
    /// (abgelehnt/abgebrochen) wird nie ueberschrieben.
    public static func applyPreviewAndRecordTransition(uri: String, preview: TalerPaymentPreview, now: Int64, tx: DBWriteTransaction) -> TalerPaymentTransition? {
        guard let existing = record(forUri: uri, tx: tx) else {
            return nil
        }
        if existing.status.isLocalTerminal {
            return TalerPaymentTransition(previous: existing.status, current: existing.status, reachedTerminalStatus: false)
        }
        let status = TalerPaymentStatus(preview.status)
        // Nur ein echter Statuswechsel zaehlt; bei gleichem Status bleibt
        // der bisherige Zeitstempel stehen.
        let statusChangedAt = status != existing.status ? now : existing.statusChangedAt
        failIfThrows {
            try tx.database.execute(
                sql: """
                    UPDATE TalerPayment SET uriKind = ?, status = ?, amount = ?, currency = ?, exchangeBaseUrl = ?,
                        summary = ?, lastCheckedAt = ?, statusChangedAt = ?, consecutiveFailures = 0
                    WHERE uri = ?
                    """,
                arguments: [preview.uriKind.rawValue, status.rawValue, preview.amount, preview.currency, preview.exchangeBaseUrl, preview.summary, now, statusChangedAt, uri],
            )
        }
        return TalerPaymentTransition(
            previous: existing.status,
            current: status,
            reachedTerminalStatus: statusLineTerminalStatuses.contains(status) && existing.status != status,
        )
    }

    /// Setzt einen Status. Ein bestehender lokaler Endzustand wird nur durch
    /// denselben Zustand "ueberschrieben" (Android `updateStatus`). `true`,
    /// wenn geschrieben wurde.
    @discardableResult
    public static func updateStatus(uri: String, status: TalerPaymentStatus, now: Int64, tx: DBWriteTransaction) -> Bool {
        guard let existing = record(forUri: uri, tx: tx) else {
            return false
        }
        if status != existing.status, existing.status.isLocalTerminal {
            return false
        }
        // Nur ein echter Statuswechsel zaehlt; bei gleichem Status bleibt
        // der bisherige Zeitstempel stehen.
        let statusChangedAt = status != existing.status ? now : existing.statusChangedAt
        failIfThrows {
            try tx.database.execute(
                sql: "UPDATE TalerPayment SET status = ?, lastCheckedAt = ?, statusChangedAt = ?, consecutiveFailures = 0 WHERE uri = ?",
                arguments: [status.rawValue, now, statusChangedAt, uri],
            )
        }
        return true
    }

    /// Transportfehler - nur Backoff-Zaehler, kein Statuswechsel.
    public static func recordFailure(uri: String, now: Int64, tx: DBWriteTransaction) {
        failIfThrows {
            try tx.database.execute(
                sql: "UPDATE TalerPayment SET lastCheckedAt = ?, consecutiveFailures = consecutiveFailures + 1 WHERE uri = ?",
                arguments: [now, uri],
            )
        }
    }

    public static func record(forUri uri: String, tx: DBReadTransaction) -> TalerPaymentRecord? {
        failIfThrows {
            try Row.fetchOne(tx.database, sql: "SELECT * FROM TalerPayment WHERE uri = ?", arguments: [uri]).map(readRecord)
        }
    }

    public static func records(forThreadUniqueId threadUniqueId: String, tx: DBReadTransaction) -> [TalerPaymentRecord] {
        failIfThrows {
            try Row.fetchAll(
                tx.database,
                sql: "SELECT * FROM TalerPayment WHERE threadUniqueId = ? ORDER BY createdAt ASC",
                arguments: [threadUniqueId],
            ).map(readRecord)
        }
    }

    public static func allRecords(tx: DBReadTransaction) -> [TalerPaymentRecord] {
        failIfThrows {
            try Row.fetchAll(tx.database, sql: "SELECT * FROM TalerPayment ORDER BY createdAt ASC").map(readRecord)
        }
    }

    /// Polling-Kandidaten: OFFEN immer (echter, vom Exchange bestaetigter
    /// Wartezustand), UNBEKANNT_OFFLINE nur innerhalb der TTL. Am laengsten
    /// nicht geprueft zuerst, damit bei mehr Vorgaengen als `limit` alle
    /// reihum drankommen. Der Backoff wird vom Aufrufer angewandt.
    public static func pollCandidates(limit: Int, ttlCutoff: Int64, tx: DBReadTransaction) -> [TalerPaymentPollCandidate] {
        failIfThrows {
            try Row.fetchAll(
                tx.database,
                sql: """
                    SELECT uri, lastCheckedAt, consecutiveFailures FROM TalerPayment
                    WHERE status = ?
                       OR (status = ? AND COALESCE(lastCheckedAt, createdAt) >= ?)
                    ORDER BY COALESCE(lastCheckedAt, 0) ASC
                    LIMIT ?
                    """,
                arguments: [TalerPaymentStatus.offen.rawValue, TalerPaymentStatus.unbekanntOffline.rawValue, ttlCutoff, limit],
            ).map { row in
                TalerPaymentPollCandidate(uri: row["uri"], lastCheckedAt: row["lastCheckedAt"], consecutiveFailures: row["consecutiveFailures"])
            }
        }
    }

    private static func readRecord(_ row: Row) -> TalerPaymentRecord {
        let kind: String? = row["uriKind"]
        let status: String = row["status"]
        return TalerPaymentRecord(
            uri: row["uri"],
            threadUniqueId: row["threadUniqueId"],
            uriKind: kind.flatMap(TalerUriKind.init(rawValue:)),
            status: TalerPaymentStatus(rawValue: status) ?? .unbekanntOffline,
            amount: row["amount"],
            currency: row["currency"],
            exchangeBaseUrl: row["exchangeBaseUrl"],
            summary: row["summary"],
            createdAt: row["createdAt"],
            lastCheckedAt: row["lastCheckedAt"],
            statusChangedAt: row["statusChangedAt"],
            consecutiveFailures: row["consecutiveFailures"],
            isOwnPayment: (row["isOwnPayment"] as Int64) != 0,
        )
    }

    /// "Zuletzt abgeschlossen" statt "zuletzt erkannt" (Zielbild 3.2/6.1):
    /// Zeitstempel des letzten Statuswechsels, rueckfallend auf die
    /// Erst-Erkennung.
    public static func latestActivityAt(_ record: TalerPaymentRecord) -> Int64 {
        record.statusChangedAt ?? record.createdAt
    }

    // MARK: - TalerPaymentInteraction

    public static func link(interactionId: Int64, uris: [String], tx: DBWriteTransaction) {
        failIfThrows {
            for uri in uris {
                try tx.database.execute(
                    sql: "INSERT OR IGNORE INTO TalerPaymentInteraction (interactionId, uri) VALUES (?, ?)",
                    arguments: [interactionId, uri],
                )
            }
        }
    }

    public static func interactionIds(forUri uri: String, tx: DBReadTransaction) -> [Int64] {
        failIfThrows {
            try Int64.fetchAll(tx.database, sql: "SELECT interactionId FROM TalerPaymentInteraction WHERE uri = ?", arguments: [uri])
        }
    }

    // MARK: - TalerPaymentMessage

    private static let uriSeparator = "\n"

    public static func insertPaymentMessage(interactionId: Int64, payload: TalerPaymentPayload, tx: DBWriteTransaction) {
        failIfThrows {
            try tx.database.execute(
                sql: """
                    INSERT OR IGNORE INTO TalerPaymentMessage (interactionId, uris, version, isGroupSplit, includeSelf, totalAmount)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    interactionId,
                    payload.uris.joined(separator: uriSeparator),
                    payload.version,
                    payload.isGroupSplit ? 1 : 0,
                    payload.includeSelf.map { $0 ? 1 : 0 },
                    payload.totalAmount,
                ],
            )
        }
    }

    public static func paymentMessage(interactionId: Int64, tx: DBReadTransaction) -> TalerPaymentMessageRecord? {
        failIfThrows {
            try Row.fetchOne(tx.database, sql: "SELECT * FROM TalerPaymentMessage WHERE interactionId = ?", arguments: [interactionId]).map { row in
                let uris: String = row["uris"]
                let includeSelf: Int64? = row["includeSelf"]
                return TalerPaymentMessageRecord(
                    interactionId: row["interactionId"],
                    payload: TalerPaymentPayload(
                        uris: uris.components(separatedBy: uriSeparator),
                        version: row["version"],
                        isGroupSplit: (row["isGroupSplit"] as Int64) != 0,
                        includeSelf: includeSelf.map { $0 != 0 },
                        totalAmount: row["totalAmount"],
                    ),
                )
            }
        }
    }

    // MARK: - TalerConfirmationMessage

    public static func insertConfirmation(interactionId: Int64, uri: String, now: Int64, tx: DBWriteTransaction) {
        failIfThrows {
            try tx.database.execute(
                sql: "INSERT OR IGNORE INTO TalerConfirmationMessage (interactionId, uri, matchedAt) VALUES (?, ?, ?)",
                arguments: [interactionId, uri, now],
            )
        }
    }

    public static func confirmationUri(interactionId: Int64, tx: DBReadTransaction) -> String? {
        failIfThrows {
            try String.fetchOne(tx.database, sql: "SELECT uri FROM TalerConfirmationMessage WHERE interactionId = ?", arguments: [interactionId])
        }
    }

    public static func confirmationInteractionIds(forUri uri: String, tx: DBReadTransaction) -> [Int64] {
        failIfThrows {
            try Int64.fetchAll(tx.database, sql: "SELECT interactionId FROM TalerConfirmationMessage WHERE uri = ?", arguments: [uri])
        }
    }
}
