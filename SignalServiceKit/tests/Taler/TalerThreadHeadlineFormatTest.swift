//
// GNU Taler integration.
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

/// `TalerThreadHeadlineFormat` uebersetzt die Headline-Rangfolge des S5-Tab
/// in Icon und Text. Getestet wird die Zweigauswahl (Singular/Plural,
/// Namensersetzung im 1:1-Chat), nicht der Wortlaut der Lokalisierung.
final class TalerThreadHeadlineFormatTest: XCTestCase {

    func testEmptyIsEmpty() {
        let label = TalerThreadHeadlineFormat.label(for: .empty, chatName: nil)
        XCTAssertEqual("", label.icon)
        XCTAssertEqual("", label.text)
    }

    func testWaitingForMeSingularUsesSingularString() {
        let label = TalerThreadHeadlineFormat.label(for: .waitingForMe(1), chatName: nil)
        XCTAssertEqual("●", label.icon)
        XCTAssertEqual(TalerStrings.headlineWaitingForMe, label.text)
    }

    func testWaitingForMePluralUsesCountFormat() {
        let label = TalerThreadHeadlineFormat.label(for: .waitingForMe(3), chatName: nil)
        XCTAssertEqual("●", label.icon)
        XCTAssertEqual(String(format: TalerStrings.headlineWaitingForMeFormat, 3), label.text)
    }

    func testWaitingForOtherPrefersTheChatName() {
        let label = TalerThreadHeadlineFormat.label(for: .waitingForOther(2), chatName: "Anna")
        XCTAssertEqual("●", label.icon)
        XCTAssertEqual(String(format: TalerStrings.headlineWaitingForOtherNameFormat, "Anna"), label.text)
    }

    func testWaitingForOtherIgnoresBlankChatName() {
        let label = TalerThreadHeadlineFormat.label(for: .waitingForOther(1), chatName: "  ")
        XCTAssertEqual(TalerStrings.headlineWaitingForOther, label.text)
    }

    func testWaitingForOtherWithoutNameCounts() {
        let singular = TalerThreadHeadlineFormat.label(for: .waitingForOther(1), chatName: nil)
        XCTAssertEqual(TalerStrings.headlineWaitingForOther, singular.text)

        let plural = TalerThreadHeadlineFormat.label(for: .waitingForOther(4), chatName: nil)
        XCTAssertEqual(String(format: TalerStrings.headlineWaitingForOtherFormat, 4), plural.text)
    }

    func testWaitingForBothEmbedsBothCounts() {
        let label = TalerThreadHeadlineFormat.label(for: .waitingForBoth(forMe: 2, forOther: 5), chatName: nil)
        XCTAssertEqual("●", label.icon)
        XCTAssertEqual(String(format: TalerStrings.headlineWaitingForBothFormat, 2, 5), label.text)
    }

    func testUnverifiableSingularAndPlural() {
        let singular = TalerThreadHeadlineFormat.label(for: .unverifiable(1), chatName: nil)
        XCTAssertEqual("…", singular.icon)
        XCTAssertEqual(TalerStrings.headlineUnverifiable, singular.text)

        let plural = TalerThreadHeadlineFormat.label(for: .unverifiable(2), chatName: nil)
        XCTAssertEqual(String(format: TalerStrings.headlineUnverifiableFormat, 2), plural.text)
    }

    func testAllSettledIsCountIndependent() {
        let label = TalerThreadHeadlineFormat.label(for: .allSettled(7), chatName: nil)
        XCTAssertEqual("✓", label.icon)
        XCTAssertEqual(TalerStrings.headlineAllSettled, label.text)
    }
}
