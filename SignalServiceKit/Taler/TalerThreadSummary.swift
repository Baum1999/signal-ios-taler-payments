//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Saldo einer einzelnen Waehrung ueber alle abgeschlossenen Vorgaenge eines
/// Chats. Ein- und Ausgang bleiben getrennt, weil die Kopfzeile beide Seiten
/// zeigen koennen muss - `net` ist nur die Verrechnung daraus.
/// Spiegel von `CurrencyBalance` (signal-android).
public struct TalerCurrencyBalance: Equatable, Sendable {
    public let currency: String
    public let inflow: Decimal
    public let outflow: Decimal

    public var net: Decimal { inflow - outflow }
}

/// Verdichtung aller Taler-Vorgaenge eines Chats - die Zahlen, aus denen die
/// Kopfzeile des Taler-Tabs ihre drei Zeilen baut (Zielbild 6.1). Spiegel von
/// `TalerThreadAggregate` (signal-android), mit zwei bewussten Abweichungen:
/// `latest` nutzt `TalerPaymentStore.latestActivityAt` (juengster Statuswechsel
/// statt juengster Erkennung) und `exchanges` enthaelt die Exchange-Hosts in
/// Reihenfolge des ersten Auftretens.
public struct TalerThreadAggregate: Equatable, Sendable {
    public let total: Int
    /// OFFEN && !isOwnPayment - wartet auf eine Entscheidung des Nutzers.
    public let openForMe: Int
    /// OFFEN && isOwnPayment - wartet auf die Gegenseite.
    public let openForOther: Int
    /// UNBEKANNT_OFFLINE - Signal konnte den Vorgang nicht pruefen.
    public let unverifiable: Int
    /// max `TalerPaymentStore.latestActivityAt`; bei Gleichstand der Record mit
    /// groesserem `createdAt`, danach groesserer URI (Determinismus).
    public let latest: TalerPaymentRecord?
    /// Nur ANGENOMMEN; inflow = !isOwnPayment, outflow = isOwnPayment;
    /// sortiert nach |net| absteigend, dann Waehrung aufsteigend.
    public let balances: [TalerCurrencyBalance]
    /// Eindeutige Exchange-Hosts, Reihenfolge des ersten Auftretens.
    public let exchanges: [String]
    public let lastCheckedAt: Int64?

    public static func build(_ records: [TalerPaymentRecord]) -> TalerThreadAggregate {
        let open = records.filter { $0.status == .offen }
        return TalerThreadAggregate(
            total: records.count,
            // isOwnPayment allein entscheidet, wer am Zug ist - dieselbe Regel,
            // die TalerCardActionGate fuer die Chat-Karte nutzt.
            openForMe: open.lazy.filter { !$0.isOwnPayment }.count,
            openForOther: open.lazy.filter { $0.isOwnPayment }.count,
            unverifiable: records.lazy.filter { $0.status == .unbekanntOffline }.count,
            latest: latestOf(records),
            balances: balancesOf(records),
            exchanges: exchangesOf(records),
            lastCheckedAt: records.compactMap { $0.lastCheckedAt }.max(),
        )
    }

