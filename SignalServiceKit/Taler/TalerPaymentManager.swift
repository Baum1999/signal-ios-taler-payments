//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public enum TalerRefreshTrigger: String, Sendable {
    /// Regulaeres Polling.
    case routine
    /// Sofort-Refresh nach Ruecksprung aus Taler.
    case returned
    /// Manueller Trigger (Menue "Aktualisieren", erkannte Bestaetigung).
    case manual
}

/// Reaktionen auf Statuswechsel, die ausserhalb von SignalServiceKit
/// umgesetzt werden (lokale Statuszeile, 1:1-Bestaetigungsnachricht). Von der
/// App in `TalerPaymentManager.shared.delegate` gesetzt.
public protocol TalerPaymentManagerDelegate: AnyObject {
    /// Wird in der Schreibtransaktion des Statuswechsels aufgerufen.
    func talerPayment(_ record: TalerPaymentRecord, didTransition transition: TalerPaymentTransition, tx: DBWriteTransaction)
}

/// Polling und Abruf fuer Taler-Vorgaenge. Spiegel von
/// `TalerPollingCoordinator` + `TalerUriRefreshJob` (signal-android):
///
///  - fester 20-s-Takt nur im Vordergrund, plus sofortiger Lauf beim
///    Aktivwerden der App (kein dauerhaftes Hintergrund-Polling),
///  - Obergrenze 200 Kandidaten pro Zyklus, TTL 24 h fuer UNBEKANNT_OFFLINE,
///  - exponentieller Backoff pro URI nach Transportfehlern (max. 20 min),
///  - Fast-Poll (2 s fuer 2 min) nach einem Ruecksprung aus Taler,
///  - hoechstens ein laufender Abruf pro (URI, Trigger) - ersetzt die
///    Job-Queue-Deduplizierung.
///
/// Laeuft nur in der Haupt-App; in NSE/Share-Extension werden Vorgaenge
/// lediglich angelegt.
public final class TalerPaymentManager: @unchecked Sendable {

    public static let shared = TalerPaymentManager()

    public weak var delegate: TalerPaymentManagerDelegate?

    static let pollIntervalSeconds: TimeInterval = 20
    static let pollCap = 200
    static let ttlMillis: Int64 = 24 * 60 * 60 * 1000
    static let maxBackoffMillis: Int64 = 20 * 60 * 1000
    static let fastPollIntervalSeconds: TimeInterval = 2
    static let fastPollDurationSeconds: TimeInterval = 120

    private let lock = NSLock()
    private var started = false
    private var inFlight = Set<String>()
    private var fastPollUntil: [String: Date] = [:]
    private var pollTask: Task<Void, Never>?
    private var fastPollTask: Task<Void, Never>?
    private var isForeground = false

    private let resolver: TalerPeerContractResolver

    init(resolver: TalerPeerContractResolver = TalerPeerContractResolver()) {
        self.resolver = resolver
    }

    private var isEnabled: Bool {
        CurrentAppContext().isMainApp
    }

    // MARK: - Lebenszyklus

