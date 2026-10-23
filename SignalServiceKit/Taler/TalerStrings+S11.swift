//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Strings fuer Paket S11 (Weiterleiten/Kopieren als Bild oder Text,
/// Taler-Status in den Einstellungen). Eigene Datei als extension, damit
/// TalerStrings.swift selbst unangetastet bleibt. Die Texte entsprechen
/// Android (TalerFork_*).
extension TalerStrings {

    // MARK: Weiterleiten/Kopieren (Zielbild 4.9)

    public static var menuForwardAsImage: String {
        TalerLocalizedString("TALER_MENU_FORWARD_AS_IMAGE", comment: "Long-press menu action on a Taler message: forward the payment card as an image")
    }

    public static var menuForwardAsText: String {
        TalerLocalizedString("TALER_MENU_FORWARD_AS_TEXT", comment: "Long-press menu action on a Taler message: forward the raw payment link(s) as text")
    }

    public static var menuCopyAsImage: String {
        TalerLocalizedString("TALER_MENU_COPY_AS_IMAGE", comment: "Long-press menu action on a Taler message: copy the payment card as an image")
    }

    /// Der Text beschreibt das Inhaberpapier-Risiko (Regel: die URI selbst
    /// erscheint hier nicht).
    public static var forwardWarningMessage: String {
        TalerLocalizedString("TALER_FORWARD_WARNING_MESSAGE", comment: "Message of the confirmation dialog before forwarding an unclaimed Taler payment as text")
    }

    // MARK: Einstellungen

    public static var settingsWalletLabel: String {
        TalerLocalizedString("TALER_SETTINGS_WALLET_LABEL", comment: "Settings row label for the GNU Taler wallet status")
    }

    public static var settingsWalletInstalled: String {
        TalerLocalizedString("TALER_SETTINGS_WALLET_INSTALLED", comment: "Settings row value: the GNU Taler wallet app is installed")
    }

    public static var settingsWalletNotInstalled: String {
        TalerLocalizedString("TALER_SETTINGS_WALLET_NOT_INSTALLED", comment: "Settings row value: the GNU Taler wallet app is not installed")
    }
}
