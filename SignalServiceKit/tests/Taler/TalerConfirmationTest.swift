//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Bestaetigungsnachricht (S7a): Format bauen und erkennen, Speichern nur
/// fuer eine eigene Zahlung im selben 1:1-Chat, Gruppen/Leertext/Muelltext
/// nie. Spiegel der Faelle aus `TalerConfirmationDetectorTest`/
/// `TalerConfirmationTrackerTest` (signal-android).
final class TalerConfirmationTest: SSKBaseTest {

    private let uri = "taler://pay-push/exchange.example/AAA"

    // MARK: Format

    func testBodyBuildsEnglishProtocolFormat() {
        XCTAssertEqual(
            TalerConfirmationDetector.body(kind: .payPush, uri: uri),
            "Payment for Taler payment link accepted (\(uri))"
        )
        XCTAssertEqual(
            TalerConfirmationDetector.body(kind: .payPull, uri: uri),
            "Payment for Taler payment request accepted (\(uri))"
        )
        // Nur Peer-Arten haben einen Wortlaut.
        XCTAssertNil(TalerConfirmationDetector.body(kind: .pay, uri: uri))
        XCTAssertNil(TalerConfirmationDetector.body(kind: .withdraw, uri: uri))
        XCTAssertNil(TalerConfirmationDetector.body(kind: .refund, uri: uri))
    }

    // MARK: Erkennen

    func testMatchRecognizesBuiltBody() {
        for kind in [TalerUriKind.payPush, .payPull] {
            let body = TalerConfirmationDetector.body(kind: kind, uri: uri)
            let match = TalerConfirmationDetector.match(body!)
            XCTAssertEqual(match?.uri, uri)
            XCTAssertEqual(match?.kind, kind)
        }
    }

    func testMatchRejectsEmptyAndGarbage() {
        XCTAssertNil(TalerConfirmationDetector.match(""))
        XCTAssertNil(TalerConfirmationDetector.match("   "))
        XCTAssertNil(TalerConfirmationDetector.match("Hallo Welt"))
        XCTAssertNil(TalerConfirmationDetector.match("12345"))
        XCTAssertNil(TalerConfirmationDetector.match(uri))
    }

    func testMatchRejectsNearMisses() {
        // Angehaengtes Leerzeichen, Kleinschreibung, deutscher Wortlaut,
        // anderes Verb: alles kein Treffer (exakter Volltext-Match).
        XCTAssertNil(TalerConfirmationDetector.match("Payment for Taler payment link accepted (\(uri)) "))
        XCTAssertNil(TalerConfirmationDetector.match("payment for taler payment link accepted (\(uri))"))
        XCTAssertNil(TalerConfirmationDetector.match("Zahlung für Taler payment link akzeptiert (\(uri))"))
        XCTAssertNil(TalerConfirmationDetector.match("Payment for Taler payment link declined (\(uri))"))
        XCTAssertNil(TalerConfirmationDetector.match("Payment for Taler payment link accepted (\(uri))!"))
        // Zwei URIs im Text sind keine Bestaetigung.
        XCTAssertNil(TalerConfirmationDetector.match(
            "Payment for Taler payment link accepted (\(uri)) taler://pay-push/exchange.example/BBB"
        ))
    }

    // MARK: Speichern

    private func makeThread() -> TSContactThread {
        write { tx in
            ContactThreadFactory().create(transaction: tx)
        }
    }

    private func makeIncomingMessage(thread: TSContactThread, body: String) -> TSIncomingMessage {
        write { tx in
            let factory = IncomingMessageFactory()
            factory.threadCreator = { _ in thread }
            factory.messageBodyBuilder = { body }
            return factory.create(transaction: tx)
        }
    }

    /// Legt einen Vorgang an und setzt Art/Status wie im echten Ablauf ueber
    /// die Exchange-Vorschau.
    private func seedPayment(uri: String, thread: TSContactThread, kind: TalerUriKind, isOwn: Bool, status: TalerOperationStatus) {
        write { tx in
            TalerPaymentStore.upsertDetected(uri: uri, threadUniqueId: thread.uniqueId, isOwnPayment: isOwn, now: 1, tx: tx)
            _ = TalerPaymentStore.applyPreviewAndRecordTransition(
                uri: uri,
                preview: TalerPaymentPreview(
                    uriKind: kind,
                    status: status,
                    amount: "1.5",
                    currency: "KUDOS",
                    exchangeBaseUrl: "https://exchange.example/",
                    summary: nil,
                    expirationTimestamp: nil
                ),
                now: 2,
                tx: tx,
            )
        }
    }

