//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Welche Taler-Aktionen des Long-Press-Menues fuer eine Nachricht gerade
/// zutreffen, inklusive der konkreten URI(s), auf die sie sich beziehen.
/// Spiegel von `TalerMenuTargets` (signal-android).
public struct TalerMenuTargets: Equatable, Sendable {
    /// Einzel-URI: die URI, die "Ablehnen" betrifft. Gruppe: der eigene
    /// Anteil im Umlauf.
    public var rejectUri: String?
    /// Eigene, noch offene Anteile (Abbrechen/Aktualisieren, nur Ersteller).
    public var cancelUris: [String]
    /// Von diesem Geraet beanspruchte, inzwischen angenommene Anteile
    /// (Rueckerstatten, S9 - hier wird nur gerechnet).
    public var refundUris: [String]

    public var showReject: Bool { rejectUri != nil }
    public var showCancel: Bool { !cancelUris.isEmpty }
    public var showRefresh: Bool { !cancelUris.isEmpty }
    public var showRefund: Bool { !refundUris.isEmpty }

    public static let none = TalerMenuTargets(rejectUri: nil, cancelUris: [], refundUris: [])

    public init(rejectUri: String?, cancelUris: [String], refundUris: [String]) {
        self.rejectUri = rejectUri
        self.cancelUris = cancelUris
        self.refundUris = refundUris
    }
}

/// Minimaler Taler-Erkennungs-Check fuer Upstream-Menue-Logik, die sonst
/// nichts von Taler weiss. Spiegel von `TalerMenuGate` (signal-android).
public enum TalerMenuGate {
    public static func hasTalerUris(body: String?) -> Bool {
        guard let body, !body.isEmpty else {
            return false
        }
        return !TalerMessageBody.uris(in: body).isEmpty
    }
}

/// Entscheidungslogik des Long-Press-Menues. Spiegel von `TalerMenuState.kt`
/// (signal-android): Einzel-URI ueber `TalerCardActionGate` (dieselbe
/// Wahrheitstabelle wie die Karte), Gruppe rollenbewusst ueber
/// `TalerGroupSplit`.
///
/// `compute` liest den DB-/Claim-Zustand jedes Mal frisch - sowohl beim
/// Aufbau des Menues als auch (erneut) im Klick-Handler, damit ein
/// zwischenzeitlich veraenderter Zustand nicht auf einem veralteten
/// Snapshot ausgefuehrt wird.
public enum TalerMenuState {

    /// Reine Logik. `role == nil` bedeutet Einzel-URI-Pfad.
    public static func compute(
        uris: [String],
        records: [TalerPaymentRecord?],
        role: TalerGroupCardRole?,
        claimedUris: Set<String>,
        anyClaimed: Bool
    ) -> TalerMenuTargets {
        guard !uris.isEmpty else {
            return .none
        }
        guard let role else {
            // Einzel-URI-Pfad: dieselben Bedingungen wie auf der Karte.
            let uri = uris[0]
            let record = records.first ?? nil
            return TalerMenuTargets(
                rejectUri: TalerCardActionGate.showReject(record) ? uri : nil,
                cancelUris: TalerCardActionGate.showCancel(record) ? [uri] : [],
                refundUris: TalerCardActionGate.showRefund(record) ? [uri] : []
            )
        }
        // Gruppe: Ablehnen nur fuer Empfaenger ohne eigenen Claim, gebunden
        // an den naechsten offenen Anteil ab dem eigenen Index (mit Umlauf).
        let statuses = records.map { $0?.status }
        let rejectUri: String?
        if case .recipient(let myIndex) = role, !anyClaimed {
            rejectUri = TalerGroupSplit.resolveTargetUri(uris: uris, statuses: statuses, startIndex: myIndex)
        } else {
            rejectUri = nil
        }
        return TalerMenuTargets(
            rejectUri: rejectUri,
            cancelUris: TalerGroupSplit.resolveCancelableUris(uris: uris, records: records, role: role),
            refundUris: TalerGroupSplit.resolveRefundableUris(uris: uris, records: records, claimedUris: claimedUris)
        )
    }

    /// Duenner Wrapper: liest Record- und Claim-Zustand frisch. Die Rolle
    /// wird lokal aus der Gruppenmitgliedschaft abgeleitet (dieselbe
    /// Aufloesung wie auf der Sammelkarte).
    public static func targets(for message: TSMessage, tx: DBReadTransaction) -> TalerMenuTargets {
        guard let body = message.body else {
            return .none
        }
        let uris = TalerMessageBody.uris(in: body)
        guard !uris.isEmpty else {
            return .none
        }
        let records = uris.map { TalerPaymentStore.record(forUri: $0, tx: tx) }
        if uris.count == 1 {
            return compute(uris: uris, records: records, role: nil, claimedUris: [], anyClaimed: false)
        }
        let thread = TSThread.fetchViaCache(uniqueId: message.uniqueThreadId, transaction: tx)
        let role = TalerGroupSplit.resolveRole(message: message, thread: thread, transaction: tx)
        let claimedUris = TalerGroupClaimTracker.shared.claimedOf(uris)
        return compute(uris: uris, records: records, role: role, claimedUris: claimedUris, anyClaimed: !claimedUris.isEmpty)
    }
}
