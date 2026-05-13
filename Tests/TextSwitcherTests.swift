import XCTest
import AppKit

final class TextSwitcherTests: XCTestCase {

    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    private func savedItems(_ string: String) -> [[NSPasteboard.PasteboardType: Data]] {
        [[.string: Data(string.utf8)]]
    }

    // MARK: - Guarded restore behavior
    //
    // These tests drive the real restore-decision logic against a private
    // NSPasteboard. They exist to catch regressions in the guard that
    // prevents the original (pre-conversion) clipboard from being restored
    // before a slow host app reads it for Cmd+V — the actual symptom of the
    // bug this file fixes.

    /// Happy path: paste already happened, our converted string is still on
    /// the clipboard, so we restore the user's original content.
    func testRestoresOriginalWhenConvertedTextStillOnClipboard() {
        let converted = "он закатил скандал"
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)

        let didRestore = TextSwitcher.restoreClipboardIfStillOurs(
            savedItems: savedItems("ORIGINAL"),
            expectedConverted: converted,
            on: pasteboard
        )

        XCTAssertTrue(didRestore)
        XCTAssertEqual(pasteboard.string(forType: .string), "ORIGINAL")
    }

    /// The exact bug scenario: by the time our timer fires, the host app
    /// has not yet read the clipboard for Cmd+V. If we restored the original
    /// clipboard here (old behavior), the host would paste the previous
    /// clipboard contents instead of the converted text. The guard must
    /// refuse to restore whenever the clipboard differs from what we set.
    func testDoesNotRestoreWhenClipboardWasOverwrittenBeforePaste() {
        pasteboard.clearContents()
        pasteboard.setString("not what we set", forType: .string)

        let didRestore = TextSwitcher.restoreClipboardIfStillOurs(
            savedItems: savedItems("ORIGINAL"),
            expectedConverted: "converted text",
            on: pasteboard
        )

        XCTAssertFalse(didRestore)
        XCTAssertEqual(
            pasteboard.string(forType: .string), "not what we set",
            "Restore must not stomp on whatever is currently on the clipboard"
        )
    }

    func testDoesNotRestoreWhenClipboardIsEmpty() {
        pasteboard.clearContents()

        let didRestore = TextSwitcher.restoreClipboardIfStillOurs(
            savedItems: savedItems("ORIGINAL"),
            expectedConverted: "converted text",
            on: pasteboard
        )

        XCTAssertFalse(didRestore)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testDoesNotRestoreWhenSavedItemsAreNil() {
        let converted = "converted"
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)

        let didRestore = TextSwitcher.restoreClipboardIfStillOurs(
            savedItems: nil,
            expectedConverted: converted,
            on: pasteboard
        )

        XCTAssertFalse(didRestore)
        XCTAssertEqual(pasteboard.string(forType: .string), converted)
    }

    func testDoesNotRestoreWhenSavedItemsAreEmpty() {
        let converted = "converted"
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)

        let didRestore = TextSwitcher.restoreClipboardIfStillOurs(
            savedItems: [],
            expectedConverted: converted,
            on: pasteboard
        )

        XCTAssertFalse(didRestore)
        XCTAssertEqual(pasteboard.string(forType: .string), converted)
    }

    /// The user's original clipboard may carry RTF, HTML, file URLs etc.
    /// alongside the plain string. Restore must put every type back, not
    /// just the string — otherwise users lose rich content.
    func testRestorePreservesNonStringPasteboardTypes() {
        let converted = "converted"
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)

        let rtfData = Data("{\\rtf1\\ansi hello}".utf8)
        let items: [[NSPasteboard.PasteboardType: Data]] = [
            [
                .string: Data("plain".utf8),
                .rtf: rtfData
            ]
        ]

        let didRestore = TextSwitcher.restoreClipboardIfStillOurs(
            savedItems: items,
            expectedConverted: converted,
            on: pasteboard
        )

        XCTAssertTrue(didRestore)
        XCTAssertEqual(pasteboard.string(forType: .string), "plain")
        XCTAssertEqual(pasteboard.data(forType: .rtf), rtfData)
    }

    // MARK: - Delay formula — regression guards
    //
    // The exact formula is an empirical heuristic, so testing exact values
    // would just mirror the implementation. Instead, assert the invariants
    // that matter:

    /// The bug regression: 0.4 s was the previous fixed delay and was
    /// insufficient for ~50-character input in Slack. A longer phrase must
    /// now wait longer than that.
    func testRestoreDelayExceedsOldFixedValueForBugRepro() {
        let delay = TextSwitcher.clipboardRestoreDelay(forTextLength: 50)
        XCTAssertGreaterThan(delay, 0.4)
    }

    /// We must never wait so long that the user's clipboard is effectively
    /// hijacked. Even pathological input has to terminate quickly.
    func testRestoreDelayIsBoundedForPathologicalInput() {
        let delay = TextSwitcher.clipboardRestoreDelay(forTextLength: 100_000)
        XCTAssertLessThanOrEqual(delay, 3.0)
    }

    /// Short text was not affected by the bug — don't slow down the common
    /// case to fix a long-text race.
    func testRestoreDelayStaysSnappyForShortText() {
        let delay = TextSwitcher.clipboardRestoreDelay(forTextLength: 0)
        XCTAssertLessThanOrEqual(delay, 0.5)
    }

    func testRestoreDelayIsMonotonicInTextLength() {
        let short = TextSwitcher.clipboardRestoreDelay(forTextLength: 5)
        let medium = TextSwitcher.clipboardRestoreDelay(forTextLength: 50)
        let long = TextSwitcher.clipboardRestoreDelay(forTextLength: 500)
        XCTAssertLessThanOrEqual(short, medium)
        XCTAssertLessThanOrEqual(medium, long)
    }
}
