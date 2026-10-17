//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Strings fuer Paket S6 (Statuszeilen, Long-Press-Menue, Ablehnen-Dialog).
/// Eigene Datei als extension, damit TalerStrings.swift selbst unangetastet
/// bleibt. Die deutschen Texte entsprechen Android (TalerFork_*).
extension TalerStrings {

    // MARK: Statuszeilen (E7, lokal, werden nie gesendet)

    public static var statusLineAccepted: String {
        OWSLocalizedString("TALER_STATUS_LINE_ACCEPTED", comment: "Local status line in the chat: a Taler payment was accepted")
    }

    public static var statusLineExpired: String {
        OWSLocalizedString("TALER_STATUS_LINE_EXPIRED", comment: "Local status line in the chat: a Taler payment link expired")
    }

    public static var statusLineDeclined: String {
        OWSLocalizedString("TALER_STATUS_LINE_DECLINED", comment: "Local status line in the chat: a Taler payment was declined on this device")
    }

    public static var statusLineCancelled: String {
        OWSLocalizedString("TALER_STATUS_LINE_CANCELLED", comment: "Local status line in the chat: a Taler payment was cancelled by deleting the message")
    }

    // MARK: Long-Press-Menue

    public static var menuReject: String {
        OWSLocalizedString("TALER_MENU_REJECT", comment: "Long-press menu action on a Taler message: decline the payment on this device")
    }

    public static var menuCancel: String {
        OWSLocalizedString("TALER_MENU_CANCEL", comment: "Long-press menu action on a Taler message: cancel an own open payment")
    }

    public static var menuRefresh: String {
        OWSLocalizedString("TALER_MENU_REFRESH", comment: "Long-press menu action on a Taler message: refresh the payment status")
    }

    public static var menuCopyTranscript: String {
        OWSLocalizedString("TALER_MENU_COPY_TRANSCRIPT", comment: "Long-press menu action on a Taler message: copy the message body")
    }

    // MARK: Ablehnen-Dialog

    public static var rejectDialogTitle: String {
        OWSLocalizedString("TALER_REJECT_DIALOG_TITLE", comment: "Title of the confirmation dialog when declining a Taler payment")
    }

    /// Der Text darf nie Rueckfluss von Geld suggerieren (Regel 1: Signal
    /// bewegt kein Geld, der Absender wird nicht benachrichtigt).
    public static var rejectDialogMessage: String {
        OWSLocalizedString("TALER_REJECT_DIALOG_MESSAGE", comment: "Message of the confirmation dialog when declining a Taler payment")
    }

    public static var rejectDialogConfirm: String {
        OWSLocalizedString("TALER_REJECT_DIALOG_CONFIRM", comment: "Confirm button of the decline dialog for a Taler payment")
    }
}
