//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Reine Darstellungslogik der Zahlungskarte, ohne UIKit - Spiegel von
/// `TalerPaymentCardPresenter.bind()/getCompactStatus()/displayHost()` und
/// `TalerCardActionGate` (signal-android). Die View setzt das Modell nur um.
public struct TalerCardModel: Equatable, Sendable {

    public enum Tone: Equatable, Sendable {
        case neutral
        case waiting
        case ok
        case bad
    }

    public var kindLabel: String
    /// `true` = Geld kommt beim Betrachter an (↓, "an dich").
    public var directionIn: Bool
    /// Mit Komma als Dezimaltrenner, wie auf Android.
    public var amountText: String
    public var currencySymbol: String
    public var partyText: String
    public var summary: String?
    public var exchangeHost: String?
    public var statusIcon: String
    public var statusText: String
    public var statusTone: Tone
    public var showAccept: Bool
    /// Nur Gruppen-Split.
    public var splitNote: String?
    /// Nur Gruppen-Split: (angenommen, gesamt).
    public var splitProgress: SplitProgress?

    public struct SplitProgress: Equatable, Sendable {
        public var accepted: Int
        public var total: Int
        public var text: String
    }

    // MARK: - Einzelkarte

    public static func build(record: TalerPaymentRecord?, otherPartyName: String?) -> TalerCardModel {
        let status = record?.status ?? .unbekanntOffline
        let isOwnPayment = record?.isOwnPayment ?? false
        let directionIn = isDirectionIn(kind: record?.uriKind, isOwnPayment: isOwnPayment)
        let (icon, text, tone) = compactStatus(record: record, status: status, otherPartyName: otherPartyName)
        // Regel 5: Betraege nur aus dem Record (verifiziert). Ohne Record-Betrag
        // steht ein Platzhalter, niemals eine Zahl aus dem Nachrichtentext.
        let amountText = record?.amount.map(formatAmount) ?? TalerStrings.amountPending
        return TalerCardModel(
            kindLabel: kindLabel(record?.uriKind),
            directionIn: directionIn,
            amountText: amountText,
            currencySymbol: currencySymbol(record?.currency),
            partyText: directionIn ? TalerStrings.partyToYou : TalerStrings.partyFromYou,
            summary: record?.summary.flatMap { $0.isEmpty ? nil : $0 },
            exchangeHost: displayHost(record?.exchangeBaseUrl),
            statusIcon: icon,
            statusText: text,
            statusTone: tone,
            showAccept: TalerCardActionGate.showAccept(record),
            splitNote: nil,
            splitProgress: nil,
        )
    }

    /// Geld verlaesst den Betrachter, wenn (pull) XOR (eigene Zahlung):
    /// eigener Push = raus, fremder Pull = raus.
    public static func isDirectionIn(kind: TalerUriKind?, isOwnPayment: Bool) -> Bool {
        let isPull = kind == .payPull
        let moneyLeavesMe = isPull != isOwnPayment
        return !moneyLeavesMe
    }

    public static func formatAmount(_ amount: String?) -> String {
        (amount ?? "0").replacingOccurrences(of: ".", with: ",")
    }

    /// Waehrungssymbole wie in der Taler-Wallet (KUDOS = "ク").
    public static func currencySymbol(_ currency: String?) -> String {
        guard let currency else {
            return ""
        }
        switch currency {
        case "KUDOS": return "ク"
        case "EUR": return "€"
        case "USD": return "$"
        default: return currency
        }
    }

    public static func kindLabel(_ kind: TalerUriKind?) -> String {
        switch kind {
        case .payPush: return TalerStrings.kindPayPush
        case .payPull: return TalerStrings.kindPayPull
        case .pay: return TalerStrings.kindPay
        case .withdraw: return TalerStrings.kindWithdraw
        case .refund: return TalerStrings.kindRefund
        case nil: return TalerStrings.kindUnknown
        }
    }

