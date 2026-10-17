//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Oeffnet die Taler-App fuer den Annehmen-Flow einer Karten-URI. Signal
/// bewegt dabei kein Geld (Regel 1) - bestaetigt wird nur in der Taler-UI
/// durch den Nutzer. Die URI ist ein Inhaberpapier: sie erscheint in keiner
/// Logmeldung und keiner Fehlermeldung.
enum TalerCardActions {

    /// Registriert die Korrelation unter einer frischen correlationId und
    /// oeffnet den Aktionslink. `isGroupShare` beansprucht den Anteil vorher
    /// fuer dieses Geraet (wie Android: das Tracking muss vor dem Deep-Link
    /// passieren, die Rueckkehr aus Taler ist nicht synchron).
    static func accept(uri: String, threadUniqueId: String, isGroupShare: Bool) {
        // Beim Tippen frisch pruefen (der Knopf konnte seit dem Menueaufbau
        // veralten, z.B. weil Taler deinstalliert wurde); der Ladepfad der
        // Karte liest nur den Cache (TalerInstallation.isInstalled).
        guard TalerInstallation.refresh() else {
            OWSActionSheets.showActionSheet(
                title: TalerStrings.alertTalerNotInstalledTitle,
                message: TalerStrings.alertTalerNotInstalledBody
            )
            return
        }
        if isGroupShare {
            TalerGroupClaimTracker.shared.track(uri)
        }
        let correlationId = TalerCorrelationStore.shared.register(
            TalerCorrelationEntry(
                intent: .acceptOrCancel,
                threadUniqueId: threadUniqueId,
                uri: uri,
                uris: [],
                quoteInteractionUniqueId: nil
            )
        )
        guard let link = TalerLinks.actionLink(forTalerUri: uri, correlationId: correlationId) else {
            owsFailDebug("Aktionslink konnte nicht gebaut werden.")
            return
        }
        UIApplication.shared.open(link, options: [:]) { success in
            if !success {
                DispatchQueue.main.async {
                    OWSActionSheets.showActionSheet(
                        title: TalerStrings.alertTalerNotInstalledTitle,
                        message: TalerStrings.alertTalerNotInstalledBody
                    )
                }
            }
        }
    }

    /// Abbrechen eines eigenen, offenen pay-push: derselbe
    /// ACCEPT_OR_CANCEL-Flow wie Annehmen - Talers eigene UI bricht die
    /// Zahlung ab, Signal bestaetigt nichts (Regel 1). Der Ruecksprung loest
    /// den Fast-Poll aus (Paket S4); der Status aendert sich erst durch
    /// Taler bzw. den Exchange, nie lokal.
    static func cancel(uri: String, threadUniqueId: String) {
        // Beim Tippen frisch pruefen (siehe accept).
        guard TalerInstallation.refresh() else {
            OWSActionSheets.showActionSheet(
                title: TalerStrings.alertTalerNotInstalledTitle,
                message: TalerStrings.alertTalerNotInstalledBody
            )
            return
        }
        let correlationId = TalerCorrelationStore.shared.register(
            TalerCorrelationEntry(
                intent: .acceptOrCancel,
                threadUniqueId: threadUniqueId,
                uri: uri,
                uris: [],
                quoteInteractionUniqueId: nil
            )
        )
        guard let link = TalerLinks.actionLink(forTalerUri: uri, correlationId: correlationId) else {
            owsFailDebug("Aktionslink konnte nicht gebaut werden.")
            return
        }
        UIApplication.shared.open(link, options: [:])
    }
}