    /// Lazy gestartet beim ersten Kontakt mit einer Taler-URI (Erkennen oder
    /// Rendern einer Karte), nicht beim App-Start.
    public func ensureStarted() {
        guard isEnabled else {
            return
        }
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        DispatchQueue.main.async { [self] in
            NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: .OWSApplicationDidBecomeActive, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: .OWSApplicationWillResignActive, object: nil)
            if CurrentAppContext().isMainAppAndActive {
                didBecomeActive()
            }
        }
    }

    @objc
    private func didBecomeActive() {
        lock.lock()
        isForeground = true
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshPending()
                try? await Task.sleep(nanoseconds: UInt64(Self.pollIntervalSeconds * 1_000_000_000))
            }
        }
        lock.unlock()
        startFastPollIfNeeded()
    }

    @objc
    private func willResignActive() {
        lock.lock()
        isForeground = false
        pollTask?.cancel()
        pollTask = nil
        fastPollTask?.cancel()
        fastPollTask = nil
        fastPollUntil.removeAll()
        lock.unlock()
    }

    // MARK: - Ausloeser

    func didDetectNewUris(_ uris: [String]) {
        guard isEnabled else {
            return
        }
        ensureStarted()
        for uri in uris {
            requestRefresh(uri: uri, trigger: .routine)
        }
    }

    public func requestRefresh(uri: String, trigger: TalerRefreshTrigger) {
        guard isEnabled else {
            return
        }
        Task { await self.refresh(uri: uri, trigger: trigger) }
    }

    /// Nach einem Ruecksprung aus Taler: sofort und dann 2 min lang alle 2 s.
    public func requestFastPoll(uri: String) {
        guard isEnabled else {
            return
        }
        ensureStarted()
        lock.lock()
        fastPollUntil[uri] = Date().addingTimeInterval(Self.fastPollDurationSeconds)
        lock.unlock()
        requestRefresh(uri: uri, trigger: .returned)
        startFastPollIfNeeded()
    }

    private func startFastPollIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard isForeground, fastPollTask == nil, !fastPollUntil.isEmpty else {
            return
        }
        fastPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.fastPollIntervalSeconds * 1_000_000_000))
                guard let self, let uris = self.activeFastPollUris() else {
                    return
                }
                for uri in uris {
                    await self.refresh(uri: uri, trigger: .returned)
                }
            }
        }
    }

    /// `nil`, wenn keine URI mehr im Fast-Poll ist (Task beendet sich).
    private func activeFastPollUris() -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        fastPollUntil = fastPollUntil.filter { $0.value > now }
        if fastPollUntil.isEmpty {
            fastPollTask = nil
            return nil
        }
        return Array(fastPollUntil.keys)
    }

    // MARK: - Polling

    private func refreshPending() async {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let candidates = SSKEnvironment.shared.databaseStorageRef.read { tx in
            TalerPaymentStore.pollCandidates(limit: Self.pollCap, ttlCutoff: now - Self.ttlMillis, tx: tx)
        }
        for candidate in candidates {
            let dueAt = (candidate.lastCheckedAt ?? 0) + Self.backoffMillis(consecutiveFailures: candidate.consecutiveFailures)
            if now >= dueAt {
                await refresh(uri: candidate.uri, trigger: .routine)
            }
        }
    }

    /// 0 Fehlschlaege: kein Backoff. Danach Verdopplung pro Fehlschlag,
    /// gedeckelt bei 20 min (Exponent zusaetzlich gegen Ueberlauf begrenzt).
    static func backoffMillis(consecutiveFailures: Int) -> Int64 {
        guard consecutiveFailures > 0 else {
            return 0
        }
        let exponent = min(consecutiveFailures, 20)
        return min(Int64(pollIntervalSeconds * 1000) << exponent, maxBackoffMillis)
    }

    // MARK: - Abruf

    public func refresh(uri: String, trigger: TalerRefreshTrigger) async {
        let key = "\(trigger.rawValue)|\(uri)"
        let acquired = lock.withLock { inFlight.insert(key).inserted }
        guard acquired else {
            return
        }
        defer {
            lock.withLock { _ = inFlight.remove(key) }
        }

        let resolution = await resolver.resolve(uri)
        await apply(resolution, uri: uri)
    }

    func apply(_ resolution: TalerContractResolution, uri: String) async {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            switch resolution {
            case .result(let preview):
                if
                    let transition = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview, now: now, tx: tx),
                    transition.previous != transition.current,
                    let record = TalerPaymentStore.record(forUri: uri, tx: tx)
                {
                    // Lokale Statuszeile genau beim ersten Erreichen eines
                    // Endzustands (Deduplizierung im Store, dieselbe
                    // Schreibtransaktion).
                    if transition.reachedTerminalStatus {
                        TalerStatusLine.insert(status: transition.current, threadUniqueId: record.threadUniqueId, tx: tx)
                    }
                    self.delegate?.talerPayment(record, didTransition: transition, tx: tx)
                }
            case .failed(let status):
                if
                    let previous = TalerPaymentStore.record(forUri: uri, tx: tx)?.status,
                    TalerPaymentStore.updateStatus(uri: uri, status: status, now: now, tx: tx),
                    previous != status,
                    let record = TalerPaymentStore.record(forUri: uri, tx: tx)
                {
                    let transition = TalerPaymentTransition(
                        previous: previous,
                        current: status,
                        reachedTerminalStatus: TalerPaymentStore.statusLineTerminalStatuses.contains(status),
                    )
                    if transition.reachedTerminalStatus {
                        TalerStatusLine.insert(status: transition.current, threadUniqueId: record.threadUniqueId, tx: tx)
                    }
                    self.delegate?.talerPayment(record, didTransition: transition, tx: tx)
                }
            case .offline:
                TalerPaymentStore.recordFailure(uri: uri, now: now, tx: tx)
            }
            Self.touchInteractions(forUri: uri, tx: tx)
        }
    }

    /// Rendert alle Nachrichten neu, die `uri` tragen (Karte) oder sich auf
    /// sie beziehen (Bestaetigungsnachricht).
    public static func touchInteractions(forUri uri: String, tx: DBWriteTransaction) {
        let rowIds = TalerPaymentStore.interactionIds(forUri: uri, tx: tx) + TalerPaymentStore.confirmationInteractionIds(forUri: uri, tx: tx)
        guard !rowIds.isEmpty else {
            return
        }
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        for interaction in interactions(rowIds: rowIds, tx: tx) {
            databaseStorage.touch(interaction: interaction, shouldReindex: false, tx: tx)
        }
    }

    public static func interactions(rowIds: [Int64], tx: DBReadTransaction) -> [TSInteraction] {
        guard !rowIds.isEmpty else {
            return []
        }
        let placeholders = rowIds.map { _ in "?" }.joined(separator: ",")
        let cursor = TSInteraction.grdbFetchCursor(
            sql: "SELECT * FROM \(InteractionRecord.databaseTableName) WHERE \(interactionColumn: .id) IN (\(placeholders))",
            arguments: StatementArguments(rowIds),
            transaction: tx,
        )
        var result: [TSInteraction] = []
        while let interaction = try? cursor.next() {
            result.append(interaction)
        }
        return result
    }
}
