//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Rolle des Betrachters auf einer Gruppen-Split-Sammelkarte. Spiegel von
/// `GroupCardRole` (`GroupSplitCard.kt`, signal-android).
public enum TalerGroupCardRole: Equatable, Sendable {
    case creator
    case recipient(myIndex: Int)
    case notAParticipant
}

/// Ergebnis von `TalerGroupSplit.buildCard`: fertiges Kartenmodell plus die
/// URI, die der Annehmen-Knopf oeffnet (`nil` = kein Knopf).
public struct TalerGroupCard: Equatable, Sendable {
    public var model: TalerCardModel
    public var acceptUri: String?

    public init(model: TalerCardModel, acceptUri: String?) {
        self.model = model
        self.acceptUri = acceptUri
    }
}

/// Reine Entscheidungslogik der Sammelkarte (eine Karte pro Nachricht statt
/// eine pro URI). 1:1 aus `GroupSplitCard.kt` / `GroupSplitRecipients.kt`.
public enum TalerGroupSplit {

    /// Sortierte Empfaenger-ACIs: alle aktuellen Gruppenmitglieder ausser
    /// dem Absender, lokal aus der bekannten Mitgliedschaft (kein
    /// Nachrichtenfeld). Sender und Empfaenger kommen unabhaengig auf
    /// dieselbe Liste.
    public static func recipientAcis(memberAcis: [String], senderAci: String) -> [String] {
        memberAcis.filter { $0 != senderAci }.sorted()
    }

    public static func resolveRole(recipientAcis: [String]?, senderAci: String, myAci: String) -> TalerGroupCardRole {
        if myAci == senderAci {
            return .creator
        }
        if let recipientAcis, let index = recipientAcis.firstIndex(of: myAci) {
            return .recipient(myIndex: index)
        }
        return .notAParticipant
    }

    /// Ab `startIndex` (mit Umlauf) der erste noch offene Anteil (Status nil
    /// oder OFFEN). "Mein Anteil" ist nur Startpunkt, kein festes Slot.
    public static func resolveTargetUri(uris: [String], statuses: [TalerPaymentStatus?], startIndex: Int) -> String? {
        guard !uris.isEmpty else {
            return nil
        }
        for offset in 0..<uris.count {
            let index = (startIndex + offset) % uris.count
            let status = statuses[index]
            if status == nil || status == .offen {
                return uris[index]
            }
        }
        return nil
    }

    public static func countAccepted(_ statuses: [TalerPaymentStatus?]) -> Int {
        statuses.filter { $0 == .angenommen }.count
    }

    /// Eigene, noch offene Anteile (nur fuer den Ersteller).
    public static func resolveCancelableUris(uris: [String], records: [TalerPaymentRecord?], role: TalerGroupCardRole) -> [String] {
        guard role == .creator else {
            return []
        }
        return zip(uris, records).filter { TalerCardActionGate.showCancel($0.1) }.map(\.0)
    }

    /// Von diesem Geraet beanspruchte und inzwischen angenommene Anteile.
    public static func resolveRefundableUris(uris: [String], records: [TalerPaymentRecord?], claimedUris: Set<String>) -> [String] {
        zip(uris, records).filter { claimedUris.contains($0.0) && TalerCardActionGate.showRefund($0.1) }.map(\.0)
    }

    public static func anyOpen(_ statuses: [TalerPaymentStatus?]) -> Bool {
        statuses.contains(.offen)
    }