    private func trackConfirmation(
        message: TSIncomingMessage,
        threadUniqueId: String,
        isGroupThread: Bool = false,
        triggeredUris: ReferenceBox<[String]>? = nil
    ) {
        write { tx in
            TalerConfirmationTracker.track(
                body: message.body,
                threadUniqueId: threadUniqueId,
                isGroupThread: isGroupThread,
                interactionId: message.sqliteRowId!,
                tx: tx,
                triggerRefresh: { uri in triggeredUris?.value.append(uri) }
            )
        }
    }

    private final class ReferenceBox<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func confirmationUri(for message: TSIncomingMessage) -> String? {
        // SSKBaseTest.read ist nach dem Upstream-Merge nur noch (DBReadTransaction) -> Void;
        // fuer Rueckgabewerte direkt auf databaseStorageRef.read gehen (generic).
        SSKEnvironment.shared.databaseStorageRef.read(block: { TalerPaymentStore.confirmationUri(interactionId: message.sqliteRowId!, tx: $0) })
    }

    func testTrackStoresConfirmationForOwnPayment() {
        let thread = makeThread()
        seedPayment(uri: uri, thread: thread, kind: .payPush, isOwn: true, status: .offen)
        let message = makeIncomingMessage(
            thread: thread,
            body: TalerConfirmationDetector.body(kind: .payPush, uri: uri)!,
        )
        trackConfirmation(message: message, threadUniqueId: thread.uniqueId)
        XCTAssertEqual(confirmationUri(for: message), uri)
        XCTAssertEqual(SSKEnvironment.shared.databaseStorageRef.read(block: { TalerPaymentStore.confirmationInteractionIds(forUri: uri, tx: $0) }), [message.sqliteRowId!])
    }

    func testTrackTriggersRefreshForStoredConfirmation() {
        let thread = makeThread()
        seedPayment(uri: uri, thread: thread, kind: .payPush, isOwn: true, status: .offen)
        let message = makeIncomingMessage(
            thread: thread,
            body: TalerConfirmationDetector.body(kind: .payPush, uri: uri)!,
        )
        let triggered = ReferenceBox<[String]>([])
        trackConfirmation(message: message, threadUniqueId: thread.uniqueId, triggeredUris: triggered)
        XCTAssertEqual(triggered.value, [uri])
    }

    func testTrackIgnoresForeignPayment() {
        let thread = makeThread()
        // Die Zahlung kam von der Gegenseite (isOwnPayment false): deren
        // Bestaetigungstext ist fuer uns kein Treffer.
        seedPayment(uri: uri, thread: thread, kind: .payPush, isOwn: false, status: .offen)
        let message = makeIncomingMessage(
            thread: thread,
            body: TalerConfirmationDetector.body(kind: .payPush, uri: uri)!,
        )
        trackConfirmation(message: message, threadUniqueId: thread.uniqueId)
        XCTAssertNil(confirmationUri(for: message))
    }

    func testTrackIgnoresGroupThread() {
        let thread = makeThread()
        seedPayment(uri: uri, thread: thread, kind: .payPush, isOwn: true, status: .offen)
        let message = makeIncomingMessage(
            thread: thread,
            body: TalerConfirmationDetector.body(kind: .payPush, uri: uri)!,
        )
        trackConfirmation(message: message, threadUniqueId: thread.uniqueId, isGroupThread: true)
        XCTAssertNil(confirmationUri(for: message))
    }

    func testTrackIgnoresOtherThreadAndKindMismatch() {
        let thread = makeThread()
        seedPayment(uri: uri, thread: thread, kind: .payPush, isOwn: true, status: .offen)

        // Bestaetigung einer anderen URI: kein Datensatz -> kein Treffer.
        let otherUri = "taler://pay-push/exchange.example/OTHER"
        let otherMessage = makeIncomingMessage(
            thread: thread,
            body: TalerConfirmationDetector.body(kind: .payPush, uri: otherUri)!,
        )
        trackConfirmation(message: otherMessage, threadUniqueId: thread.uniqueId)
        XCTAssertNil(confirmationUri(for: otherMessage))

        // Art-Label passt nicht zum Datensatz (pay-pull vs. pay-push).
        let kindMessage = makeIncomingMessage(
            thread: thread,
            body: TalerConfirmationDetector.body(kind: .payPull, uri: uri)!,
        )
        trackConfirmation(message: kindMessage, threadUniqueId: thread.uniqueId)
        XCTAssertNil(confirmationUri(for: kindMessage))
    }

    func testTrackRejectsEmptyAndGarbageBody() {
        let thread = makeThread()
        seedPayment(uri: uri, thread: thread, kind: .payPush, isOwn: true, status: .offen)
        for body in ["", "   ", "Hallo Welt", "Payment for Taler payment link accepted "] {
            let message = makeIncomingMessage(thread: thread, body: body)
            trackConfirmation(message: message, threadUniqueId: thread.uniqueId)
            XCTAssertNil(confirmationUri(for: message), "Unerwarteter Treffer fuer: \(body)")
        }
    }
}
