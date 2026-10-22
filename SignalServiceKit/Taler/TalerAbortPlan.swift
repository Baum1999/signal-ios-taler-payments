//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Ausloeser eines compose-abort (spec-multi-uri-link.md 3.1, `reason`). Nur
/// fuer den Dialogtext in Taler; Rohwerte sind Protokoll.
public enum TalerAbortReason: String, Equatable, Sendable {
    /// "Fuer alle loeschen" einer Nachricht mit eigenen offenen Zahlungen.
    case delete
    /// "Abbrechen" im Long-Press-Menue einer Gruppenkarte (ab zwei Anteilen).
    case menu
}

/// Flache, reine Anzeige-Metadaten des compose-abort-Links
/// (spec-multi-uri-link.md 3.1/3.2). Taler entscheidet nie auf ihrer
/// Grundlage; es zeigt nur verifizierte Werte und warnt bei Abweichung.
/// Keine Geheimnisse, keine Kontakt- oder Nachrichtendaten ausser dem
/// Anzeigenamen des Chats.
public struct TalerAbortMeta: Equatable, Sendable {
    public var reason: TalerAbortReason?
    public var isGroup: Bool?
    public var recipientHint: String?
    public var memberCount: Int?
    public var isGroupSplit: Bool?
    public var includeSelf: Bool?
    /// Urspruengliche Zahl der Anteile der Nachricht.
    public var splitCount: Int?
    public var currency: String?
    /// Format wie `TalerPaymentPayload.totalAmount` (Dezimalstring ohne
    /// Waehrung).
    public var totalAmount: String?
    public var summary: String?
    /// Sendezeitpunkt der Nachricht, Millisekunden seit 1970.
    public var sentAt: UInt64?

    public static let maxRecipientHintLength = 80
    public static let maxSummaryLength = 200

    public init(reason: TalerAbortReason? = nil,
                isGroup: Bool? = nil,
                recipientHint: String? = nil,
                memberCount: Int? = nil,
                isGroupSplit: Bool? = nil,
                includeSelf: Bool? = nil,
                splitCount: Int? = nil,
                currency: String? = nil,
                totalAmount: String? = nil,
                summary: String? = nil,
                sentAt: UInt64? = nil) {
        self.reason = reason
        self.isGroup = isGroup
        self.recipientHint = recipientHint
        self.memberCount = memberCount
        self.isGroupSplit = isGroupSplit
        self.includeSelf = includeSelf
        self.splitCount = splitCount
        self.currency = currency
        self.totalAmount = totalAmount
        self.summary = summary
        self.sentAt = sentAt
    }
}

/// Rest eines compose-abort mit mehr als `TalerAbortPlan.maxUrisPerLink`
/// URIs: die noch offenen Stapel, dieselben Metadaten und ob ein
/// gescheitertes Oeffnen lokal abbricht ("Fuer alle loeschen") oder nichts tut
/// (Menue).
public struct TalerAbortContinuation: Equatable {
    public let remainingBatches: [[String]]
    public let meta: TalerAbortMeta?
    public let fallsBackLocally: Bool

    public init(remainingBatches: [[String]], meta: TalerAbortMeta?, fallsBackLocally: Bool) {
        self.remainingBatches = remainingBatches
        self.meta = meta
        self.fallsBackLocally = fallsBackLocally
    }
}

/// Was Signal mit einem Abbruch-Ergebnis tut.
public enum TalerAbortFollowUp: Equatable {
    /// `aborted`: Taler behauptet einen Abbruch. Erst der Exchange belegt
    /// ihn (`TalerPaymentManager.verifyAbort`), vorher aendert sich nichts.
    case verifyAbort
    /// Status direkt setzen (`expired` -> ABGELAUFEN).
    case setStatus(TalerPaymentStatus)
    /// Nichts erzwingen, nur den echten Zustand abfragen.
    case refresh
}

/// Reine Entscheidungslogik des echten Abbruchs (S10, Gap A, Zielbild 6.2,
/// Multi-URI-Link 5.2; Spiegel der Logik aus dem Android-Plan
/// 2026-09-28-taler-payment-delete-abort.md). Kein DB-Zugriff, kein UIKit:
/// Der Aufrufer liest die Records in seiner Transaktion und schreibt die
/// Ergebnisse selbst. URIs sind Inhaberpapiere und werden nie geloggt.
public enum TalerAbortPlan {

