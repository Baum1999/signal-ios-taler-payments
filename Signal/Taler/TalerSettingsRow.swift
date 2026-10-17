//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Zeile "GNU Taler Wallet: installiert / nicht installiert" in den
/// App-Einstellungen (Zielbild, Android-Paritaet). Der Zustand kommt aus
/// dem zentralen Cache `TalerInstallation` (Main-Thread-Pruefung beim
/// App-Start und bei jedem Aktiv-Werden); das Oeffnen der Einstellungen
/// erfolgt nach einer solchen Pruefung, der gelesene Wert ist also frisch.
enum TalerSettingsRow {

    /// Die fertige Tabellenzeile; nicht interaktiv, nur Anzeige.
    static func tableItem() -> OWSTableItem {
        let statusText = TalerInstallation.isInstalled
            ? TalerStrings.settingsWalletInstalled
            : TalerStrings.settingsWalletNotInstalled
        return .label(
            withText: TalerStrings.settingsWalletLabel,
            accessoryText: statusText,
            accessoryType: .none,
        )
    }
}
