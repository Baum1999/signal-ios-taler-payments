//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Strings fuer Paket S7b (Zustellstatus bezahlt, Nachrichtendetails,
/// Zitat-Zusammenfassung). Eigene Datei als extension, damit
/// TalerStrings.swift selbst unangetastet bleibt.
extension TalerStrings {

    // MARK: Zitat-Zusammenfassung

    public static var quoteTitle: String {
        OWSLocalizedString("TALER_QUOTE_TITLE", comment: "Short summary shown instead of the raw payment URI when quoting a Taler message")
    }

    /// Betrifft mehrere Links (Gruppen-Split). Betrachtet {{ link count }}.
    public static var quoteGroupSummaryFormat: String {
        OWSLocalizedString("TALER_QUOTE_GROUP_SUMMARY_FORMAT", comment: "Short summary shown when quoting a Taler message with several payment links. Embeds {{ link count }}.")
    }

    // MARK: Nachrichtendetails

    public static var detailSectionTitle: String {
        OWSLocalizedString("TALER_DETAIL_SECTION_TITLE", comment: "Section title in the message details for a single Taler payment link")
    }

    public static var detailUriLabel: String {
        OWSLocalizedString("TALER_DETAIL_URI_LABEL", comment: "Row label in the message details for a shortened Taler payment link (long-press to copy)")
    }

    public static var detailStatusLabel: String {
        OWSLocalizedString("TALER_DETAIL_STATUS_LABEL", comment: "Row label in the message details for the Taler payment status")
    }

    public static var detailAmountLabel: String {
        OWSLocalizedString("TALER_DETAIL_AMOUNT_LABEL", comment: "Row label in the message details for the Taler payment amount")
    }

    /// Zeitpunkt der Erkennung durch Signal, ehrlich ohne Zahlungszeitpunkt.
    public static var detailDetectedLabel: String {
        OWSLocalizedString("TALER_DETAIL_DETECTED_LABEL", comment: "Row label in the message details for the time Signal first detected the Taler link")
    }

    public static var detailStatusChangedLabel: String {
        OWSLocalizedString("TALER_DETAIL_STATUS_CHANGED_LABEL", comment: "Row label in the message details for the time the Taler payment status last changed")
    }
}
