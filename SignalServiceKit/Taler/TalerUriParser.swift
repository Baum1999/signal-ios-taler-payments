//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Klassifiziert Taler-URIs anhand ihres Pfad-Praefixes. Swift-Spiegel von
/// `net.taler.wallet.link.TalerUriParser` (taler-android, von signal-android
/// byte-identisch uebernommen) - gleiche Praefixe, gleiche Reihenfolge,
/// kein Netzwerk.
public enum TalerUriParser {

    public static func classify(_ uri: String) -> TalerUriKind? {
        let normalized = uri.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let action: Substring
        if normalized.hasPrefix("taler://") {
            action = normalized.dropFirst("taler://".count)
        } else if normalized.hasPrefix("ext+taler://") {
            action = normalized.dropFirst("ext+taler://".count)
        } else if normalized.hasPrefix("taler+http://") {
            action = normalized.dropFirst("taler+http://".count)
        } else {
            return nil
        }

        if action.hasPrefix("pay-push/") {
            return .payPush
        } else if action.hasPrefix("pay-pull/") {
            return .payPull
        } else if action.hasPrefix("pay/") || action.hasPrefix("pay-template/") {
            return .pay
        } else if action.hasPrefix("withdraw/") || action.hasPrefix("withdraw-exchange/") {
            return .withdraw
        } else if action.hasPrefix("refund/") {
            return .refund
        }
        return nil
    }
}