    /// Plausibilitaetspruefung der von Taler mitgelieferten Summe gegen den
    /// bekannten Pro-Anteil-Betrag. Divisor = URI-Anzahl (+1, wenn der Sender
    /// sich mitgezaehlt hat); Toleranz 1e-6 (Anteile sind auf 8 Stellen
    /// abgerundet). `nil` = keine Summe anzeigen (fail-safe).
    public static func computeVerifiedTotal(totalAmount: String?, includeSelf: Bool?, uriCount: Int, perShareAmount: String?) -> Decimal? {
        guard
            let totalAmount,
            let includeSelf,
            let perShareAmount,
            uriCount > 0,
            let total = decimal(totalAmount),
            let perShare = decimal(perShareAmount)
        else {
            return nil
        }
        let divisor = includeSelf ? uriCount + 1 : uriCount
        let expected = perShare * Decimal(divisor)
        var difference = expected - total
        if difference < 0 {
            difference = -difference
        }
        return difference <= Decimal(string: "0.000001", locale: Locale(identifier: "en_US_POSIX"))! ? total : nil
    }

    /// Strikter Dezimal-Parser (wie `toBigDecimalOrNull`): nur Ziffern mit
    /// optionalem Punkt.
    static func decimal(_ value: String) -> Decimal? {
        let pattern = #"^-?[0-9]+(\.[0-9]+)?$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func plainString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    // MARK: - Sammelkarte

    /// Rolle des Betrachters aus der LOKALEN Gruppenmitgliedschaft:
    /// sender-seitig ist der Absender die eigene ACI, empfaengerseitig die
    /// authorAddress der eingehenden Nachricht; die Empfaengerliste kommt
    /// aus der bekannten Mitgliedschaft, nicht aus der Nachricht
    /// (GroupSplitRecipients.kt). Von buildCard (S3) und dem Long-Press-Menue
    /// (S6) gemeinsam genutzt.
    public static func resolveRole(message: TSMessage, thread: TSThread?, transaction: DBReadTransaction) -> TalerGroupCardRole {
        let myAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aci.serviceIdString
        let senderAci: String?
        if let incoming = message as? TSIncomingMessage {
            senderAci = incoming.authorAddress.aciString
        } else {
            senderAci = myAci
        }
        // recipientAcis kommt aus der lokal bekannten Gruppenmitgliedschaft,
        // nicht aus der Nachricht (GroupSplitRecipients.kt).
        let recipientAcis: [String]? = (thread as? TSGroupThread).map { groupThread in
            TalerGroupSplit.recipientAcis(
                memberAcis: groupThread.groupModel.groupMembership.fullMembers.compactMap { $0.aciString },
                senderAci: senderAci ?? ""
            )
        }
        if let myAci, let senderAci {
            return resolveRole(recipientAcis: recipientAcis, senderAci: senderAci, myAci: myAci)
        }
        return .notAParticipant
    }

    /// Baut Modell und Annehmen-URI der Sammelkarte fuer eine Nachricht mit
    /// mehreren Anteilen. Spiegel von `bindGroupCard`
    /// (TalerPaymentCardPresenter.kt, signal-android):
    ///  - Rolle des Betrachters aus der LOKALEN Gruppenmitgliedschaft
    ///    (Ersteller = eigene Nachricht, Empfaenger = Mitglied ausser dem
    ///    Absender, sonst kein Teilnehmer),
    ///  - Betrag: die per `computeVerifiedTotal` gegen den Pro-Anteil-Betrag
    ///    gepruefte Gesamtsumme; ohne verifizierte Summe der gepruefte
    ///    Pro-Anteil-Betrag, ohne jeden Record ein Platzhalter (Regel 5:
    ///    niemals eine Zahl aus dem Nachrichtentext),
    ///  - Fortschritt "x von N bezahlt" aus den Record-Statusen,
    ///  - Annehmen-Knopf gebunden an den naechsten offenen Anteil ab dem
    ///    eigenen Index, nur solange dieses Geraet noch keinen Anteil der
    ///    Nachricht beansprucht hat (GroupClaimTracker).
    public static func buildCard(
        message: TSMessage,
        thread: TSThread,
        uris: [String],
        records: [TalerPaymentRecord?],
        totalAmount: String?,
        includeSelf: Bool?,
        otherPartyName: String?,
        transaction: DBReadTransaction
    ) -> TalerGroupCard {
        // Alle Anteile derselben Nachricht teilen Betrag/Waehrung/Zweck/
        // Exchange - der erste bekannte Datensatz reicht als Quelle.
        let record = records.compactMap { $0 }.first
        let statuses = records.map { $0?.status }

        // Rollenaufloesung aus der lokal bekannten Gruppenmitgliedschaft
        // (siehe resolveRole).
        let role = resolveRole(message: message, thread: thread, transaction: transaction)
        let isOwnCard = role == .creator

        // Naechster offener Anteil ab dem eigenen Index, nur wenn dieses
        // Geraet noch keinen Anteil dieser Nachricht beansprucht hat.
        let alreadyClaimed = TalerGroupClaimTracker.shared.hasClaimedAny(uris)
        var acceptUri: String?
        if case .recipient(let myIndex) = role, !alreadyClaimed {
            acceptUri = resolveTargetUri(uris: uris, statuses: statuses, startIndex: myIndex)
        }

        let verifiedTotal = computeVerifiedTotal(
            totalAmount: totalAmount,
            includeSelf: includeSelf,
            uriCount: uris.count,
            perShareAmount: record?.amount
        )
        let amountText: String
        if let verifiedTotal {
            amountText = TalerCardModel.formatAmount(plainString(verifiedTotal))
        } else if let amount = record?.amount {
            amountText = TalerCardModel.formatAmount(amount)
        } else {
            amountText = TalerStrings.amountPending
        }

        let accepted = countAccepted(statuses)
        let progress = TalerCardModel.SplitProgress(
            accepted: accepted,
            total: uris.count,
            text: String(format: TalerStrings.splitProgressFormat, accepted, uris.count)
        )

        var splitNote: String?
        if let verifiedTotal, let includeSelf {
            let totalText = TalerCardModel.formatAmount(plainString(verifiedTotal))
            let symbol = TalerCardModel.currencySymbol(record?.currency)
            splitNote = includeSelf
                ? String(format: TalerStrings.splitNoteWithSelfFormat, totalText, symbol, uris.count + 1, uris.count)
                : String(format: TalerStrings.splitNoteWithoutSelfFormat, totalText, symbol, uris.count)
        }

        let directionIn = !isOwnCard
        let model = TalerCardModel(
            kindLabel: TalerCardModel.kindLabel(record?.uriKind),
            directionIn: directionIn,
            amountText: amountText,
            currencySymbol: TalerCardModel.currencySymbol(record?.currency),
            partyText: directionIn ? TalerStrings.partyToYou : TalerStrings.partyFromYou,
            summary: record?.summary.flatMap { $0.isEmpty ? nil : $0 },
            exchangeHost: TalerCardModel.displayHost(record?.exchangeBaseUrl),
            statusIcon: "",
            statusText: TalerCardModel.plainStatusLabel(record?.status ?? .unbekanntOffline),
            statusTone: .neutral,
            showAccept: acceptUri != nil,
            splitNote: splitNote,
            splitProgress: progress
        )
        return TalerGroupCard(model: model, acceptUri: acceptUri)
    }
}

/// Welche Anteile einer Gruppen-Split-Nachricht DIESES Geraet beansprucht
/// hat - damit dieselbe Karte nicht einen zweiten Anteil annehmen laesst.
/// Spiegel von `GroupClaimTracker.kt` (dort SharedPreferences).
public final class TalerGroupClaimTracker {
    public static let shared = TalerGroupClaimTracker(defaults: .standard)

    private static let key = "TalerGroupClaims"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private var claimed: Set<String> {
        Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    public func track(_ uri: String) {
        lock.withLock {
            var current = claimed
            current.insert(uri)
            defaults.set(Array(current), forKey: Self.key)
        }
    }

    public func hasClaimedAny(_ uris: [String]) -> Bool {
        lock.withLock { !claimed.isDisjoint(with: uris) }
    }

    public func claimedOf(_ uris: [String]) -> Set<String> {
        lock.withLock { claimed.intersection(uris) }
    }
}
