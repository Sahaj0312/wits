import XCTest
@testable import wits

final class ReviewPrompterTests: XCTestCase {
    func testAutomaticRequestRequiresFiveFinishedGames() async {
        await MainActor.run {
            withCleanDefaults { defaults in
                let firstUse = Date(timeIntervalSince1970: 1_000_000)
                let eligibleDate = firstUse.addingTimeInterval(24 * 60 * 60)

                ReviewPrompter.appStarted(now: firstUse, defaults: defaults)
                for _ in 0..<4 {
                    ReviewPrompter.gameFinished(now: eligibleDate, defaults: defaults)
                }

                XCTAssertFalse(ReviewPrompter.takePendingRequest(now: eligibleDate,
                                                                 defaults: defaults))

                ReviewPrompter.gameFinished(now: eligibleDate, defaults: defaults)

                XCTAssertTrue(ReviewPrompter.takePendingRequest(now: eligibleDate,
                                                                defaults: defaults))
            }
        }
    }

    func testAutomaticRequestWaitsTwentyFourHours() async {
        await MainActor.run {
            withCleanDefaults { defaults in
                let firstUse = Date(timeIntervalSince1970: 2_000_000)
                let tooEarly = firstUse.addingTimeInterval(24 * 60 * 60 - 1)

                ReviewPrompter.appStarted(now: firstUse, defaults: defaults)
                for _ in 0..<5 {
                    ReviewPrompter.gameFinished(now: tooEarly, defaults: defaults)
                }

                XCTAssertFalse(ReviewPrompter.takePendingRequest(now: tooEarly,
                                                                 defaults: defaults))
            }
        }
    }

    func testRepeatedStartsDoNotMoveFirstUseDateForward() async {
        await MainActor.run {
            withCleanDefaults { defaults in
                let firstUse = Date(timeIntervalSince1970: 3_000_000)
                let laterLaunch = firstUse.addingTimeInterval(12 * 60 * 60)
                let eligibleDate = firstUse.addingTimeInterval(24 * 60 * 60)

                ReviewPrompter.appStarted(now: firstUse, defaults: defaults)
                ReviewPrompter.appStarted(now: laterLaunch, defaults: defaults)
                for _ in 0..<5 {
                    ReviewPrompter.gameFinished(now: eligibleDate, defaults: defaults)
                }

                XCTAssertTrue(ReviewPrompter.takePendingRequest(now: eligibleDate,
                                                                defaults: defaults))
            }
        }
    }

    @MainActor
    private func withCleanDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "ReviewPrompterTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults")
            return
        }

        ReviewPrompter.resetSessionStateForTesting()
        defer {
            ReviewPrompter.resetSessionStateForTesting()
            defaults.removePersistentDomain(forName: suiteName)
        }
        body(defaults)
    }
}
