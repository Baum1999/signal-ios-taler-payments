//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Strings fuer Paket S7a (Bestaetigungsnachricht). Eigene Datei als
/// extension, damit TalerStrings.swift selbst unangetastet bleibt.
///
/// Der Wortlaut der GESCHICKTEN Nachricht ist Protokoll und liegt deshalb
/// nicht lokalisiert in TalerStrings.swift (acceptConfirmationFormat,
/// wireKindPayPush/wireKindPayPull); hier steht nur die lokale Anzeige.
extension TalerStrings {

    // MARK: Anzeige erkannter Bestaetigungen

    /// Kompakte Zeile statt Rohtext fuer eine erkannte Bestaetigung.
    public static var confirmationLine: String {
        OWSLocalizedString("TALER_CONFIRMATION_LINE", comment: "Compact line shown in the chat instead of the raw text of a recognized Taler payment confirmation")
    }
}
