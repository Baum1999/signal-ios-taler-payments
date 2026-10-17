//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import GRDB
@testable import SignalServiceKit

/// Faelle nach `TalerPaymentTableTest.kt` (signal-android): Upsert-Idempotenz,
/// Schutz lokaler Endzustaende, genau eine Statuszeile pro Endzustand,
/// Poll-Kandidaten mit TTL/Limit/Sortierung, Backoff.
final class TalerPaymentStoreTest: XCTestCase {

    private let db = InMemoryDB()
    private let uri = "taler://pay-push/exchange.example/AAA"

    private func preview(_ status: TalerOperationStatus) -> TalerPaymentPreview {
        TalerPaymentPreview(uriKind: .payPush, status: status, amount: "1.5", currency: "KUDOS", exchangeBaseUrl: "https://exchange.example/", summary: "Pizza", expirationTimestamp: nil)
    }

    func testUpsertDetectedIsIdempotentAndKeepsIsOwnPayment() {
        db.write { tx in
            XCTAssertTrue(TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: "t1", isOwnPayment: true, now: 1, tx: tx))
            XCTAssertFalse(TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: "t1", isOwnPayment: false, now: 2, tx: tx))
        }
        let record = db.read { TalerPaymentStore.record(forUri: uri, tx: $0) }
        XCTAssertEqual(record?.status, .unbekanntOffline)
        XCTAssertEqual(record?.isOwnPayment, true)
        XCTAssertEqual(record?.createdAt, 1)
    }

    func testApplyPreviewWritesFieldsAndResetsFailures() {
        db.write { tx in
            TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: "t1", isOwnPayment: false, now: 1, tx: tx)
            TalerPaymentStore.recordFailure(uri: uri, now: 2, tx: tx)
            let transition = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.offen), now: 3, tx: tx)
            XCTAssertEqual(transition, TalerPaymentTransition(previous: .unbekanntOffline, current: .offen, reachedTerminalStatus: false))
        }
        let record = db.read { TalerPaymentStore.record(forUri: uri, tx: $0) }
        XCTAssertEqual(record?.uriKind, .payPush)
        XCTAssertEqual(record?.amount, "1.5")
        XCTAssertEqual(record?.currency, "KUDOS")
        XCTAssertEqual(record?.summary, "Pizza")
        XCTAssertEqual(record?.consecutiveFailures, 0)
        XCTAssertEqual(record?.lastCheckedAt, 3)
    }

    func testTerminalStatusIsReportedOnlyOnce() {
        db.write { tx in
            TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: "t1", isOwnPayment: false, now: 1, tx: tx)
            _ = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.offen), now: 2, tx: tx)
            let first = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.angenommen), now: 3, tx: tx)
            let second = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.angenommen), now: 4, tx: tx)
            XCTAssertEqual(first?.reachedTerminalStatus, true)
            XCTAssertEqual(second?.reachedTerminalStatus, false)
        }
    }

    func testLocalTerminalStatusIsNeverOverwrittenByPreview() {
        db.write { tx in
            TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: "t1", isOwnPayment: false, now: 1, tx: tx)
            XCTAssertTrue(TalerPaymentStore.updateStatus(uri: uri, status: .lokalAbgelehnt, now: 2, tx: tx))
            let transition = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.angenommen), now: 3, tx: tx)
            XCTAssertEqual(transition?.current, .lokalAbgelehnt)
            XCTAssertFalse(TalerPaymentStore.updateStatus(uri: uri, status: .offen, now: 4, tx: tx))
            XCTAssertTrue(TalerPaymentStore.updateStatus(uri: uri, status: .lokalAbgelehnt, now: 5, tx: tx))
        }
        XCTAssertEqual(db.read { TalerPaymentStore.record(forUri: uri, tx: $0)?.status }, .lokalAbgelehnt)
    }

    func testApplyPreviewForUnknownUriReturnsNil() {
        db.write { tx in
            XCTAssertNil(TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.offen), now: 1, tx: tx))
        }
    }

    func testPollCandidatesRespectStatusTtlAndOrder() {
        let open1 = "taler://pay-push/e/OPEN1"
        let open2 = "taler://pay-push/e/OPEN2"
        let freshUnknown = "taler://pay-push/e/FRESH"
        let staleUnknown = "taler://pay-push/e/STALE"
        let accepted = "taler://pay-push/e/DONE"
        db.write { tx in
            for (u, created) in [(open1, 100), (open2, 100), (freshUnknown, 1_000), (staleUnknown, 10), (accepted, 100)] {
                TalerPaymentStore.upsertDetected(uri: u, threadUniqueId: "t", isOwnPayment: false, now: Int64(created), tx: tx)
            }
            _ = TalerPaymentStore.applyPreviewAndRecordTransition(uri: open1, preview: preview(.offen), now: 500, tx: tx)
            _ = TalerPaymentStore.applyPreviewAndRecordTransition(uri: open2, preview: preview(.offen), now: 300, tx: tx)
            _ = TalerPaymentStore.applyPreviewAndRecordTransition(uri: accepted, preview: preview(.angenommen), now: 300, tx: tx)
        }
        let candidates = db.read { TalerPaymentStore.pollCandidates(limit: 10, ttlCutoff: 50, tx: $0) }.map(\.uri)
        // OFFEN ohne TTL, UNBEKANNT nur innerhalb der TTL, am laengsten ungeprueft zuerst.
        XCTAssertEqual(candidates, [freshUnknown, open2, open1])
        let limited = db.read { TalerPaymentStore.pollCandidates(limit: 1, ttlCutoff: 50, tx: $0) }
        XCTAssertEqual(limited.count, 1)
    }

    func testBackoff() {
        XCTAssertEqual(TalerPaymentManager.backoffMillis(consecutiveFailures: 0), 0)
        XCTAssertEqual(TalerPaymentManager.backoffMillis(consecutiveFailures: 1), 40_000)
        XCTAssertEqual(TalerPaymentManager.backoffMillis(consecutiveFailures: 3), 160_000)
        XCTAssertEqual(TalerPaymentManager.backoffMillis(consecutiveFailures: 50), 20 * 60 * 1000)
    }

    func testRecordsForThread() {
        db.write { tx in
            TalerPaymentStore.upsertDetected(uri: "taler://pay-push/e/A", threadUniqueId: "t1", isOwnPayment: false, now: 2, tx: tx)
            TalerPaymentStore.upsertDetected(uri: "taler://pay-push/e/B", threadUniqueId: "t2", isOwnPayment: false, now: 1, tx: tx)
            TalerPaymentStore.upsertDetected(uri: "taler://pay-push/e/C", threadUniqueId: "t1", isOwnPayment: true, now: 1, tx: tx)
        }
        XCTAssertEqual(db.read { TalerPaymentStore.records(forThreadUniqueId: "t1", tx: $0) }.map(\.uri), ["taler://pay-push/e/C", "taler://pay-push/e/A"])
        XCTAssertEqual(db.read { TalerPaymentStore.allRecords(tx: $0) }.count, 3)
    }

    func testStructuredPayloadRoundTripsThroughProto() {
        let payload = TalerPaymentPayload(uris: ["taler://pay-push/e/A", "taler://pay-push/e/B"], version: 1, isGroupSplit: true, includeSelf: true, totalAmount: "30")
        let proto = TalerPaymentTracker.buildProto(from: payload)
        XCTAssertEqual(TalerPaymentTracker.structuredPayload(from: proto), payload)
        XCTAssertNil(TalerPaymentTracker.structuredPayload(from: nil))
    }

    // MARK: - statusChangedAt

    func testStatusChangeSetsStatusChangedAt() {
        db.write { tx in
            TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: "t1", isOwnPayment: false, now: 1, tx: tx)
            _ = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.offen), now: 2, tx: tx)
        }
        XCTAssertEqual(db.read { TalerPaymentStore.record(forUri: uri, tx: $0)?.statusChangedAt }, 2)
        db.write { tx in
            _ = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.angenommen), now: 3, tx: tx)
        }
        XCTAssertEqual(db.read { TalerPaymentStore.record(forUri: uri, tx: $0)?.statusChangedAt }, 3)
    }

    func testSameStatusKeepsStatusChangedAt() {
        db.write { tx in
            TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: "t1", isOwnPayment: false, now: 1, tx: tx)
            _ = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.offen), now: 2, tx: tx)
            _ = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.offen), now: 5, tx: tx)
            XCTAssertTrue(TalerPaymentStore.updateStatus(uri: uri, status: .offen, now: 6, tx: tx))
        }
        XCTAssertEqual(db.read { TalerPaymentStore.record(forUri: uri, tx: $0)?.statusChangedAt }, 2)
    }

    func testBlockedChangeKeepsStatusChangedAt() {
        db.write { tx in
            TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: "t1", isOwnPayment: false, now: 1, tx: tx)
            XCTAssertTrue(TalerPaymentStore.updateStatus(uri: uri, status: .lokalAbgelehnt, now: 2, tx: tx))
            XCTAssertFalse(TalerPaymentStore.updateStatus(uri: uri, status: .offen, now: 3, tx: tx))
            _ = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.angenommen), now: 4, tx: tx)
        }
        XCTAssertEqual(db.read { TalerPaymentStore.record(forUri: uri, tx: $0)?.statusChangedAt }, 2)
    }

    func testUpsertDetectedLeavesStatusChangedAtNil() {
        db.write { tx in
            _ = TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: "t1", isOwnPayment: false, now: 1, tx: tx)
        }
        XCTAssertNil(db.read { TalerPaymentStore.record(forUri: uri, tx: $0)?.statusChangedAt })
    }

    func testLatestActivityAtFallsBackToCreatedAt() {
        db.write { tx in
            _ = TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: "t1", isOwnPayment: false, now: 42, tx: tx)
        }
        XCTAssertEqual(TalerPaymentStore.latestActivityAt(db.read { TalerPaymentStore.record(forUri: uri, tx: $0)! }), 42)
        db.write { tx in
            _ = TalerPaymentStore.applyPreviewAndRecordTransition(uri: uri, preview: preview(.angenommen), now: 100, tx: tx)
        }
        XCTAssertEqual(TalerPaymentStore.latestActivityAt(db.read { TalerPaymentStore.record(forUri: uri, tx: $0)! }), 100)
    }

    /// Die InMemory-DB laeuft durch den normalen Migrator - die neue Migration
    /// muss die Spalte also liefern.
    func testMigrationAddsStatusChangedAtColumn() {
        let columns = db.read { tx -> [String] in
            (try? Row.fetchAll(tx.database, sql: "PRAGMA table_info(TalerPayment)"))?.compactMap { $0["name"] as String? } ?? []
        }
        XCTAssertTrue(columns.contains("statusChangedAt"))
    }
}
