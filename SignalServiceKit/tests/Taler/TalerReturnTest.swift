//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Ruecksprung-Parser nach docs/cross-platform/link-protokoll.md (2.3, 8, 9):
/// Scheme/Host-Pflicht, Pflichtparameter correlationId, status nur ready oder
/// cancelled, talerUri/talerPaymentData nur bei ready, result am ersten `|`
/// geteilt, ungueltige Einzelwerte verworfen.
final class TalerReturnTest: XCTestCase {

    private func parse(_ string: String) -> TalerReturn? {
        guard let url = URL(string: string) else {
            XCTFail("Test-URL nicht baubar: \(string)")
            return nil
        }
        return TalerReturn.parse(url)
    }

    // MARK: Scheme und Host

    func testRejectsWrongSchemeOrHost() {
        XCTAssertNil(parse("sgnl://linkdevice?correlationId=abc"))
        XCTAssertNil(parse("talerlink://compose-send?correlationId=abc"))
        XCTAssertNil(parse("sgnl://other?correlationId=abc"))
        // Opake URL ohne Host.
        XCTAssertNil(parse("sgnl:taler-return?correlationId=abc"))
    }

    func testAcceptsUppercaseSchemeAndHost() {
        let result = parse("SGNL://TALER-RETURN?correlationId=abc&status=ready")
        XCTAssertEqual(result?.correlationId, "abc")
        XCTAssertEqual(result?.status, .ready)
    }

    // MARK: correlationId

    func testRejectsMissingOrEmptyCorrelationId() {
        XCTAssertNil(parse("sgnl://taler-return"))
        XCTAssertNil(parse("sgnl://taler-return?status=ready"))
        XCTAssertNil(parse("sgnl://taler-return?correlationId="))
        XCTAssertNil(parse("sgnl://taler-return?correlationId=&status=ready"))
    }

    func testFirstValueWinsForDuplicateParameters() {
        let result = parse("sgnl://taler-return?correlationId=first&correlationId=second&status=cancelled&status=ready")
        XCTAssertEqual(result?.correlationId, "first")
        XCTAssertEqual(result?.status, .cancelled)
    }

    // MARK: status-Variante

    func testReadyWithTalerUri() {
        let result = parse("sgnl://taler-return?correlationId=abc&status=ready&talerUri=taler%3A%2F%2Fpay-push%2Fex%2FAAA")
        XCTAssertEqual(result?.correlationId, "abc")
        XCTAssertEqual(result?.status, .ready)
        XCTAssertEqual(result?.talerUri, "taler://pay-push/ex/AAA")
        XCTAssertNil(result?.talerPaymentData)
        XCTAssertEqual(result?.results, [])
    }

    func testReadyWithTalerPaymentDataJson() {
        let result = parse("sgnl://taler-return?correlationId=abc&status=ready&talerPaymentData=%7B%22uri%22%3A%5B%22taler%3A%2F%2Fpay-push%2Fex%2FAAA%22%5D%7D")
        XCTAssertEqual(result?.status, .ready)
        XCTAssertEqual(result?.talerPaymentData, "{\"uri\":[\"taler://pay-push/ex/AAA\"]}")
        XCTAssertNil(result?.talerUri)
    }

    func testCancelledIgnoresTalerUri() {
        let result = parse("sgnl://taler-return?correlationId=abc&status=cancelled&talerUri=taler%3A%2F%2Fpay-push%2Fex%2FAAA&talerPaymentData=%7B%7D")
        XCTAssertEqual(result?.status, .cancelled)
        XCTAssertNil(result?.talerUri)
        XCTAssertNil(result?.talerPaymentData)
    }

    func testUnknownOrMissingStatusIsTreatedAsMissingButReturnParsed() {
        // Unbekannter Status: Ruecksprung bleibt gueltig (z. B. Fast-Poll bei
        // ACCEPT_OR_CANCEL), aber talerUri/talerPaymentData werden nicht uebernommen.
        let unknown = parse("sgnl://taler-return?correlationId=abc&status=nonsense&talerUri=taler%3A%2F%2Fpay-push%2Fex%2FAAA")
        XCTAssertEqual(unknown?.correlationId, "abc")
        XCTAssertNil(unknown?.status)
        XCTAssertNil(unknown?.talerUri)

        let missing = parse("sgnl://taler-return?correlationId=abc")
        XCTAssertEqual(missing?.correlationId, "abc")
        XCTAssertNil(missing?.status)
        XCTAssertNil(missing?.talerUri)
        XCTAssertNil(missing?.talerPaymentData)
    }

    // MARK: result-Variante (Gap A)

    func testResultsKeepOrderAndAllKnownOutcomes() {
        let result = parse("sgnl://taler-return?correlationId=abc"
                           + "&result=taler%3A%2F%2Fpay-push%2Fex%2FAAAA%7Caborted"
                           + "&result=taler%3A%2F%2Fpay-push%2Fex%2FBBBB%7Calready_claimed"
                           + "&result=taler%3A%2F%2Fpay-push%2Fex%2FCCCC%7Cexpired"
                           + "&result=taler%3A%2F%2Fpay-push%2Fex%2FDDDD%7Cdeclined")
        XCTAssertEqual(result?.correlationId, "abc")
        XCTAssertEqual(result?.results, [
            TalerAbortResult(uri: "taler://pay-push/ex/AAAA", outcome: .aborted),
            TalerAbortResult(uri: "taler://pay-push/ex/BBBB", outcome: .alreadyClaimed),
            TalerAbortResult(uri: "taler://pay-push/ex/CCCC", outcome: .expired),
            TalerAbortResult(uri: "taler://pay-push/ex/DDDD", outcome: .declined),
        ])
        XCTAssertNil(result?.status)
    }

    func testResultWithPipeInUriQueryIsDiscarded() {
        // Das zweite | bleibt im Status-Teil ("cd|aborted" ist unbekannt),
        // nur dieser Eintrag wird verworfen, nicht der Ruecksprung.
        let result = parse("sgnl://taler-return?correlationId=abc"
                           + "&result=taler%3A%2F%2Fpay-push%2Fex%2FAAA%3Fx%3Dab%7Ccd%7Caborted")
        XCTAssertEqual(result?.correlationId, "abc")
        XCTAssertEqual(result?.results, [])
    }

    func testResultWithoutPipeOrUnknownOutcomeIsDiscardedIndividually() {
        let result = parse("sgnl://taler-return?correlationId=abc"
                           + "&result=nopipe"
                           + "&result=taler%3A%2F%2Fpay-push%2Fex%2FAAAA%7Cunknown_status"
                           + "&result=taler%3A%2F%2Fpay-push%2Fex%2FBBBB%7Caborted")
        XCTAssertEqual(result?.results, [TalerAbortResult(uri: "taler://pay-push/ex/BBBB", outcome: .aborted)])
    }

    func testResultWithoutOutcomeAfterPipeIsDiscarded() {
        let result = parse("sgnl://taler-return?correlationId=abc&result=taler%3A%2F%2Fex%2FAAA%7C")
        XCTAssertEqual(result?.results, [])
    }

    // MARK: Kombination und unbekannte Parameter

    func testUnknownParametersAreIgnored() {
        let result = parse("sgnl://taler-return?correlationId=abc&foo=bar&status=ready")
        XCTAssertEqual(result?.correlationId, "abc")
        XCTAssertEqual(result?.status, .ready)
    }
}
