//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// `TalerLocalDelete.cancelOpenOwnPayments`: nur eigene, noch offene
/// Anteile werden abgebrochen; fremde und bereits entschiedene Zahlungen
/// bleiben unberuehrt (Spiegel von
/// `cancelCancelablePaymentsForDeletedMessages`, signal-android).
final class TalerLocalDeleteTest: SSKBaseTest {

    private let ownOpenUri = "taler://pay-push/exchange.example/OWN-OPEN"
    private let foreignOpenUri = "taler://pay-push/exchange.example/FOREIGN-OPEN"
    private let ownAcceptedUri = "taler://pay-push/exchange.example/OWN-DONE"

    private func makeThread() -> TSContactThread {
        write { tx in
            ContactThreadFactory().create(transaction: tx)
        }
    }

    /// Legt die drei Vorgaenge an: eigener offener, fremder offener,
    /// eigener bereits angenommener pay-push.
    private func seedPayments(thread: TSContactThread) {
        write { tx in
            TalerPaymentStore.upsertDetected(uri: ownOpenUri, threadUniqueId: thread.uniqueId, isOwnPayment: true, now: 1, tx: tx)
            TalerPaymentStore.upsertDetected(uri: foreignOpenUri, threadUniqueId: thread.uniqueId, isOwnPayment: false, now: 1, tx: tx)
            TalerPaymentStore.upsertDetected(uri: ownAcceptedUri, threadUniqueId: thread.uniqueId, isOwnPayment: true, now: 1, tx: tx)
            // upsertDetected setzt keine uriKind; die Vorschau setzt uriKind
            // (pay-push) und Status, wie im echten Ablauf.
            let seeds: [(String, TalerOperationStatus)] = [(ownOpenUri, .offen), (foreignOpenUri, .offen), (ownAcceptedUri, .angenommen)]
            for (uri, status) in seeds {
                _ = TalerPaymentStore.applyPreviewAndRecordTransition(
                    uri: uri,
                    preview: TalerPaymentPreview(
                        uriKind: .payPush,
                        status: status,
                        amount: "1.5",
                        currency: "KUDOS",
                        exchangeBaseUrl: "https://exchange.example/",
                        summary: nil,
                        expirationTimestamp: nil
                    ),
                    now: 2,
                    tx: tx
                )
            }
        }
    }

    private func makeMessage(thread: TSContactThread, body: String) -> TSOutgoingMessage {
        write { tx in
            let factory = OutgoingMessageFactory()
            factory.threadCreator = { _ in thread }
            factory.messageBodyBuilder = { body }
            return factory.create(transaction: tx)
        }
    }

    private func statusOf(_ uri: String) -> TalerPaymentStatus? {
        var status: TalerPaymentStatus?
        read { tx in
            status = TalerPaymentStore.record(forUri: uri, tx: tx)?.status
        }
        return status
    }

    private func statusLineCount(threadUniqueId: String) -> Int {
        var count = 0
        read { tx in
            count = TSInteraction.anyFetchAll(transaction: tx).filter { interaction in
                guard let infoMessage = interaction as? TSInfoMessage else {
                    return false
                }
                let raw: String? = infoMessage.infoMessageValue(forKey: .talerPaymentStatus)
                return infoMessage.messageType == .talerPaymentUpdate
                    && raw == TalerPaymentStatus.lokalAbgebrochen.rawValue
                    && infoMessage.uniqueThreadId == threadUniqueId
            }.count
        }
        return count
    }

    func testCancelsOnlyOwnOpenShares() {
        let thread = makeThread()
        seedPayments(thread: thread)
        let body = [ownOpenUri, foreignOpenUri, ownAcceptedUri].joined(separator: "\n")
        let message = makeMessage(thread: thread, body: body)

        write { tx in
            TalerLocalDelete.cancelOpenOwnPayments(in: [message], tx: tx)
        }

        XCTAssertEqual(statusOf(ownOpenUri), .lokalAbgebrochen)
        XCTAssertEqual(statusOf(foreignOpenUri), .offen)
        XCTAssertEqual(statusOf(ownAcceptedUri), .angenommen)
        // Genau eine Zeile, nur fuer den abgebrochenen Anteil.
        XCTAssertEqual(statusLineCount(threadUniqueId: thread.uniqueId), 1)
    }

    func testMessageWithoutTalerUrisChangesNothing() {
        let thread = makeThread()
        seedPayments(thread: thread)
        let message = makeMessage(thread: thread, body: "Ganz normale Nachricht ohne Zahlungslink.")

        write { tx in
            TalerLocalDelete.cancelOpenOwnPayments(in: [message], tx: tx)
        }

        XCTAssertEqual(statusOf(ownOpenUri), .offen)
        XCTAssertEqual(statusOf(foreignOpenUri), .offen)
        XCTAssertEqual(statusLineCount(threadUniqueId: thread.uniqueId), 0)
    }

    func testEmptyInputIsSafe() {
        let thread = makeThread()
        seedPayments(thread: thread)
        write { tx in
            TalerLocalDelete.cancelOpenOwnPayments(in: [], tx: tx)
        }
        XCTAssertEqual(statusOf(ownOpenUri), .offen)
        XCTAssertEqual(statusLineCount(threadUniqueId: thread.uniqueId), 0)
    }
}
