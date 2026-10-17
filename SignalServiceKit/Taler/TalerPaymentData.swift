//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// JSON, das Taler beim Ruecksprung als `talerPaymentData` mitgibt (und das
/// aeltere Nachrichten als ganzen Body trugen). Spiegel von
/// `TalerPaymentData` (signal-android/taler-android, kotlinx.serialization).
///
/// Kotlin kodiert Felder mit Standardwert nicht mit (`encodeDefaults=false`),
/// deshalb sind hier alle Felder ausser `legacyText`/`uri` beim Dekodieren
/// optional.
public struct TalerPaymentData: Codable, Equatable, Sendable {
    public var legacyText: String
    public var version: Int
    public var includeSelf: Bool?
    public var totalAmount: String?
    public var uri: [String]

    public init(legacyText: String, version: Int = 1, includeSelf: Bool? = nil, totalAmount: String? = nil, uri: [String]) {
        self.legacyText = legacyText
        self.version = version
        self.includeSelf = includeSelf
        self.totalAmount = totalAmount
        self.uri = uri
    }

    private enum CodingKeys: String, CodingKey {
        case legacyText, version, includeSelf, totalAmount, uri
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        legacyText = try container.decode(String.self, forKey: .legacyText)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        includeSelf = try container.decodeIfPresent(Bool.self, forKey: .includeSelf)
        totalAmount = try container.decodeIfPresent(String.self, forKey: .totalAmount)
        uri = try container.decode([String].self, forKey: .uri)
    }

    public func encode(to encoder: Encoder) throws {
        // Wie kotlinx.serialization mit Standardkonfiguration: Standardwerte
        // und null weglassen, damit beide Seiten dasselbe JSON erzeugen.
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(legacyText, forKey: .legacyText)
        if version != 1 {
            try container.encode(version, forKey: .version)
        }
        try container.encodeIfPresent(includeSelf, forKey: .includeSelf)
        try container.encodeIfPresent(totalAmount, forKey: .totalAmount)
        try container.encode(uri, forKey: .uri)
    }

    /// Defensiv: `body` kann bei aelteren Nachrichten oder Fremd-Clients
    /// reiner Klartext sein.
    public static func parseOrNil(_ body: String) -> TalerPaymentData? {
        guard let data = body.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(TalerPaymentData.self, from: data)
    }

    public func jsonString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        guard let data = try? encoder.encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

/// Strukturierte Zahlungsdaten fuer `DataMessage.talerPayment` (Feld 9000).
/// Spiegel von `TalerPaymentPayload` (signal-android). Ohne `legacyText`:
/// der steht nur noch im Klartext-`body`.
public struct TalerPaymentPayload: Equatable, Sendable {
    public var uris: [String]
    public var version: Int
    public var isGroupSplit: Bool
    public var includeSelf: Bool?
    public var totalAmount: String?

    public init(uris: [String], version: Int = 1, isGroupSplit: Bool = false, includeSelf: Bool? = nil, totalAmount: String? = nil) {
        self.uris = uris
        self.version = version
        self.isGroupSplit = isGroupSplit
        self.includeSelf = includeSelf
        self.totalAmount = totalAmount
    }
}

public enum TalerMessageBody {

    /// Liefert die in `body` enthaltenen Taler-URIs. Versucht zuerst, `body`
    /// als `TalerPaymentData`-JSON zu lesen (autoritative, sauber dekodierte
    /// URI-Liste); nur wenn das scheitert oder die Liste leer ist, faellt es
    /// auf `TalerUriDetector.findUris` zurueck. Nicht direkt den Regex auf
    /// JSON anwenden: kompaktes JSON klebt Anfuehrungszeichen an die URI.
    public static func uris(in body: String) -> [String] {
        if let paymentData = TalerPaymentData.parseOrNil(body), !paymentData.uri.isEmpty {
            return paymentData.uri
        }
        return TalerUriDetector.findUris(body)
    }
}
