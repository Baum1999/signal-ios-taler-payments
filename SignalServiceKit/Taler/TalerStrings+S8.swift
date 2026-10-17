//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Strings des Pakets S8 (Taler-Tab in der Medienuebersicht). Bewusst in
/// einer eigenen Datei als Extension, damit `TalerStrings.swift` unberuehrt
/// bleibt. Pluralfaelle (1 vs. N) werden als getrennte Keys gefuehrt, weil
/// PluralAware.stringsdict fuer Fork-Keys nicht angefasst wird.
extension TalerStrings {

    /// Titel des Tab-Knopfs neben den Medien-Segmenten.
    public static var mediaTabTitle: String {
        OWSLocalizedString("TALER_MEDIA_TAB_TITLE", comment: "Title of the Taler tab in the chat's media overview")
    }

    // MARK: - Filter-Chips

    public static var threadFilterAll: String {
        OWSLocalizedString("TALER_THREAD_FILTER_ALL", comment: "Filter chip in the Taler tab: show all payments")
    }

    public static var threadFilterOpen: String {
        OWSLocalizedString("TALER_THREAD_FILTER_OPEN", comment: "Filter chip in the Taler tab: show only open payments")
    }

    public static var threadFilterReceived: String {
        OWSLocalizedString("TALER_THREAD_FILTER_RECEIVED", comment: "Filter chip in the Taler tab: show only payments received from the other side")
    }

    public static var threadFilterSent: String {
        OWSLocalizedString("TALER_THREAD_FILTER_SENT", comment: "Filter chip in the Taler tab: show only payments sent by the viewer")
    }

    // MARK: - Kopfzeile

    public static var threadLatestReceived: String {
        OWSLocalizedString("TALER_THREAD_LATEST_RECEIVED", comment: "Direction label for the latest payment in the Taler tab header: received")
    }

    public static var threadLatestSent: String {
        OWSLocalizedString("TALER_THREAD_LATEST_SENT", comment: "Direction label for the latest payment in the Taler tab header: sent")
    }

    public static var threadLatestPrefix: String {
        OWSLocalizedString("TALER_THREAD_LATEST_PREFIX", comment: "Prefix of the 'latest activity' line in the Taler tab header")
    }

    public static var threadBalancePrefix: String {
        OWSLocalizedString("TALER_THREAD_BALANCE_PREFIX", comment: "Prefix of the balance line in the Taler tab header")
    }

    public static var threadEmptyFilterMessage: String {
        OWSLocalizedString("TALER_THREAD_EMPTY_FILTER", comment: "Hint in the Taler tab when the selected filter matches no payments")
    }

    // MARK: - Headline (Rangfolge aus TalerThreadHeadline)

    public static var headlineWaitingForMe: String {
        OWSLocalizedString("TALER_HEADLINE_WAITING_FOR_ME", comment: "Taler tab headline: one payment is waiting for the viewer to act")
    }

    public static var headlineWaitingForMeFormat: String {
        OWSLocalizedString("TALER_HEADLINE_WAITING_FOR_ME_FORMAT", comment: "Taler tab headline: number of payments waiting for the viewer. Embeds {{ count }}.")
    }

    public static var headlineWaitingForOtherNameFormat: String {
        OWSLocalizedString("TALER_HEADLINE_WAITING_FOR_OTHER_NAME_FORMAT", comment: "Taler tab headline: payments waiting for the other side, named by chat partner. Embeds {{ name }}.")
    }

    public static var headlineWaitingForOther: String {
        OWSLocalizedString("TALER_HEADLINE_WAITING_FOR_OTHER", comment: "Taler tab headline: one payment is waiting for the other side (unnamed, e.g. in groups)")
    }

    public static var headlineWaitingForOtherFormat: String {
        OWSLocalizedString("TALER_HEADLINE_WAITING_FOR_OTHER_FORMAT", comment: "Taler tab headline: number of payments waiting for the other side. Embeds {{ count }}.")
    }

    public static var headlineWaitingForBothFormat: String {
        OWSLocalizedString("TALER_HEADLINE_WAITING_FOR_BOTH_FORMAT", comment: "Taler tab headline: payments open on both sides. Embeds {{ count waiting for viewer }}, {{ count waiting for other side }}.")
    }

    public static var headlineUnverifiable: String {
        OWSLocalizedString("TALER_HEADLINE_UNVERIFIABLE", comment: "Taler tab headline: one payment could not be verified")
    }

    public static var headlineUnverifiableFormat: String {
        OWSLocalizedString("TALER_HEADLINE_UNVERIFIABLE_FORMAT", comment: "Taler tab headline: number of payments that could not be verified. Embeds {{ count }}.")
    }

    public static var headlineAllSettled: String {
        OWSLocalizedString("TALER_HEADLINE_ALL_SETTLED", comment: "Taler tab headline: nothing open, all payments are settled")
    }
}

/// Uebersetzung der Headline-Rangfolge (S5, `TalerThreadHeadline`) in Icon und
/// Text der Kopfzeile. Reine Logik ohne UIKit, damit die Zweigauswahl -
/// insbesondere Singular/Plural und die Namensersetzung im 1:1-Chat -
/// testbar bleibt. Die Farbe waehlt die View anhand der Headline selbst.
public enum TalerThreadHeadlineFormat {

    public static func label(for headline: TalerThreadHeadline, chatName: String?) -> (icon: String, text: String) {
        switch headline {
        case .empty:
            return ("", "")
        case .waitingForMe(let count):
            // Der Tab existiert nur mit mindestens einem Vorgang; die Anzahl
            // steht im Text, damit mehrere wartende Zahlungen nicht wie eine
            // wirken.
            return ("●", count == 1
                ? TalerStrings.headlineWaitingForMe
                : String(format: TalerStrings.headlineWaitingForMeFormat, count))
        case .waitingForOther(let count):
            // 1:1: Name des Gegenuebers statt "die Gegenseite"; ohne Namen
            // (Gruppe, fehlender Name) bleibt es bei der Zaehlung.
            if let name = chatName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return ("●", String(format: TalerStrings.headlineWaitingForOtherNameFormat, name))
            }
            return ("●", count == 1
                ? TalerStrings.headlineWaitingForOther
                : String(format: TalerStrings.headlineWaitingForOtherFormat, count))
        case .waitingForBoth(let forMe, let forOther):
            return ("●", String(format: TalerStrings.headlineWaitingForBothFormat, forMe, forOther))
        case .unverifiable(let count):
            return ("…", count == 1
                ? TalerStrings.headlineUnverifiable
                : String(format: TalerStrings.headlineUnverifiableFormat, count))
        case .allSettled:
            // Anzahl steht hier nicht im Text: nichts Offenes ist die Aussage.
            return ("✓", TalerStrings.headlineAllSettled)
        }
    }
}
