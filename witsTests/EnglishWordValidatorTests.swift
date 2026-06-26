import XCTest
@testable import wits

final class EnglishWordValidatorTests: XCTestCase {
    func testRejectsRandomFiveLetterStrings() {
        XCTAssertFalse(EnglishWordValidator.isValidWord("zzzzz", length: 5))
        XCTAssertFalse(EnglishWordValidator.isValidWord("qwert", length: 5))
    }

    func testAcceptsKnownAnswerBankWords() {
        XCTAssertTrue(EnglishWordValidator.isValidWord("crane", length: 5, acceptedWords: ["crane"]))
    }

    func testRejectsWrongLengthWords() {
        XCTAssertFalse(EnglishWordValidator.isValidWord("crane", length: 6, acceptedWords: ["crane"]))
    }
}
