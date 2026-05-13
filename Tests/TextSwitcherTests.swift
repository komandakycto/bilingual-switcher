import XCTest

final class TextSwitcherTests: XCTestCase {

    // MARK: - Clipboard Restore Delay

    func testRestoreDelayBaselineForEmptyText() {
        let delay = TextSwitcher.clipboardRestoreDelay(forTextLength: 0)
        XCTAssertEqual(delay, 0.4, accuracy: 0.0001)
    }

    func testRestoreDelayScalesWithTextLength() {
        let short = TextSwitcher.clipboardRestoreDelay(forTextLength: 5)
        let medium = TextSwitcher.clipboardRestoreDelay(forTextLength: 50)
        let long = TextSwitcher.clipboardRestoreDelay(forTextLength: 200)
        XCTAssertLessThan(short, medium)
        XCTAssertLessThan(medium, long)
    }

    func testRestoreDelayMatchesFormulaForTypicalSentence() {
        // 50 chars (a Slack-sized phrase in the wrong layout) → 0.4 + 50 * 0.02 = 1.4 s.
        let delay = TextSwitcher.clipboardRestoreDelay(forTextLength: 50)
        XCTAssertEqual(delay, 1.4, accuracy: 0.0001)
    }

    func testRestoreDelayClampedForVeryLongText() {
        // Pathological input must not delay restoration indefinitely.
        let delay = TextSwitcher.clipboardRestoreDelay(forTextLength: 10_000)
        XCTAssertLessThanOrEqual(delay, 3.0)
        XCTAssertGreaterThan(delay, 1.0)
    }
}
