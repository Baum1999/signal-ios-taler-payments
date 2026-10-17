//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Strings fuer Paket S4 (compose-send starten, Ruecksprung annehmen). Eigene
/// Datei als extension, damit TalerStrings.swift selbst unangetastet bleibt.
extension TalerStrings {

    // MARK: compose-send starten (TalerComposeLauncher)

    /// Alert-Titel, wenn GNU Taler nicht installiert ist.
    public static var talerNotInstalledTitle: String {
        OWSLocalizedString("TALER_NOT_INSTALLED_TITLE", comment: "Title of an alert explaining that the GNU Taler app is not installed.")
    }

    /// Alert-Text, wenn GNU Taler nicht installiert ist.
    public static var talerNotInstalledMessage: String {
        OWSLocalizedString("TALER_NOT_INSTALLED_MESSAGE", comment: "Message of an alert explaining that the GNU Taler app must be installed to compose a Taler payment.")
    }

    /// Alert-Titel, wenn ein Taler-Versand in "Notiz an mich" angefragt wird.
    public static var noteToSelfUnsupportedTitle: String {
        OWSLocalizedString("TALER_NOTE_TO_SELF_TITLE", comment: "Title of an alert explaining that Taler payments cannot be composed in Note to Self.")
    }

    /// Alert-Text, wenn ein Taler-Versand in "Notiz an mich" angefragt wird.
    public static var noteToSelfUnsupportedMessage: String {
        OWSLocalizedString("TALER_NOTE_TO_SELF_MESSAGE", comment: "Message of an alert explaining that Taler payments cannot be composed in Note to Self.")
    }
}
