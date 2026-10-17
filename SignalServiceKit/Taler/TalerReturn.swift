//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Status-Variante des Ruecksprungs (link-protokoll.md 8): Ergebnis von
/// compose-send, compose-refund und Aktionslinks. Alles andere als
/// `ready`/`cancelled` gilt wie fehlend. Der Status ist angreiferkontrolliert
/// und wird nie angezeigt - er ist nur ein Trigger, Betraege und Zustaende
/// kommen aus der eigenen Verifikation (Contract/Exchange).
public enum TalerReturnStatus: String {
    case ready
    case cancelled
}

/// Ergebnis pro URI aus der result-Variante des Ruecksprungs
/// (link-protokoll.md 9, Gap A): `aborted` (echter Abbruch),
/// `already_claimed` (Empfaenger hat angenommen), `expired` (Purse abgelaufen),
/// `declined` (Nutzer hat die Sammel-Bestaetigung in Taler abgelehnt).
public enum TalerAbortOutcome: String {
    case aborted
    case alreadyClaimed = "already_claimed"
    case expired
    case declined
}

/// Ein uebernommenes Abbruch-Ergebnis: die URI und ihr Ausgang. Die URI ist
/// ein Inhaberpapier und wird nicht geloggt.
public struct TalerAbortResult: Equatable {
    public let uri: String
    public let outcome: TalerAbortOutcome

    public init(uri: String, outcome: TalerAbortOutcome) {
        self.uri = uri
        self.outcome = outcome
    }
}

/// Geparster Ruecksprung `TalerLinks.returnUri` (beide Varianten,
/// link-protokoll.md 8 und 9). Reine Parse-Logik: Sie entscheidet nicht,
/// was mit den Werten passiert - das macht der Ruecksprung-Handler anhand
/// des Intents aus dem Correlation-Store. Alle Werte sind
/// angreiferkontrolliert und werden nie ungeprueft angezeigt.
public struct TalerReturn: Equatable {
    public let correlationId: String
    /// nil, wenn `status` fehlt oder einen anderen Wert als ready/cancelled
    /// hat (dann werden auch talerUri/talerPaymentData nicht uebernommen).
    public let status: TalerReturnStatus?
    /// Nur uebernommen, wenn status == .ready (bei cancelled auch dann
    /// ignoriert, wenn der Parameter vorhanden ist).
    public let talerUri: String?
    /// Roher JSON-String (Struktur siehe datenmodell.md), nur bei
    /// status == .ready. Das Parsen des JSON macht der Handler, nicht hier.
    public let talerPaymentData: String?
    /// Alle gueltigen `result`-Eintraege der result-Variante, in der
    /// Reihenfolge des Ruecksprungs. Ungueltige Einzelwerte (kein `|`,
    /// unbekannter Ausgang) werden verworfen, nicht der ganze Ruecksprung.
    public let results: [TalerAbortResult]

    public init(correlationId: String,
                status: TalerReturnStatus?,
                talerUri: String?,
                talerPaymentData: String?,
                results: [TalerAbortResult]) {
        self.correlationId = correlationId
        self.status = status
        self.talerUri = talerUri
        self.talerPaymentData = talerPaymentData
        self.results = results
    }

    /// Parst einen eingehenden Ruecksprung. Rueckgabe nil, wenn:
    /// - Scheme nicht `TalerLinks.returnScheme` oder Host nicht `taler-return`
    ///   (Gross/Kleinschreibung egal, Schemes und Hosts sind laut RFC 3986
    ///   case-insensitiv), auch opake URLs ohne Host,
    /// - `correlationId` fehlt oder leer ist.
    /// Ein unbekannter/fehlender `status` verwirft nur das Status-Feld,
    /// nicht den Ruecksprung (bei ACCEPT_OR_CANCEL wird trotzdem gepollt).
    /// Nicht wiederholbare Parameter mehrfach: erster Wert gewinnt, wie
    /// `Uri.getQueryParameter` auf Android.
    public static func parse(_ url: URL) -> TalerReturn? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard components.scheme?.lowercased() == TalerLinks.returnScheme,
              components.host?.lowercased() == "taler-return" else {
            return nil
        }
        let items = components.queryItems ?? []

        func firstValue(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        // correlationId ist Pflicht und wird exakt, unveraendert
        // uebernommen (kein Trimmen: der Abgleich mit dem Store ist exakt,
        // ein verfaelschter Wert darf nie doch noch matchen). Leere ID ist
        // wie fehlende zu behandeln.
        guard let correlationId = firstValue("correlationId"), !correlationId.isEmpty else {
            return nil
        }

        let status = firstValue("status").flatMap(TalerReturnStatus.init(rawValue:))

        // talerUri/talerPaymentData nur bei ready - bei cancelled oder
        // unbekanntem Status werden vorhandene Werte ignoriert.
        let talerUri = status == .ready ? firstValue("talerUri") : nil
        let talerPaymentData = status == .ready ? firstValue("talerPaymentData") : nil

        var results: [TalerAbortResult] = []
        for item in items where item.name == "result" {
            guard let value = item.value,
                  let pipe = value.firstIndex(of: "|") else {
                continue
            }
            let uri = String(value[..<pipe])
            let outcome = String(value[value.index(after: pipe)...])
            guard let parsedOutcome = TalerAbortOutcome(rawValue: outcome) else {
                continue
            }
            results.append(TalerAbortResult(uri: uri, outcome: parsedOutcome))
        }

        return TalerReturn(correlationId: correlationId,
                           status: status,
                           talerUri: talerUri,
                           talerPaymentData: talerPaymentData,
                           results: results)
    }
}
