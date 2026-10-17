//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Strings des Pakets S3-card-wiring. Bewusst in einer eigenen Datei als
/// Extension, damit `TalerStrings.swift` unveraendert bleibt.
public extension TalerStrings {

    /// Platzhalter auf der Karte, solange kein verifizierter Betrag bekannt
    /// ist (Regel 5: nie eine Zahl aus dem Nachrichtentext).
    static var amountPending: String {
        OWSLocalizedString("TALER_CARD_AMOUNT_PENDING", comment: "Placeholder on a Taler payment card instead of an amount while no verified amount is known yet")
    }

    /// Hinweis-Alert, wenn das Oeffnen des Aktionslinks scheitert, weil keine
    /// Taler-App installiert ist.
    static var alertTalerNotInstalledTitle: String {
        OWSLocalizedString("TALER_NOT_INSTALLED_ALERT_TITLE", comment: "Alert title shown when the GNU Taler app is not installed")
    }

    static var alertTalerNotInstalledBody: String {
        OWSLocalizedString("TALER_NOT_INSTALLED_ALERT_BODY", comment: "Alert body shown when the GNU Taler app is not installed")
    }
}