    /// Der zuletzt aktive Vorgang. Primaerschriterium ist
    /// `TalerPaymentStore.latestActivityAt` (Statuswechsel vor Erst-Erkennung),
    /// damit "Zuletzt" den letzten *Vorgang* nennt, nicht die letzte
    /// Zustellung. Die URI bricht den letzten Gleichstand, damit das Ergebnis
    /// nicht von der Zeilenreihenfolge aus der Datenbank abhaengt.
    private static func latestOf(_ records: [TalerPaymentRecord]) -> TalerPaymentRecord? {
        records.max { lhs, rhs in
            let lhsActivity = TalerPaymentStore.latestActivityAt(lhs)
            let rhsActivity = TalerPaymentStore.latestActivityAt(rhs)
            if lhsActivity != rhsActivity {
                return lhsActivity < rhsActivity
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.uri < rhs.uri
        }
    }

    /// Nur ANGENOMMEN zaehlt: offene, abgelehnte, abgebrochene und abgelaufene
    /// Vorgaenge haben nie Geld bewegt und gehoeren nicht in den Saldo.
    private static func balancesOf(_ records: [TalerPaymentRecord]) -> [TalerCurrencyBalance] {
        var inflow: [String: Decimal] = [:]
        var outflow: [String: Decimal] = [:]
        for record in records where record.status == .angenommen {
            guard let currency = record.currency, !currency.isEmpty else {
                continue
            }
            // Ungueltige Betraege tragen 0 bei, der Vorgang bleibt aber erfasst.
            let amount = parseTalerAmount(record.amount) ?? 0
            if record.isOwnPayment {
                outflow[currency, default: 0] += amount
            } else {
                inflow[currency, default: 0] += amount
            }
        }
        return Set(inflow.keys).union(outflow.keys).map { currency in
            TalerCurrencyBalance(currency: currency, inflow: inflow[currency] ?? 0, outflow: outflow[currency] ?? 0)
        }.sorted { lhs, rhs in
            let lhsNet = abs(lhs.net)
            let rhsNet = abs(rhs.net)
            if lhsNet != rhsNet {
                return lhsNet > rhsNet
            }
            return lhs.currency < rhs.currency
        }
    }

    /// Hosts der Exchange-Basis-URLs (Phishing-Schutz wie auf der Karte:
    /// nicht parsbare und nicht-ASCII-Hosts entfallen), in Reihenfolge des
    /// ersten Auftretens.
    private static func exchangesOf(_ records: [TalerPaymentRecord]) -> [String] {
        var hosts: [String] = []
        var seen = Set<String>()
        for record in records {
            guard let host = TalerCardModel.displayHost(record.exchangeBaseUrl), seen.insert(host).inserted else {
                continue
            }
            hosts.append(host)
        }
        return hosts
    }
}

/// Welche Aussage die Kopfzeile trifft. Bewusst ein eigener Typ statt eines
/// fertigen Strings: die Rangfolge ("Handlungsbedarf schlaegt Wissensluecke
/// schlaegt erledigt") ist die eigentliche Logik und bleibt so ohne UIKit
/// pruefbar - die Zuordnung zu Text, Icon und Farbe passiert erst in der
/// View. Spiegel von `TalerHeadline` (signal-android).
public enum TalerThreadHeadline: Equatable, Sendable {
    /// Keine Taler-Vorgaenge in diesem Chat.
    case empty
    /// Angegebene Anzahl eingehender Vorgaenge wartet auf eine Entscheidung des Nutzers.
    case waitingForMe(Int)
    /// Angegebene Anzahl eigener Vorgaenge wartet auf die Gegenseite.
    case waitingForOther(Int)
    /// Auf beiden Seiten offen - beide Zahlen, damit keine davon verschwindet.
    case waitingForBoth(forMe: Int, forOther: Int)
    /// Angegebene Anzahl Vorgaenge konnte nicht geprueft werden (Exchange nicht erreichbar).
    case unverifiable(Int)
    /// Nichts offen, nichts unklar - angegebene Anzahl Vorgaenge insgesamt.
    case allSettled(Int)

    /// Rangfolge exakt wie Android: was der Nutzer tun muss, schlaegt was
    /// Signal nicht weiss, schlaegt was erledigt ist - eine Wissensluecke darf
    /// nie als "alles abgeschlossen" durchgehen, und ein offener Vorgang nie
    /// hinter einer Wissensluecke verschwinden.
    public static func from(_ agg: TalerThreadAggregate) -> TalerThreadHeadline {
        if agg.openForMe > 0, agg.openForOther > 0 {
            return .waitingForBoth(forMe: agg.openForMe, forOther: agg.openForOther)
        }
        if agg.openForMe > 0 {
            return .waitingForMe(agg.openForMe)
        }
        if agg.openForOther > 0 {
            return .waitingForOther(agg.openForOther)
        }
        if agg.unverifiable > 0 {
            return .unverifiable(agg.unverifiable)
        }
        if agg.total > 0 {
            return .allSettled(agg.total)
        }
        return .empty
    }
}

/// Filter-Chips unter der Kopfzeile (Alle / Offen / Erhalten / Gesendet).
public enum TalerThreadFilter: CaseIterable, Sendable {
    case all
    case open
    case received
    case sent

