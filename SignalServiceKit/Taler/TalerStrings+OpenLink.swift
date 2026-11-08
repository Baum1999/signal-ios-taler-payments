//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Strings fuer den Link `taler-open` (Taler oeffnet die Zahlungsnachricht,
/// link-protokoll.md 12).
extension TalerStrings {

    public static var openPaymentNotFoundTitle: String {
        TalerLocalizedString("TALER_OPEN_PAYMENT_NOT_FOUND_TITLE", comment: "Title of the alert when GNU Taler asks Signal to show the message of a payment that Signal does not know")
    }

    public static var openPaymentNotFoundMessage: String {
        TalerLocalizedString("TALER_OPEN_PAYMENT_NOT_FOUND_MESSAGE", comment: "Message of the alert when GNU Taler asks Signal to show the message of a payment that Signal does not know")
    }
}
