//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// Link-Bau nach docs/cross-platform/link-protokoll.md (Abschnitte 2.2, 3-6):
/// Parameterreihenfolge, memberCount nur bei Gruppe, strenge Kodierung
/// (nur RFC-3986-unreserved roh), Roundtrip, Aktionslink-Auswahl.
final class TalerLinksTest: XCTestCase {

    private let correlationId = "6f1c2a34-8b1e-4d7a-9c55-0e8f3b2a1d90"

    private func items(_ url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private func names(_ url: URL) -> [String] {
        items(url).map(\.name)
    }

    // MARK: compose-send

    func testComposeSendParameterOrderForIndividualChat() {
        let url = TalerLinks.composeSend(recipientHint: "Anna Müller", isGroup: false,
                                         memberCount: nil, disappearingMessagesSeconds: 0,
                                         direction: .payPush, correlationId: correlationId)
        XCTAssertEqual(url.scheme, "talerlink")
        XCTAssertEqual(url.host, "compose-send")
        XCTAssertEqual(names(url), ["recipientHint", "senderAppName", "isGroup", "direction",
                                     "disappearingMessagesSeconds", "correlationId", "returnUri"])
        XCTAssertEqual(items(url).map(\.value),
                       ["Anna Müller", "Signal", "false", "PAY_PUSH", "0", correlationId, "sgnl://taler-return"])
    }

    func testComposeSendIncludesSenderAppName() {
        let url = TalerLinks.composeSend(recipientHint: "Bob", isGroup: false,
                                         memberCount: nil, disappearingMessagesSeconds: 0,
                                         direction: .payPush, correlationId: correlationId)
        XCTAssertEqual(items(url).first { $0.name == "senderAppName" }?.value, "Signal")
    }

    func testComposeSendEncodesValuesStrictly() {
        // Umlaut als UTF-8, Leerzeichen als %20, Doppelpunkt und Slashes
        // kodiert - der Ruecksprung-Wert ist selbst eine URI.
        let url = TalerLinks.composeSend(recipientHint: "Anna Müller", isGroup: false,
                                         memberCount: nil, disappearingMessagesSeconds: 3600,
                                         direction: .payPull, correlationId: correlationId)
        XCTAssertEqual(url.absoluteString,
                       "talerlink://compose-send?recipientHint=Anna%20M%C3%BCller&senderAppName=Signal&isGroup=false"
                       + "&direction=PAY_PULL&disappearingMessagesSeconds=3600"
                       + "&correlationId=\(correlationId)"
                       + "&returnUri=sgnl%3A%2F%2Ftaler-return")
    }

    func testComposeSendGroupAppendsMemberCountLast() {
        let url = TalerLinks.composeSend(recipientHint: "Team", isGroup: true, memberCount: 5,
                                         disappearingMessagesSeconds: 86400,
                                         direction: .payPush, correlationId: correlationId)
        XCTAssertEqual(names(url).suffix(3), ["correlationId", "returnUri", "memberCount"])
        XCTAssertEqual(items(url).last?.value, "5")
    }

    func testComposeSendWithoutMemberCountForIndividualChat() {
        let url = TalerLinks.composeSend(recipientHint: "Bob", isGroup: false, memberCount: 5,
                                         disappearingMessagesSeconds: 0,
                                         direction: .payPush, correlationId: correlationId)
        // memberCount wird auch bei angegebenem Wert nur fuer Gruppen angehaengt (wie Android).
        XCTAssertFalse(names(url).contains("memberCount"))
    }

    func testComposeSendGroupWithoutMemberCountOmitsParameter() {
        let url = TalerLinks.composeSend(recipientHint: "Team", isGroup: true, memberCount: nil,
                                         disappearingMessagesSeconds: 0,
                                         direction: .payPush, correlationId: correlationId)
        XCTAssertFalse(names(url).contains("memberCount"))
    }

    // MARK: compose-refund

    func testComposeRefundParameterOrderAndEncoding() {
        let original = "taler://pay-push/exchange.example.org/AAA+B?x=1&y=/2#frag"
        let url = TalerLinks.composeRefund(originalUri: original, correlationId: correlationId)
        XCTAssertEqual(url.host, "compose-refund")
        XCTAssertEqual(names(url), ["originalUri", "correlationId", "returnUri"])
        // Alle Sonderzeichen kodiert: : / + ? = & # bleiben nirgends roh.
        XCTAssertEqual(url.absoluteString,
                       "talerlink://compose-refund?originalUri=taler%3A%2F%2Fpay-push%2Fexchange.example.org%2FAAA%2BB%3Fx%3D1%26y%3D%2F2%23frag"
                       + "&correlationId=\(correlationId)"
                       + "&returnUri=sgnl%3A%2F%2Ftaler-return")
    }

    // MARK: compose-abort

    func testComposeAbortRepeatsUriParameterInOrder() {
        let uris = ["taler://pay-push/exchange.example.org/AAAA",
                    "taler://pay-push/exchange.example.org/BBBB"]
        let url = TalerLinks.composeAbort(uris: uris, correlationId: correlationId)
        XCTAssertEqual(url.host, "compose-abort")
        XCTAssertEqual(names(url), ["uri", "uri", "correlationId", "returnUri"])
        XCTAssertEqual(items(url)[0].value, uris[0])
        XCTAssertEqual(items(url)[1].value, uris[1])
    }

    func testComposeAbortEncodesUris() {
        let uri = "taler://pay-push/e/A+B&C=D"
        let url = TalerLinks.composeAbort(uris: [uri], correlationId: correlationId)
        XCTAssertEqual(url.absoluteString,
                       "talerlink://compose-abort?uri=taler%3A%2F%2Fpay-push%2Fe%2FA%2BB%26C%3DD"
                       + "&correlationId=\(correlationId)"
                       + "&returnUri=sgnl%3A%2F%2Ftaler-return")
    }

    // MARK: Roundtrip

    func testRoundTripBuiltLinkDecodesToIdenticalValues() {
        // Werte mit allen problematischen Zeichen: + & = ? # und UTF-8.
        let hint = "Ärger + & = / : ? # ~"
        let uri = "taler://pay-push/ex/AAA?b=1&c=2#top"
        let send = TalerLinks.composeSend(recipientHint: hint, isGroup: true, memberCount: 3,
                                          disappearingMessagesSeconds: 604800,
                                          direction: .payPush, correlationId: correlationId)
        let sendItems = items(send)
        XCTAssertEqual(sendItems[0].value, hint)
        XCTAssertEqual(sendItems[5].value, correlationId)
        XCTAssertEqual(sendItems[6].value, "sgnl://taler-return")

        let refund = TalerLinks.composeRefund(originalUri: uri, correlationId: correlationId)
        XCTAssertEqual(items(refund)[0].value, uri)
        XCTAssertEqual(items(refund)[1].value, correlationId)

        let abort = TalerLinks.composeAbort(uris: [uri, uri], correlationId: correlationId)
        XCTAssertEqual(items(abort)[0].value, uri)
        XCTAssertEqual(items(abort)[1].value, uri)
        // Ein rohes + bleibt ein + (wird nicht zu einem Leerzeichen dekodiert).
        XCTAssertEqual(items(abort)[2].name, "correlationId")
    }

    // MARK: Aktionslink

    func testActionLinkPayPush() {
        let url = TalerLinks.actionLink(forTalerUri: "taler://pay-push/exchange.example.org/7Q4XK2",
                                        correlationId: correlationId)
        XCTAssertEqual(url?.absoluteString,
                       "talerlink://pay-push/exchange.example.org/7Q4XK2"
                       + "?correlationId=\(correlationId)"
                       + "&returnUri=sgnl%3A%2F%2Ftaler-return")
    }

    func testActionLinkPayPull() {
        let url = TalerLinks.actionLink(forTalerUri: "taler://pay-pull/exchange.example.org/7Q4XK2",
                                        correlationId: correlationId)
        XCTAssertEqual(url?.absoluteString,
                       "talerlink://pay-pull/exchange.example.org/7Q4XK2"
                       + "?correlationId=\(correlationId)"
                       + "&returnUri=sgnl%3A%2F%2Ftaler-return")
    }

    func testActionLinkIsCaseInsensitiveForSchemeAndAction() {
        let url = TalerLinks.actionLink(forTalerUri: "TALER://PAY-PULL/ex/AAA",
                                        correlationId: correlationId)
        // Scheme wird zu talerlink, der Rest bleibt unveraendert (Pfad inkl. Gross-/Kleinschreibung).
        XCTAssertEqual(url?.absoluteString,
                       "talerlink://PAY-PULL/ex/AAA?correlationId=\(correlationId)&returnUri=sgnl%3A%2F%2Ftaler-return")
    }

    func testActionLinkAppendsWithAmpersandWhenUriHasQuery() {
        let url = TalerLinks.actionLink(forTalerUri: "taler://pay-push/ex/AAA?foo=bar",
                                        correlationId: correlationId)
        XCTAssertEqual(url?.absoluteString,
                       "talerlink://pay-push/ex/AAA?foo=bar&correlationId=\(correlationId)&returnUri=sgnl%3A%2F%2Ftaler-return")
    }

    func testActionLinkRejectsOtherKindsAndGarbage() {
        XCTAssertNil(TalerLinks.actionLink(forTalerUri: "taler://withdraw/exchange.example.org/AAA", correlationId: correlationId))
        XCTAssertNil(TalerLinks.actionLink(forTalerUri: "taler://pay/exchange.example.org/AAA", correlationId: correlationId))
        XCTAssertNil(TalerLinks.actionLink(forTalerUri: "taler://refund/exchange.example.org/AAA", correlationId: correlationId))
        XCTAssertNil(TalerLinks.actionLink(forTalerUri: "ext+taler://pay-push/ex/AAA", correlationId: correlationId))
        XCTAssertNil(TalerLinks.actionLink(forTalerUri: "keine Taler-URI", correlationId: correlationId))
        XCTAssertNil(TalerLinks.actionLink(forTalerUri: "", correlationId: correlationId))
    }
}