    /// Hoechstens so viele URIs traegt ein compose-abort-Link
    /// (spec-multi-uri-link.md 3.1). Mehr werden in Stapel geteilt, die
    /// nacheinander starten (der naechste erst nach dem Ruecksprung).
    public static let maxUrisPerLink = 32

    /// URIs, fuer die das Abbruch-Gate gilt (eigene, noch offene pay-push,
    /// `TalerCardActionGate.showCancel`) - nur diese darf Signal Taler zum
    /// Abbrechen vorlegen. Eintraege ohne Record (URI nicht verifiziert),
    /// fremde, bereits entschiedene oder nicht-pay-push-Zahlungen fallen
    /// heraus; Dubletten werden einmalig uebernommen, die Reihenfolge bleibt
    /// erhalten.
    public static func affectedUris(records: [TalerPaymentRecord?]) -> [String] {
        var seen = Set<String>()
        var uris: [String] = []
        for record in records {
            guard let record, TalerCardActionGate.showCancel(record), seen.insert(record.uri).inserted else {
                continue
            }
            uris.append(record.uri)
        }
        return uris
    }

    /// Teilt `uris` in Stapel zu hoechstens `maxUrisPerLink`, Reihenfolge
    /// erhalten. Leere Eingabe -> keine Stapel.
    public static func batches(_ uris: [String]) -> [[String]] {
        stride(from: 0, to: uris.count, by: maxUrisPerLink).map {
            Array(uris[$0..<min($0 + maxUrisPerLink, uris.count)])
        }
    }

    /// Bildet die Ergebnisse des Ruecksprungs auf Folgeaktionen ab
    /// (link-protokoll.md 9, spec-multi-uri-link.md 3.3 und Frage 6):
    /// `aborted` -> erst verifizieren, `expired` -> ABGELAUFEN, alles andere
    /// (`already_claimed`, `declined`, `not_own`, `failed`) -> nur Refresh.
    /// Ergebnisse mit einer URI, die nicht in `allowed` steht, werden
    /// komplett ignoriert (Ziel-Validierung). Die Reihenfolge des
    /// Ruecksprungs bleibt erhalten. Verglichen wird entpackt
    /// (`TalerHttpsLink.unwrap`): Taler bekommt und meldet `taler://`, der
    /// Record kann den DD-103-https-Link tragen; zurueck kommt immer die URI
    /// aus `allowed`.
    public static func apply(results: [TalerAbortResult], allowed: [String]) -> [(uri: String, followUp: TalerAbortFollowUp)] {
        var allowedByKey: [String: String] = [:]
        for uri in allowed where allowedByKey[TalerHttpsLink.unwrap(uri)] == nil {
            allowedByKey[TalerHttpsLink.unwrap(uri)] = uri
        }
        var updates: [(uri: String, followUp: TalerAbortFollowUp)] = []
        for result in results {
            guard let original = allowedByKey[TalerHttpsLink.unwrap(result.uri)] else {
                continue
            }
            switch result.outcome {
            case .aborted:
                updates.append((original, .verifyAbort))
            case .expired:
                updates.append((original, .setStatus(.abgelaufen)))
            case .alreadyClaimed, .declined, .notOwn, .failed:
                updates.append((original, .refresh))
            }
        }
        return updates
    }

    /// Exchange-Antwort nach einem von Taler gemeldeten `aborted`: Ist der
    /// Purse weg (Contract/Status 404/410, beim Resolver `ABGELAUFEN`), ist
    /// der Abbruch belegt -> UNGUELTIG wie bisher. Jede andere Antwort
    /// (weiter offen, angenommen, offline) gilt unveraendert - die Behauptung
    /// aus dem Link allein aendert nichts.
    public static func verifiedAbortResolution(_ resolution: TalerContractResolution) -> TalerContractResolution {
        if case .failed(.abgelaufen) = resolution {
            return .failed(.ungueltig)
        }
        return resolution
    }
}
