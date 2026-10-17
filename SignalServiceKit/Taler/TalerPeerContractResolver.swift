//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Vorschau einer Peer-Zahlung, wie Signal sie selbst vom Exchange ermittelt.
/// Spiegel von `PaymentPreviewResult` (signal-android).
public struct TalerPaymentPreview: Equatable, Sendable {
    public var uriKind: TalerUriKind
    public var status: TalerOperationStatus
    public var amount: String?
    public var currency: String?
    public var exchangeBaseUrl: String?
    public var summary: String?
    /// Millisekunden seit 1970, `nil` = "never".
    public var expirationTimestamp: Int64?
}

public enum TalerContractResolution: Equatable, Sendable {
    case result(TalerPaymentPreview)
    /// Exchange nicht erreichbar - spaeter erneut versuchen.
    case offline
    case failed(TalerPaymentStatus)
}

/// Loest `pay-push`/`pay-pull`-URIs ohne die Taler-App auf: Contract-Chiffrat
/// beim Exchange abholen, lokal entschluesseln, Purse-Status abfragen. Beides
/// sind oeffentliche, unauthentifizierte Endpunkte; der Einmal-Schluessel
/// steckt in der URI selbst. Direkt vom Geraet, kein Proxy.
///
/// Portiert aus `TalerPeerContractResolver.kt` (signal-android).
public struct TalerPeerContractResolver: Sendable {

    public enum HTTPResult: Sendable {
        case ok(Data)
        /// 404/410 - der Exchange kennt die Ressource nicht (mehr).
        case notFound
    }

    /// Wirft bei Transportfehlern und unerwarteten Statuscodes (-> offline).
    public typealias Fetch = @Sendable (URL) async throws -> HTTPResult

    private let fetch: Fetch
    private let now: @Sendable () -> Date

    public init(fetch: @escaping Fetch = TalerPeerContractResolver.urlSessionFetch, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetch = fetch
        self.now = now
    }

    public struct ParsedPeerUri: Equatable, Sendable {
        public let kind: TalerUriKind
        public let exchangeBaseUrl: String
        public let contractPrivateKey: Data
    }

    public func resolve(_ uri: String) async -> TalerContractResolution {
        guard let parsed = Self.parse(uri) else {
            return .failed(.ungueltig)
        }
        do {
            return try await resolveParsed(parsed)
        } catch is ResolveError {
            Logger.warn("[Taler] Contract-Aufloesung fehlgeschlagen fuer \(TalerCorrelation.shortHash(uri))")
            return .failed(.ungueltig)
        } catch {
            Logger.warn("[Taler] Exchange nicht erreichbar fuer \(TalerCorrelation.shortHash(uri))")
            return .offline
        }
    }

    private enum ResolveError: Error {
        case malformed
    }

    private func resolveParsed(_ parsed: ParsedPeerUri) async throws -> TalerContractResolution {
        guard let contractPublicKey = try? TalerCrypto.eddsaPublicKey(seed: parsed.contractPrivateKey) else {
            throw ResolveError.malformed
        }
        let contractPub = Crockford.encode(contractPublicKey)
        guard let contractUrl = URL(string: "\(parsed.exchangeBaseUrl)contracts/\(contractPub)") else {
            throw ResolveError.malformed
        }
        guard case .ok(let contractBody) = try await fetch(contractUrl) else {
            return .failed(.abgelaufen)
        }
        guard let contract = try? JSONDecoder().decode(ContractResponse.self, from: contractBody) else {
            throw ResolveError.malformed
        }
        guard
            let pursePub = try? Crockford.decode(contract.pursePublicKey),
            let econtract = try? Crockford.decode(contract.encryptedContract),
            let direction = TalerContractCrypto.Direction(parsed.kind),
            let json = TalerContractCrypto.decrypt(
                encryptedContract: econtract,
                pursePublicKey: pursePub,
                contractPrivateKey: parsed.contractPrivateKey,
                direction: direction,
            ),
            let terms = try? JSONDecoder().decode(ContractTerms.self, from: Data(json.utf8))
        else {
            return .failed(.ungueltig)
        }

        let expiration = terms.purseExpiration?.milliseconds
        if let expiration, expiration <= Int64(now().timeIntervalSince1970 * 1000) {
            return .failed(.abgelaufen)
        }

        let statusPath = parsed.kind == .payPush ? "deposit" : "merge"
        guard let statusUrl = URL(string: "\(parsed.exchangeBaseUrl)purses/\(contract.pursePublicKey)/\(statusPath)") else {
            throw ResolveError.malformed
        }
        guard case .ok(let statusBody) = try await fetch(statusUrl) else {
            return .failed(.abgelaufen)
        }
        guard let purseStatus = try? JSONDecoder().decode(PurseStatusResponse.self, from: statusBody) else {
            throw ResolveError.malformed
        }

        // Push: der Empfaenger fuehrt zusammen (merge); Pull: der Schuldner
        // zahlt ein (deposit).
        let settledTimestamp = parsed.kind == .payPush ? purseStatus.mergeTimestamp : purseStatus.depositTimestamp
        let settled = settledTimestamp?.milliseconds != nil

        let (amount, currency) = Self.splitAmount(terms.amount)
        return .result(TalerPaymentPreview(
            uriKind: parsed.kind,
            status: settled ? .angenommen : .offen,
            amount: amount,
            currency: currency,
            exchangeBaseUrl: parsed.exchangeBaseUrl,
            summary: terms.summary,
            expirationTimestamp: expiration,
        ))
    }

