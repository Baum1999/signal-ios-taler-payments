//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Strings fuer Paket S9 (Rueckerstatten). Eigene Datei als extension, damit
/// TalerStrings.swift selbst unangetastet bleibt. Der Menue-Text entspricht
/// Android (TalerFork_action_refund).
extension TalerStrings {

    // MARK: Long-Press-Menue

    public static var menuRefund: String {
        OWSLocalizedString("TALER_MENU_REFUND", comment: "Long-press menu action on a Taler message: refund an accepted incoming payment, opens GNU Taler")
    }

    // MARK: Nachrichtentext (Protokoll, nicht lokalisiert)

    /// `Refund: %1$s` (Android TalerFork_refund_message). Wie die anderen
    /// Texte echter ausgehender Nachrichten bewusst NICHT lokalisiert: der
    /// Body wird gesendet und soll geraeteueberall identisch bleiben; Argument
    /// ist der Taler-seitige Verwendungszweck (legacyText) bzw. im
    /// Rueckfallpfad die URI selbst.
    public static let refundMessageFormat = "Refund: %@"
}
