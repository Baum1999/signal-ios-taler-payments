//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Baut die Links Signal -> Taler (docs/cross-platform/link-protokoll.md).
/// Reine Logik ohne UIKit: das Oeffnen des Links (`UIApplication.open`)
/// macht die UI, nicht dieser Typ. Parameternamen sind Protokoll und werden
/// nie umbenannt. Alle Werte werden streng prozent-kodiert (nur die
/// RFC-3986-unreserved Zeichen bleiben roh), weil sie selbst URIs oder JSON
/// sind - ein rohes `+ & = / : ? #` wuerde die Query zerlegen.
public enum TalerLinks {

    /// Scheme of `returnUri`. Signal already registers `sgnl` as URL type;
    /// builds paired with a different wallet change it here and register
    /// the scheme in Signal-Info.plist.
    public static let returnScheme = "sgnl"

    /// Ruecksprungziel, das Signal jedem Link als `returnUri` mitgibt.
    /// Exakt dieser String, ohne Query, Pfad oder Fragment.
    public static let returnUri = "\(returnScheme)://taler-return"

    /// Scheme aller Links, die Signal an Taler schickt. iOS nutzt es auch
    /// fuer Aktionslinks (`talerlink://pay-push/...`), weil iOS kein
    /// `setPackage` kennt (link-protokoll.md 2.1).
    public static let linkScheme = "talerlink"

    /// Anfangsstellung des Richtungs-Toggles im Taler-Compose-Screen.
    /// Rohwerte sind Teil des Protokolls (TalerUriKind), nicht umbenennen.
    public enum Direction: String {
        case payPush = "PAY_PUSH"
        case payPull = "PAY_PULL"
    }

