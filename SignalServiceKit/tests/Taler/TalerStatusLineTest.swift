//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// `TalerStatusLine` (E7, Variante A): Verschwinde-Frist nach
/// Thread-Konfiguration, genau eine Zeile pro erstmals erreichtem
/// Endzustand, Texte je Status.
final class TalerStatusLineTest: SSKBaseTest {

    private let uri = "taler://pay-push/exchange.example/AAA"

    private func preview(_ status: TalerOperationStatus) -> TalerPaymentPreview {
        TalerPaymentPreview(
            uriKind: .payPush,
            status: status,
            amount: "1.5",
            currency: "KUDOS",
            exchangeBaseUrl: "https://exchange.example/",
            summary: "Pizza",
            expirationTimestamp: nil
        )
    }

    private func statusLines(threadUniqueId: String) -> [TSInfoMessage] {
        var result: [TSInfoMessage] = []
        read { tx in
            result = TSInteraction.anyFetchAll(transaction: tx).compactMap { interaction in
                guard
                    let infoMessage = interaction as? TSInfoMessage,
                    infoMessage.messageType == .talerPaymentUpdate,
                    infoMessage.uniqueThreadId == threadUniqueId
                else {
                    return nil
                }
                return infoMessage
            }
        }
        return result
    }

    // MARK: - insert

    func testInsertWithoutTimerConfiguration() {
        let thread = write { tx in
            ContactThreadFactory().create(transaction: tx)
        }
        write { tx in
            TalerStatusLine.insert(status: .lokalAbgelehnt, threadUniqueId: thread.uniqueId, tx: tx)
        }
        let lines = statusLines(threadUniqueId: thread.uniqueId)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.expiresInSeconds, 0)
        XCTAssertNil(lines.first?.expireTimerVersion)
        // Rein informativ: die Zeile ist direkt als gelesen markiert.
        XCTAssertEqual(lines.first?.wasRead, true)
    }

    func testInsertUsesThreadDisappearConfiguration() {
        let thread = write { tx in
            ContactThreadFactory().create(transaction: tx)
        }
        write { tx in
            DependenciesBridge.shared.disappearingMessagesConfigurationStore.set(
                token: VersionedDisappearingMessageToken(isEnabled: true, durationSeconds: 30, version: 7),
                for: .thread(thread),
                tx: tx
            )
        }
        write { tx in
            TalerStatusLine.insert(status: .angenommen, threadUniqueId: thread.uniqueId, tx: tx)
        }
        let lines = statusLines(threadUniqueId: thread.uniqueId)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.expiresInSeconds, 30)
        XCTAssertEqual(lines.first?.expireTimerVersion?.uint32Value, 7)
    }

    func testInsertIsNoOpForStatusWithoutLine() {
        let thread = write { tx in
            ContactThreadFactory().create(transaction: tx)
        }
        write { tx in
            TalerStatusLine.insert(status: .offen, threadUniqueId: thread.uniqueId, tx: tx)
            TalerStatusLine.insert(status: .ungueltig, threadUniqueId: thread.uniqueId, tx: tx)
            // Unbekannter Thread: stiller Abbruch.
            TalerStatusLine.insert(status: .angenommen, threadUniqueId: "gibt-es-nicht", tx: tx)
        }
        XCTAssertEqual(statusLines(threadUniqueId: thread.uniqueId), [])
    }

    // MARK: - Insert-Hook des Managers (Deduplizierung)

    func testTerminalTransitionInsertsExactlyOneStatusLine() async {
        let thread = write { tx in
            ContactThreadFactory().create(transaction: tx)
        }
        write { tx in
            TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: thread.uniqueId, isOwnPayment: false, now: 1, tx: tx)
        }
        let manager = TalerPaymentManager()
        await manager.apply(.result(preview(.offen)), uri: uri)
        await manager.apply(.result(preview(.angenommen)), uri: uri)
        await manager.apply(.result(preview(.angenommen)), uri: uri)
        let lines = statusLines(threadUniqueId: thread.uniqueId)
        XCTAssertEqual(lines.count, 1)
        // Der Rohwert steht im userInfo, nicht der lokalisierte Text.
        let raw: String? = lines.first?.infoMessageValue(forKey: .talerPaymentStatus)
        XCTAssertEqual(raw, TalerPaymentStatus.angenommen.rawValue)
    }

    func testFailedResolutionToExpiredInsertsStatusLine() async {
        let thread = write { tx in
            ContactThreadFactory().create(transaction: tx)
        }
        write { tx in
            TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: thread.uniqueId, isOwnPayment: false, now: 1, tx: tx)
            TalerPaymentStore.updateStatus(uri: uri, status: .offen, now: 2, tx: tx)
        }
        let manager = TalerPaymentManager()
        await manager.apply(.failed(.abgelaufen), uri: uri)
        await manager.apply(.failed(.abgelaufen), uri: uri)
        XCTAssertEqual(statusLines(threadUniqueId: thread.uniqueId).count, 1)
    }

    // MARK: - text

    func testTextForStatus() {
        for status in [TalerPaymentStatus.angenommen, .abgelaufen, .lokalAbgelehnt, .lokalAbgebrochen] {
            XCTAssertNotNil(TalerStatusLine.text(for: status))
        }
        for status in [TalerPaymentStatus.offen, .unbekanntOffline, .ungueltig] {
            XCTAssertNil(TalerStatusLine.text(for: status))
        }
    }

    func testTextForMessageRoundTripsStatus() {
        let thread = write { tx in
            ContactThreadFactory().create(transaction: tx)
        }
        write { tx in
            TalerStatusLine.insert(status: .lokalAbgebrochen, threadUniqueId: thread.uniqueId, tx: tx)
        }
        let line = statusLines(threadUniqueId: thread.uniqueId).first
        XCTAssertNotNil(line)
        XCTAssertEqual(TalerStatusLine.text(for: line!), TalerStatusLine.text(for: .lokalAbgebrochen))
    }
}
