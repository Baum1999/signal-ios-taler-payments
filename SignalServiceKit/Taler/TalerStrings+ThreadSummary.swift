//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Strings des Pakets S5 (Kopfzeile des Taler-Tabs). Bewusst in einer eigenen
/// Datei als Extension, damit `TalerStrings.swift` unberuehrt bleibt.
extension TalerStrings {

    /// "N Exchanges" in der Kontextzeile, wenn der Saldo aus mehr als einem
    /// Exchange stammt. Embeds {{ count }}.
    public static var exchangeCountFormat: String {
        OWSLocalizedString("TALER_EXCHANGES_COUNT_FORMAT", comment: "Context line in the Taler tab: number of distinct exchanges. Embeds {{ count }}.")
    }
}
