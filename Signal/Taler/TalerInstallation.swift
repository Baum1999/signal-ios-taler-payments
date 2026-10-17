//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// Zentraler, thread-sicher lesbarer Cache dafuer, ob eine App das
/// `talerlink://`-Schema registriert hat (Voraussetzung: `talerlink` in
/// LSApplicationQueriesSchemes). Spiegel von `TalerInstallation`
/// (signal-android), das dort PackageManager-Fragen klumpen; hier ist die
/// einzige Quelle `UIApplication.canOpenURL`.
///
/// `UIApplication.canOpenURL` darf nur vom Main-Thread aufgerufen werden.
/// Deshalb wird der Wert beim App-Start und bei jedem Aktiv-Werden auf dem
/// Main-Thread frisch geprueft (`refresh()`); der Ladepfad der Karte
/// (`CVComponentTalerPayment.buildState`) und alles andere Lesen greift
/// nur auf den gespeicherten Wert zu (`isInstalled`). Wer wirklich oeffnet
/// (Karte, Menue, Launcher, Einstellungszeile), prueft beim Tippen
/// zusaetzlich frisch.
enum TalerInstallation {

    private static let lock = NSLock()
    private static var cachedValue = false

    /// Gespeicherter Installationszustand; von jedem Thread lesbar.
    static var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedValue
    }

    /// Frische Pruefung auf dem Main-Thread (App-Start, `didBecomeActive`,
    /// und vor jedem tatsaechlichen Oeffnen eines Taler-Links). Aktualisiert
    /// den Cache und liefert den frischen Wert.
    @discardableResult
    static func refresh() -> Bool {
        AssertIsOnMainThread()
        guard let probeUrl = URL(string: "\(TalerLinks.linkScheme)://") else {
            owsFailDebug("Taler-Scheme-URL nicht baubar")
            lock.lock()
            defer { lock.unlock() }
            return cachedValue
        }
        let installed = UIApplication.shared.canOpenURL(probeUrl)
        lock.lock()
        cachedValue = installed
        lock.unlock()
        return installed
    }
}
