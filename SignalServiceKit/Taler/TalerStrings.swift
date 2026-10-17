//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Nutzersichtbare Taler-Strings (Android: `TalerFork_*` in strings.xml).
///
/// Ausnahme: die Texte echter ausgehender Nachrichten
/// (`acceptConfirmationFormat`, `sendMessageFormat`, `requestMessageFormat`,
/// Art-Labels darin) sind bewusst NICHT lokalisiert. Der Empfaenger erkennt
/// die Bestaetigung per exaktem Textvergleich (`TalerConfirmationDetector`);
/// Android verschickt denselben englischen Wortlaut.
public enum TalerStrings {

    // MARK: Nachrichtentexte (Protokoll, nicht lokalisiert)

    public static let wireKindPayPush = "Taler payment link"
    public static let wireKindPayPull = "Taler payment request"
    /// `Payment for %1$s accepted (%2$s)`
    public static let acceptConfirmationFormat = "Payment for %@ accepted (%@)"
    public static let sendMessageFormat = "Payment sent: %@ (%@)"
    public static let requestMessageFormat = "Payment requested: %@ (%@)"
    public static let legacyText = "This is a GNU Taler link. Update Signal or copy the URI below into the GNU Taler app to make the payment."

    // MARK: Karte

    public static var kindPayPush: String { OWSLocalizedString("TALER_KIND_PAY_PUSH", comment: "Label on a payment card for a taler://pay-push/... link") }
    public static var kindPayPull: String { OWSLocalizedString("TALER_KIND_PAY_PULL", comment: "Label on a payment card for a taler://pay-pull/... link") }
    public static var kindPay: String { OWSLocalizedString("TALER_KIND_PAY", comment: "Label for a taler://pay/... link") }
    public static var kindWithdraw: String { OWSLocalizedString("TALER_KIND_WITHDRAW", comment: "Label for a taler://withdraw/... link") }
    public static var kindRefund: String { OWSLocalizedString("TALER_KIND_REFUND", comment: "Label for a taler://refund/... link") }
    public static var kindUnknown: String { OWSLocalizedString("TALER_KIND_UNKNOWN", comment: "Label for a recognized but uncategorized Taler link") }

    // MARK: Vorschau (Chatliste, Benachrichtigungen) - Android: TalerFork_preview_group_split

    public static var previewGroupSplit: String { OWSLocalizedString("TALER_PREVIEW_GROUP_SPLIT", comment: "Preview label in the chat list and notification banner for a group-split Taler payment (multiple Taler URIs)") }

    public static var partyToYou: String { OWSLocalizedString("TALER_PARTY_TO_YOU", comment: "Direction on a Taler card: money comes to the viewer") }
    public static var partyFromYou: String { OWSLocalizedString("TALER_PARTY_FROM_YOU", comment: "Direction on a Taler card: money leaves the viewer") }

    public static var statusOpen: String { OWSLocalizedString("TALER_STATUS_OPEN", comment: "Compact Taler payment status: open") }
    public static var statusAccepted: String { OWSLocalizedString("TALER_STATUS_ACCEPTED", comment: "Compact Taler payment status: accepted") }
    public static var statusDeclined: String { OWSLocalizedString("TALER_STATUS_DECLINED", comment: "Compact Taler payment status: declined locally") }
    public static var statusCancelled: String { OWSLocalizedString("TALER_STATUS_CANCELLED", comment: "Compact Taler payment status: cancelled") }
    public static var statusExpired: String { OWSLocalizedString("TALER_STATUS_EXPIRED", comment: "Compact Taler payment status: expired") }
    public static var statusChecking: String { OWSLocalizedString("TALER_STATUS_CHECKING", comment: "Compact Taler payment status: being checked") }
    public static var statusInvalid: String { OWSLocalizedString("TALER_STATUS_INVALID", comment: "Compact Taler payment status: payment failed / invalid") }
    public static var statusWaitingForAcceptance: String { OWSLocalizedString("TALER_STATUS_WAITING_FOR_ACCEPTANCE", comment: "Taler status on an incoming payment waiting for the viewer's acceptance") }
    public static var statusWaitingForRecipientFormat: String { OWSLocalizedString("TALER_STATUS_WAITING_FOR_RECIPIENT_FORMAT", comment: "Taler status on an own payment. Embeds {{ recipient name }}.") }
    public static var statusSentConfirmedFormat: String { OWSLocalizedString("TALER_STATUS_SENT_CONFIRMED_FORMAT", comment: "Taler status on an own accepted payment. Embeds {{ recipient name }}.") }
    public static var statusAcceptedFromFormat: String { OWSLocalizedString("TALER_STATUS_ACCEPTED_FROM_FORMAT", comment: "Taler status on an accepted incoming payment. Embeds {{ sender name }}.") }
    public static var recipientFallback: String { OWSLocalizedString("TALER_RECIPIENT_FALLBACK", comment: "Fallback name for the recipient of a Taler payment") }
    public static var senderFallback: String { OWSLocalizedString("TALER_SENDER_FALLBACK", comment: "Fallback name for the sender of a Taler payment") }

    public static var actionAccept: String { OWSLocalizedString("TALER_ACTION_ACCEPT", comment: "Button on a Taler card: accept, opens GNU Taler") }

    // MARK: Gruppen-Split

    public static var splitProgressFormat: String { OWSLocalizedString("TALER_SPLIT_PROGRESS_FORMAT", comment: "Group split progress. Embeds {{ accepted count }}, {{ total count }}.") }
    public static var splitNoteWithSelfFormat: String { OWSLocalizedString("TALER_SPLIT_NOTE_WITH_SELF_FORMAT", comment: "Group split note. Embeds {{ total }}, {{ currency }}, {{ people incl. sender }}, {{ links sent }}.") }
    public static var splitNoteWithoutSelfFormat: String { OWSLocalizedString("TALER_SPLIT_NOTE_WITHOUT_SELF_FORMAT", comment: "Group split note. Embeds {{ total }}, {{ currency }}, {{ people }}.") }
}