    // MARK: - URI

    /// `taler://pay-push/<host>[/<path>...]/<key>` -> Exchange-Base-URL
    /// (immer `https`, ausser bei `taler+http`) und privater Schluessel.
    public static func parse(_ uri: String) -> ParsedPeerUri? {
        guard let kind = TalerUriParser.classify(uri), kind == .payPush || kind == .payPull else {
            return nil
        }
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutQuery = trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
        let scheme = withoutQuery.lowercased().hasPrefix("taler+http://") ? "http" : "https"
        guard let schemeEnd = withoutQuery.range(of: "://") else {
            return nil
        }
        let body = withoutQuery[schemeEnd.upperBound...]
        let segments = body.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard segments.count >= 3 else {
            return nil
        }
        let host = segments[1]
        let path = segments[2..<(segments.count - 1)]
        var baseUrl = "\(scheme)://\(host)/"
        for segment in path {
            baseUrl += "\(segment)/"
        }
        guard let key = try? Crockford.decodeFixed(segments[segments.count - 1], expectedLength: 32) else {
            return nil
        }
        return ParsedPeerUri(kind: kind, exchangeBaseUrl: baseUrl, contractPrivateKey: key)
    }

    static func splitAmount(_ amount: String) -> (amount: String?, currency: String?) {
        guard let separator = amount.firstIndex(of: ":"), separator > amount.startIndex else {
            return (amount, nil)
        }
        return (String(amount[amount.index(after: separator)...]), String(amount[..<separator]))
    }

    // MARK: - Netz

    public static let urlSessionFetch: Fetch = { url in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        switch http.statusCode {
        case 200..<300:
            return .ok(data)
        case 404, 410:
            return .notFound
        default:
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - JSON

    private struct ContractResponse: Decodable {
        let pursePublicKey: String
        let encryptedContract: String

        enum CodingKeys: String, CodingKey {
            case pursePublicKey = "purse_pub"
            case encryptedContract = "econtract"
        }
    }

    private struct PurseStatusResponse: Decodable {
        let depositTimestamp: TalerTimestamp?
        let mergeTimestamp: TalerTimestamp?

        enum CodingKeys: String, CodingKey {
            case depositTimestamp = "deposit_timestamp"
            case mergeTimestamp = "merge_timestamp"
        }
    }

    struct ContractTerms: Decodable {
        let amount: String
        let summary: String
        let purseExpiration: TalerTimestamp?

        enum CodingKeys: String, CodingKey {
            case amount
            case summary
            case purseExpiration = "purse_expiration"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            amount = try container.decode(String.self, forKey: .amount)
            summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
            purseExpiration = try container.decodeIfPresent(TalerTimestamp.self, forKey: .purseExpiration)
        }
    }

    /// `t_s` ist entweder eine Zahl oder der String "never".
    struct TalerTimestamp: Decodable {
        let seconds: Int64?

        enum CodingKeys: String, CodingKey {
            case seconds = "t_s"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try? container.decodeIfPresent(Int64.self, forKey: .seconds) {
                seconds = value
            } else if let value = try? container.decodeIfPresent(Double.self, forKey: .seconds) {
                seconds = Int64(value)
            } else {
                seconds = nil
            }
        }

        var milliseconds: Int64? { seconds.map { $0 * 1000 } }
    }
}
