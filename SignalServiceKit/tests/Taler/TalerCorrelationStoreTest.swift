//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Correlation-Store nach docs/cross-platform/link-protokoll.md 2.4:
/// register/take, single-use, TTL 15 Minuten mit injizierter Uhr
/// (Grenzfall genau TTL gilt wie auf Android noch als gueltig),
/// unbekannte IDs. Ohne Mocking-Framework, nur eine gestellte Uhr.
final class TalerCorrelationStoreTest: XCTestCase {

    private func makeStore(ttl: TimeInterval = 15 * 60) -> (store: TalerCorrelationStore, now: () -> Void) {
        var current = Date(timeIntervalSince1970: 1_000)
        let store = TalerCorrelationStore(ttl: ttl, now: { current })
        return (store, { current = current.addingTimeInterval(1) })
    }

    func testRegisterAndTakeReturnsEntry() {
        let (store, _) = makeStore()
        let entry = TalerCorrelationEntry(intent: .refund, threadUniqueId: "t1",
                                           uri: "taler://pay-push/ex/AAA",
                                           quoteInteractionUniqueId: "i42")
        let correlationId = store.register(entry)
        XCTAssertEqual(store.take(correlationId), entry)
    }

    func testRegisterReturnsLowercaseUUIDPerEntry() {
        let (store, _) = makeStore()
        let first = store.register(TalerCorrelationEntry(intent: .send, threadUniqueId: "t1"))
        let second = store.register(TalerCorrelationEntry(intent: .send, threadUniqueId: "t2"))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, first.lowercased())
        XCTAssertEqual(second, second.lowercased())
        // UUID-Format 8-4-4-4-12 Hex-Zeichen.
        let hex = CharacterSet(charactersIn: "0123456789abcdef-")
        XCTAssertTrue(first.unicodeScalars.allSatisfy { hex.contains($0) })
        XCTAssertEqual(first.split(separator: "-").map(\.count), [8, 4, 4, 4, 12])
    }

    func testTakeIsSingleUse() {
        let (store, _) = makeStore()
        let correlationId = store.register(
            TalerCorrelationEntry(intent: .acceptOrCancel, threadUniqueId: "t1",
                                  uri: "taler://pay-push/ex/AAA"))
        XCTAssertNotNil(store.take(correlationId))
        // Replay mit derselben ID findet nichts mehr.
        XCTAssertNil(store.take(correlationId))
    }

    func testTakeWithUnknownIdReturnsNil() {
        let (store, _) = makeStore()
        XCTAssertNil(store.take("unbekannt"))
        XCTAssertNil(store.take(""))
    }

    func testTakeWithinTtlReturnsEntry() {
        let (store, tick) = makeStore()
        let entry = TalerCorrelationEntry(intent: .abort, threadUniqueId: "t1",
                                          uris: ["taler://pay-push/ex/AAA", "taler://pay-push/ex/BBB"])
        let correlationId = store.register(entry)
        tick()
        tick()
        XCTAssertEqual(store.take(correlationId), entry)
    }

    func testTakeAtExactlyTtlStillReturnsEntry() {
        // Android-Vergleich (TalerCorrelationStore.kt): abgelaufen ist strikt
        // groesser als TTL; genau TTL gilt noch als gueltig.
        var current = Date(timeIntervalSince1970: 1_000)
        let store = TalerCorrelationStore(ttl: 15 * 60, now: { current })
        let entry = TalerCorrelationEntry(intent: .send, threadUniqueId: "t1")
        let correlationId = store.register(entry)
        current = current.addingTimeInterval(15 * 60)
        XCTAssertEqual(store.take(correlationId), entry)
    }

    func testExpiredEntryReturnsNilAndIsRemoved() {
        var current = Date(timeIntervalSince1970: 1_000)
        let store = TalerCorrelationStore(ttl: 15 * 60, now: { current })
        let correlationId = store.register(
            TalerCorrelationEntry(intent: .abort, threadUniqueId: "t1",
                                  uris: ["taler://pay-push/ex/AAA"]))
        current = current.addingTimeInterval(15 * 60 + 1)
        XCTAssertNil(store.take(correlationId))
        // take entfernt immer - auch abgelaufene Eintraege (single-use).
        XCTAssertNil(store.take(correlationId))
    }

    func testCustomTtlIsRespected() {
        var current = Date(timeIntervalSince1970: 1_000)
        let store = TalerCorrelationStore(ttl: 60, now: { current })
        let entry = TalerCorrelationEntry(intent: .send, threadUniqueId: "t1")
        let correlationId = store.register(entry)
        current = current.addingTimeInterval(61)
        XCTAssertNil(store.take(correlationId))
    }

    func testEntryKeepsAllFieldsForAbortIntent() {
        let (store, _) = makeStore()
        let uris = ["taler://pay-push/ex/AAA", "taler://pay-push/ex/BBB", "taler://pay-push/ex/CCC"]
        let entry = TalerCorrelationEntry(intent: .abort, threadUniqueId: "t7", uris: uris)
        let correlationId = store.register(entry)
        let taken = store.take(correlationId)
        XCTAssertEqual(taken?.intent, .abort)
        XCTAssertEqual(taken?.threadUniqueId, "t7")
        XCTAssertEqual(taken?.uris, uris)
        XCTAssertNil(taken?.uri)
        XCTAssertNil(taken?.quoteInteractionUniqueId)
    }
}