    /// Host fuer den Exchange-Chip. Nicht-ASCII-Hosts werden nie in ihrer
    /// Unicode-Form gezeigt (Homograph-Risiko): `URLComponents` liefert den
    /// Host bereits punycodiert; bleibt trotzdem Nicht-ASCII uebrig, wird er
    /// ausgeblendet.
    public static func displayHost(_ exchangeBaseUrl: String?) -> String? {
        guard let exchangeBaseUrl, let host = URL(string: exchangeBaseUrl)?.host, !host.isEmpty else {
            return nil
        }
        if host.unicodeScalars.contains(where: { $0.value > 127 }) {
            return nil
        }
        return host
    }

    public static func plainStatusLabel(_ status: TalerPaymentStatus) -> String {
        switch status {
        case .offen: return TalerStrings.statusOpen
        case .angenommen: return TalerStrings.statusAccepted
        case .lokalAbgelehnt: return TalerStrings.statusDeclined
        case .lokalAbgebrochen: return TalerStrings.statusCancelled
        case .abgelaufen: return TalerStrings.statusExpired
        case .unbekanntOffline: return TalerStrings.statusChecking
        case .ungueltig: return TalerStrings.statusInvalid
        }
    }

    static func compactStatus(record: TalerPaymentRecord?, status: TalerPaymentStatus, otherPartyName: String?) -> (String, String, Tone) {
        let name = otherPartyName.flatMap { $0.isEmpty ? nil : $0 }
        if status == .offen, record?.uriKind == .payPush, let record {
            if record.isOwnPayment {
                return ("⏳", String(format: TalerStrings.statusWaitingForRecipientFormat, name ?? TalerStrings.recipientFallback), .waiting)
            }
            return ("⏳", TalerStrings.statusWaitingForAcceptance, .waiting)
        }
        if status == .angenommen, record?.uriKind == .payPush, let record {
            if record.isOwnPayment {
                return ("✓", String(format: TalerStrings.statusSentConfirmedFormat, name ?? TalerStrings.recipientFallback), .ok)
            }
            return ("✓", String(format: TalerStrings.statusAcceptedFromFormat, name ?? TalerStrings.senderFallback), .ok)
        }
        let icon: String
        switch status {
        case .offen: icon = "○"
        case .angenommen: icon = "✓"
        case .lokalAbgelehnt: icon = "✕"
        case .lokalAbgebrochen: icon = "⊘"
        case .abgelaufen: icon = "⏱"
        case .unbekanntOffline: icon = "…"
        case .ungueltig: icon = "!"
        }
        let tone: Tone
        switch status {
        case .angenommen: tone = .ok
        case .lokalAbgelehnt, .lokalAbgebrochen, .abgelaufen, .ungueltig: tone = .bad
        default: tone = .neutral
        }
        return (icon, plainStatusLabel(status), tone)
    }
}

/// Sichtbarkeit der Aktionen fuer eine Einzel-URI. Spiegel von
/// `TalerCardActionGate` (signal-android) - dieselbe Wahrheitstabelle fuer
/// Karte und Long-Press-Menue.
public enum TalerCardActionGate {

    /// Annehmen/Ablehnen: offener, fremder pay-push.
    public static func showAccept(_ record: TalerPaymentRecord?) -> Bool {
        record?.status == .offen && record?.uriKind == .payPush && record?.isOwnPayment == false
    }

    public static func showReject(_ record: TalerPaymentRecord?) -> Bool {
        showAccept(record)
    }

    /// Abbrechen/Aktualisieren: eigener, noch offener pay-push.
    public static func showCancel(_ record: TalerPaymentRecord?) -> Bool {
        record?.status == .offen && record?.uriKind == .payPush && record?.isOwnPayment == true
    }

    public static func showRefresh(_ record: TalerPaymentRecord?) -> Bool {
        showCancel(record)
    }

    /// Rueckerstatten: fremde, bereits angenommene Zahlung.
    public static func showRefund(_ record: TalerPaymentRecord?) -> Bool {
        record?.status == .angenommen && record?.isOwnPayment == false
    }
}
