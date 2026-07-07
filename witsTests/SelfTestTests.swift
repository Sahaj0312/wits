//
//  SelfTestTests.swift
//  witsTests
//
//  Self-report test catalog: scoring keys (thresholds, reverse-scored items,
//  subscales) and catalog integrity (every question answerable, scorer ranges
//  hold for extreme answers).
//

import XCTest
@testable import wits

final class SelfTestTests: XCTestCase {

    // MARK: Catalog integrity

    func testCatalogIsWellFormed() {
        XCTAssertFalse(SelfTestCatalog.all.isEmpty)
        XCTAssertEqual(Set(SelfTestCatalog.all.map(\.id)).count, SelfTestCatalog.all.count, "test ids must be unique")
        for test in SelfTestCatalog.all {
            XCTAssertFalse(test.questions.isEmpty, "\(test.id) needs questions")
            for (index, question) in test.questions.enumerated() {
                let options = test.options(for: question)
                XCTAssertGreaterThanOrEqual(options.count, 2, "\(test.id) q\(index) needs a scale")
            }
        }
    }

    /// Extreme answer patterns must produce scores within [0, maxScore] and a
    /// non-empty label — guards against off-by-one keying in any scorer.
    func testScorersStayInRangeForExtremeAnswers() {
        for test in SelfTestCatalog.all {
            let lows = test.questions.map { test.options(for: $0).first!.value }
            let highs = test.questions.map { test.options(for: $0).last!.value }
            for answers in [lows, highs] {
                let outcome = test.score(answers)
                XCTAssertFalse(outcome.label.isEmpty, test.id)
                XCTAssertGreaterThanOrEqual(outcome.score, 0, test.id)
                XCTAssertLessThanOrEqual(outcome.score, outcome.maxScore, test.id)
            }
        }
    }

    // MARK: Instrument keying

    func testASRSThreshold() {
        // Items 1–3 flag from "sometimes" (2), items 4–6 only from "often" (3).
        let justUnder = [2, 2, 2, 2, 2, 2]   // 3 markers — items 4–6 miss at 2
        XCTAssertEqual(SelfTestCatalog.scoreASRS(justUnder).score, 3)
        XCTAssertTrue(SelfTestCatalog.scoreASRS(justUnder).label.hasPrefix("below threshold"))

        let justOver = [2, 2, 2, 3, 2, 2]    // 4 markers
        XCTAssertEqual(SelfTestCatalog.scoreASRS(justOver).score, 4)
        XCTAssertTrue(SelfTestCatalog.scoreASRS(justOver).label.hasPrefix("signals present"))
    }

    func testAQ10Keying() {
        // Agree on agree-keyed items (1,7,8,10) + disagree on the rest = 10/10.
        let allKeyed = [0, 3, 3, 3, 3, 3, 0, 0, 3, 0]
        XCTAssertEqual(SelfTestCatalog.scoreAQ10(allKeyed).score, 10)
        // The exact opposite pattern scores 0.
        let none = [3, 0, 0, 0, 0, 0, 3, 3, 0, 3]
        XCTAssertEqual(SelfTestCatalog.scoreAQ10(none).score, 0)
        // Threshold at 6.
        let six = [0, 3, 3, 3, 3, 3, 0, 3, 0, 3]   // items 1,2,3,4,5,6 keyed → 6 points
        XCTAssertTrue(SelfTestCatalog.scoreAQ10(six).label.hasPrefix("elevated traits"))
    }

    func testWHO5Scaling() {
        XCTAssertEqual(SelfTestCatalog.scoreWHO5([5, 5, 5, 5, 5]).score, 100)
        XCTAssertEqual(SelfTestCatalog.scoreWHO5([0, 0, 0, 0, 0]).score, 0)
        XCTAssertEqual(SelfTestCatalog.scoreWHO5([3, 3, 3, 3, 3]).score, 60)
    }

    func testRMEQCategories() {
        XCTAssertTrue(SelfTestCatalog.scoreRMEQ([1, 1, 1, 1, 0]).label.hasPrefix("definite night owl"))
        XCTAssertTrue(SelfTestCatalog.scoreRMEQ([3, 3, 3, 3, 2]).label.hasPrefix("hummingbird"))
        XCTAssertTrue(SelfTestCatalog.scoreRMEQ([5, 4, 5, 5, 6]).label.hasPrefix("definite lark"))
    }

    func testMiniIPIPReversalAndSubscales() {
        // "Very accurate" (5) on every item: reversed items flip to 1, so every
        // factor with 2 reversed items scores 4·... check extraversion exactly:
        // items 1(+),6(r),11(+),16(r) → 5+1+5+1 = 12.
        let all5 = Array(repeating: 5, count: 20)
        let outcome = SelfTestCatalog.scoreMiniIPIP(all5)
        XCTAssertEqual(outcome.subscales?["extraversion"], 12)
        // Openness has three reversed items (10,15,20) → 5+1+1+1 = 8.
        XCTAssertEqual(outcome.subscales?["openness"], 8)
        XCTAssertEqual(outcome.subscales?.count, 5)
    }

    func testDirtyDozenSubscales() {
        // Agree strongly on machiavellianism items only.
        let answers = [5, 5, 5, 5, 1, 1, 1, 1, 1, 1, 1, 1]
        let outcome = SelfTestCatalog.scoreDirtyDozen(answers)
        XCTAssertEqual(outcome.subscales?["machiavellianism"], 20)
        XCTAssertEqual(outcome.subscales?["psychopathy"], 4)
        XCTAssertEqual(outcome.subscales?["narcissism"], 4)
        XCTAssertEqual(outcome.score, 28)
    }

    func testNCS6Reversal() {
        // Max thinking-lover: 5 on positives, 1 on reversed items 3 & 4.
        XCTAssertEqual(SelfTestCatalog.scoreNCS6([5, 5, 1, 1, 5, 5]).score, 30)
        XCTAssertTrue(SelfTestCatalog.scoreNCS6([5, 5, 1, 1, 5, 5]).label.hasPrefix("insatiable"))
        // All neutral = 18 → balanced.
        XCTAssertTrue(SelfTestCatalog.scoreNCS6([3, 3, 3, 3, 3, 3]).label.hasPrefix("balanced"))
    }

    func testVVIQBands() {
        XCTAssertTrue(SelfTestCatalog.scoreVVIQ(Array(repeating: 1, count: 16)).label.hasPrefix("aphantasia"))
        XCTAssertTrue(SelfTestCatalog.scoreVVIQ(Array(repeating: 2, count: 16)).label.hasPrefix("dim imagery"))
        XCTAssertTrue(SelfTestCatalog.scoreVVIQ(Array(repeating: 5, count: 16)).label.hasPrefix("hyperphantasia"))
    }

    func testRosenbergReversal() {
        // Strongly agree (3) with positives, strongly disagree (0) with the five
        // reversed items (2,5,6,8,9) → 30/30.
        let answers = [3, 0, 3, 3, 0, 0, 3, 0, 0, 3]
        XCTAssertEqual(SelfTestCatalog.scoreRosenberg(answers).score, 30)
        // The exact inverse → 0.
        let inverse = [0, 3, 0, 0, 3, 3, 0, 3, 3, 0]
        XCTAssertEqual(SelfTestCatalog.scoreRosenberg(inverse).score, 0)
    }
}
