//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Kurze, sichere Zusammenfassung einer Taler-Zahlungsnachricht fuer die
/// Zitat-Anzeige - ersetzt die rohe(n) URI(s) (inkl. Claim-/Pay-Token) im
/// Zitat. Spiegel von `TalerQuoteSummary.kt` (signal-android): Betrag nur aus
/// dem Record (Regel 5), niemals aus dem Nachrichtentext; die URI erscheint
/// gar nicht (Regel 4). Bewusst ohne eigenen Wire-Format-Eintrag - der Hook
/// wird bei jedem Aufbau des Zitats frisch aufgerufen.
public enum TalerQuoteSummary {

    /// Reine Logik: Zusammenfassung oder `nil`, wenn `uris` leer ist (keine
    /// Taler-Zahlung - der Aufrufer zeigt den Body unveraendert).
    ///
    /// - Mehrere URIs (Gruppen-Split): Titel mit Anzahl der Links.
    /// - Einzel-URI mit Record-Betrag: "Taler-Zahlung · 5,00 KUDOS".
    /// - Einzel-URI ohne Record-Betrag: nur der Titel, ohne Betrag.
    public static func build(uris: [String], records: [TalerPaymentRecord?]) -> String? {
        guard !uris.isEmpty else {
            return nil
        }
        guard uris.count == 1 else {
            return String(format: TalerStrings.quoteGroupSummaryFormat, uris.count)
        }
        let record = records.first ?? nil
        guard let amount = record?.amount, !amount.isEmpty else {
            return TalerStrings.quoteTitle
        }
        let amountText = TalerCardModel.formatAmount(amount)
        let currency = record?.currency ?? ""
        let amountWithCurrency = "\(amountText) \(currency)".trimmingCharacters(in: .whitespaces)
        return "\(TalerStrings.quoteTitle) · \(amountWithCurrency)"
    }

    /// Bruecke fuer das Quote-Rendering: liest die URIs aus dem zitierten
    /// Body und die Records frisch aus der DB. `nil`, wenn der Body keine
    /// Taler-URI traegt.
    public static func build(body: String, transaction: DBReadTransaction) -> String? {
        let uris = TalerMessageBody.uris(in: body)
        guard !uris.isEmpty else {
            return nil
        }
        let records = uris.map { TalerPaymentStore.record(forUri: $0, tx: transaction) }
        return build(uris: uris, records: records)
    }
}
