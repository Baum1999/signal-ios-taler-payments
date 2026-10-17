//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// Gemeinsames Farbmapping fuer `TalerCardModel.Tone`, Theme-/Dark-Mode-
/// faehig: `UIColor` mit dynamischem Provider, im dunklen Theme aufgehellt,
/// damit die Farben auf dunklem Grund lesbar bleiben. Alle Taler-Flaechen
/// (Zahlungskarte S3, Medien-Tab S8) fragen ihre Farben hier ab, damit sie
/// dieselbe Sprache sprechen - keine festen Hex-Werte mehr in den Views.
enum TalerToneColors {

    /// Amber: offen / wartet auf jemanden.
    static let waiting = dynamic(light: 0xB26A00, dark: 0xFFB454)

    /// Gruen: abgeschlossen.
    static let ok = dynamic(light: 0x2E7D32, dark: 0x81C784)

    /// Rot: abgelehnt, abgebrochen, abgelaufen, ungueltig.
    static let bad = dynamic(light: 0xC62828, dark: 0xEF9A9A)

    /// Neutral: keine Aussage - wie Secondary Label des Themes.
    static let neutral: UIColor = .Signal.secondaryLabel

    /// Farbe zu einer Tonalitaet.
    static func color(for tone: TalerCardModel.Tone) -> UIColor {
        switch tone {
        case .neutral:
            return neutral
        case .waiting:
            return waiting
        case .ok:
            return ok
        case .bad:
            return bad
        }
    }

    /// Farbe zu einem Zahlungsstatus. Spiegelt die Tonvergabe aus
    /// `TalerCardModel.compactStatus` (die selbst intern ist): offen zaehlt
    /// als "wartet", offline/offen-ohne-Kontext bleibt neutral.
    static func color(for status: TalerPaymentStatus) -> UIColor {
        let tone: TalerCardModel.Tone
        switch status {
        case .offen:
            tone = .waiting
        case .angenommen:
            tone = .ok
        case .lokalAbgelehnt, .lokalAbgebrochen, .abgelaufen, .ungueltig:
            tone = .bad
        case .unbekanntOffline:
            tone = .neutral
        }
        return color(for: tone)
    }

    /// Theme-faehige Farbe: heller Wert fuer helles Theme, aufgehellter Wert
    /// fuer dunkles Theme.
    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor(dynamicProvider: { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(rgbHex: dark) : UIColor(rgbHex: light)
        })
    }
}