    public func matches(_ r: TalerPaymentRecord) -> Bool {
        switch self {
        case .all: return true
        case .open: return r.status == .offen
        case .received: return !r.isOwnPayment
        case .sent: return r.isOwnPayment
        }
    }
}

/// Formatierung der Kopfzeile des Taler-Tabs (Zielbild 6.1), getrennt von der
/// Rechenschicht, damit genau die Faelle testbar bleiben, die die Kopfzeile
/// bestimmen. Reine Logik ohne UIKit; die Labels fuer erhalten/gesendet und
/// die relative Zeit haengt die UI an.
public enum TalerThreadSummaryFormat {

    /// Kontextzeile: "Saldo +12,50 KUDOS · exchange.demo.taler.net" - nur
    /// ANGENOMMENE-Vorgaenge aus `agg.balances` (bereits nach |net| absteigend
    /// sortiert), davon max. zwei Waehrungen, fuer den Rest verbleibt "+N", dazu der
    /// Exchange-Host bzw. "N Exchanges". Ist der Saldo insgesamt 0, entfaellt
    /// die Zeile komplett. `nil`, wenn es nichts anzuzeigen gibt.
    public static func contextLine(_ agg: TalerThreadAggregate, locale: Locale) -> String? {
        let nonZero = agg.balances.filter { $0.net != 0 }
        guard !nonZero.isEmpty else {
            return nil
        }
        var parts = nonZero.prefix(2).map { balance -> String in
            let sign = balance.net < 0 ? "-" : "+"
            return sign + formatAmount(abs(balance.net), locale: locale) + " " + balance.currency
        }
        if nonZero.count > 2 {
            parts.append("+\(nonZero.count - 2)")
        }
        if let exchangeText = exchangeText(agg.exchanges) {
            parts.append(exchangeText)
        }
        return parts.joined(separator: " · ")
    }

    /// Zeile "Letzter Vorgang": Betrag+Waehrung, erhalten/gesendet, Summary.
    /// Leere Teile entfallen; die relative Zeit haengt die UI an. Leer, wenn es
    /// keinen Vorgang gibt.
    public static func latestLineParts(
        _ agg: TalerThreadAggregate,
        receivedLabel: String,
        sentLabel: String,
        locale: Locale
    ) -> [String] {
        guard let latest = agg.latest else {
            return []
        }
        var parts: [String] = []
        if let amount = latest.amount,
           let currency = latest.currency,
           !currency.isEmpty,
           let parsed = parseTalerAmount(amount) {
            parts.append(formatAmount(parsed, locale: locale) + " " + currency)
        }
        parts.append(latest.isOwnPayment ? sentLabel : receivedLabel)
        if let summary = latest.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            parts.append(summary)
        }
        return parts
    }

    /// Host bzw. "N Exchanges" fuer die Kontextzeile. Kein Exchange bekannt:
    /// entfaellt.
    static func exchangeText(_ exchanges: [String]) -> String? {
        if let only = exchanges.first, exchanges.count == 1 {
            return only
        }
        if exchanges.count > 1 {
            return String(format: TalerStrings.exchangeCountFormat, exchanges.count)
        }
        return nil
    }

    /// Zwei Nachkommastellen, ohne Gruppierung, mit dem Dezimaltrenner des
    /// uebergebenen Locale - wie die Betraege auf den Karten.
    static func formatAmount(_ amount: Decimal, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }
}

/// Betraege im Record sind Strings mit Punkt als Dezimaltrenner (Taler-Format).
/// Alles andere - Komma, Vorzeichen, Muell - ist ungueltig und wird ignoriert.
func parseTalerAmount(_ amount: String?) -> Decimal? {
    guard let amount = amount?.trimmingCharacters(in: .whitespacesAndNewlines), !amount.isEmpty else {
        return nil
    }
    guard amount.range(of: "^[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil else {
        return nil
    }
    return Decimal(string: amount)
}