    /// Zeichen, die in einem Query-Wert roh bleiben duerfen (RFC 3986
    /// unreserved). Alles andere wird als %XX kodiert (Hex in Grossbuchstaben,
    /// so liefert es Foundation; Leerzeichen als %20, nie als +).
    private static let queryValueAllowed: CharacterSet =
        // Bewusst nur ASCII: `CharacterSet.alphanumerics` enthaelt auch
        // Unicode-Buchstaben (ue, ...), die dann roh blieben.
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? ""
    }

    /// Setzt einen compose-Link aus schon streng kodierten Werten zusammen.
    /// `percentEncodedQueryItems` (nicht `queryItems`) sorgt dafuer, dass
    /// Foundation die Werte nicht ein zweites, weniger strenge Mal kodiert.
    private static func composeLink(host: String, items: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = linkScheme
        components.host = host
        components.percentEncodedQueryItems = items
        // Scheme und Host sind Konstanten, alle Werte bestehen nach der
        // strengen Kodierung nur noch aus unreserved Zeichen und %XX - ein
        // Fehlschlag ist hier konstruktionsbedingt unmoeglich. Ein stiller
        // Fallback (Link ohne Query) waere gefaehrlicher als der Absturz,
        // weil Taler ihn kommentarlos verwerfen wuerde.
        guard let url = components.url else {
            fatalError("TalerLinks: compose-Link konnte nicht gebaut werden")
        }
        return url
    }

    /// Anzeigename dieser App im `senderAppName`-Parameter von compose-send
    /// (link-protokoll.md 3) - fester Konstantenwert, keine Nutzereingabe.
    /// Dient Taler nur als Vorschlagstext fuers Zweck-Feld.
    public static let senderAppName = "Signal"

    /// `talerlink://compose-send` - Signal bittet Taler, eine Zahlung zu
    /// erstellen. Betrag und Zweck fragt Taler selbst ab; Signal gibt nur
    /// unbedenkliche Kontextinfo mit. Sender-Reihenfolge (link-protokoll.md 3):
    /// `recipientHint`, `senderAppName`, `isGroup`, `direction`,
    /// `disappearingMessagesSeconds`, `correlationId`, `returnUri`, dann
    /// `memberCount` nur bei Gruppe (wie Android, TalerSendActions.kt).
    public static func composeSend(recipientHint: String, isGroup: Bool, memberCount: Int?,
                                   disappearingMessagesSeconds: UInt32, direction: Direction,
                                   correlationId: String) -> URL {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "recipientHint", value: encode(recipientHint)),
            URLQueryItem(name: "senderAppName", value: encode(senderAppName)),
            URLQueryItem(name: "isGroup", value: isGroup ? "true" : "false"),
            URLQueryItem(name: "direction", value: direction.rawValue),
            URLQueryItem(name: "disappearingMessagesSeconds", value: String(disappearingMessagesSeconds)),
            URLQueryItem(name: "correlationId", value: encode(correlationId)),
            URLQueryItem(name: "returnUri", value: encode(returnUri)),
        ]
        if isGroup, let memberCount {
            items.append(URLQueryItem(name: "memberCount", value: String(memberCount)))
        }
        return composeLink(host: "compose-send", items: items)
    }

    /// `talerlink://compose-refund` - Signal bittet Taler, eine Rueckerstattung
    /// zu erstellen. `originalUri` ist die einzige Angabe; Taler loest daraus
    /// selbst Betrag und Zweck auf. Reihenfolge (link-protokoll.md 4):
    /// `originalUri`, `correlationId`, `returnUri`.
    public static func composeRefund(originalUri: String, correlationId: String) -> URL {
        composeLink(host: "compose-refund", items: [
            URLQueryItem(name: "originalUri", value: encode(originalUri)),
            URLQueryItem(name: "correlationId", value: encode(correlationId)),
            URLQueryItem(name: "returnUri", value: encode(returnUri)),
        ])
    }

    /// `talerlink://compose-abort` (Gap A, link-protokoll.md 5) - Signal bittet
    /// Taler, eigene offene Zahlungen tatsaechlich abzubrechen. Eine URI pro
    /// wiederholtem `uri`-Parameter (keine Komma-Trennung, URIs koennen
    /// Kommas enthalten), Reihenfolge bleibt erhalten; danach `correlationId`,
    /// `returnUri`.
    public static func composeAbort(uris: [String], correlationId: String) -> URL {
        var items = uris.map { URLQueryItem(name: "uri", value: encode($0)) }
        items.append(URLQueryItem(name: "correlationId", value: encode(correlationId)))
        items.append(URLQueryItem(name: "returnUri", value: encode(returnUri)))
        return composeLink(host: "compose-abort", items: items)
    }

    /// Aktionslink (link-protokoll.md 6): die normale Zahlungs-URI mit Scheme
    /// `taler` (Gross/Kleinschreibung egal) wird zu `talerlink://...`, der Rest
    /// der URI bleibt byte-identisch; `correlationId` und `returnUri` werden
    /// angehaengt (per `&`, falls die URI bereits eine Query traegt, sonst per
    /// `?` - wie Android, TalerAcceptRejectActions.kt).
    ///
    /// Nur `taler://pay-push/...` und `taler://pay-pull/...` (jeweils auch in
    /// Grossbuchstaben). Andere Arten (`ext+taler://`, `taler+http://`, `pay`,
    /// `withdraw`, `refund`) und unparsable Eingaben liefern nil - fuer sie
    /// schickt Signal keinen Aktionslink.
    public static func actionLink(forTalerUri uri: String, correlationId: String) -> URL? {
        let normalized = uri.lowercased()
        guard normalized.hasPrefix("taler://pay-push/") || normalized.hasPrefix("taler://pay-pull/") else {
            return nil
        }
        let rest = uri.dropFirst("taler://".count)
        let separator = rest.contains("?") ? "&" : "?"
        let query = "correlationId=\(encode(correlationId))&returnUri=\(encode(returnUri))"
        return URL(string: "\(linkScheme)://\(rest)\(separator)\(query)")
    }
}
