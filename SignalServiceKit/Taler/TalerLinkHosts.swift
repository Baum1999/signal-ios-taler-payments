//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Einzige Stelle mit Domains fuer die https-Links nach DD 103 (siehe
/// `TalerHttpsLink`). Spiegel von `net.taler.wallet.link.TalerLinkHosts`
/// (signal-android). Forks mit eigener Link-Domain ueberschreiben nur diese
/// Datei, damit ein Rebase auf den Hauptzweig konfliktfrei bleibt.
public enum TalerLinkHosts {
    /// Domains, deren `/link#`-Links `TalerHttpsLink.unwrap` akzeptiert.
    public static let acceptedHosts = ["wallet.taler.net"]
}
