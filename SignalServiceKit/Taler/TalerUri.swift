//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Art einer Taler-URI. Spiegel von `net.taler.wallet.link.TalerUriKind`
/// (signal-android/taler-android). Die Rohwerte sind Teil des
/// App-uebergreifenden Link-Protokolls (`direction=PAY_PUSH` im
/// compose-send-Link) und in der Datenbank gespeichert - nicht umbenennen.
public enum TalerUriKind: String, CaseIterable, Codable, Sendable {
    case payPush = "PAY_PUSH"
    case payPull = "PAY_PULL"
    case pay = "PAY"
    case withdraw = "WITHDRAW"
    case refund = "REFUND"
}

/// Zustand eines Vorgangs, wie ihn die Exchange-Abfrage liefert. Spiegel von
/// `TalerOperationStatus` (Android).
public enum TalerOperationStatus: String, Sendable {
    case offen = "OFFEN"
    case angenommen = "ANGENOMMEN"
    case abgelaufen = "ABGELAUFEN"
    case ungueltig = "UNGUELTIG"
    case unbekanntOffline = "UNBEKANNT_OFFLINE"
}

/// Zustand eines Taler-Vorgangs aus Signals Sicht - Obermenge von
/// `TalerOperationStatus` um die rein lokalen Zustaende. Spiegel von
/// `org.thoughtcrime.securesms.taler.TalerPaymentStatus`; die Rohwerte werden
/// in der Tabelle `TalerPayment` gespeichert.
public enum TalerPaymentStatus: String, CaseIterable, Sendable {
    case offen = "OFFEN"
    case angenommen = "ANGENOMMEN"
    case lokalAbgelehnt = "LOKAL_ABGELEHNT"
    case lokalAbgebrochen = "LOKAL_ABGEBROCHEN"
    case abgelaufen = "ABGELAUFEN"
    case unbekanntOffline = "UNBEKANNT_OFFLINE"
    case ungueltig = "UNGUELTIG"

    public init(_ status: TalerOperationStatus) {
        switch status {
        case .offen: self = .offen
        case .angenommen: self = .angenommen
        case .abgelaufen: self = .abgelaufen
        case .ungueltig: self = .ungueltig
        case .unbekanntOffline: self = .unbekanntOffline
        }
    }

    /// Rein lokale Endzustaende - ein Exchange-Refresh darf sie nie
    /// ueberschreiben.
    public var isLocalTerminal: Bool {
        self == .lokalAbgelehnt || self == .lokalAbgebrochen
    }
}
