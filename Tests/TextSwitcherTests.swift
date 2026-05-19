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

    // MARK: - chunkUTF16

    func testChunkUTF16_EmptyStringYieldsEmptyArray() {
        XCTAssertEqual(TextSwitcher.chunkUTF16("", maxCodeUnits: 20).count, 0)
    }

    func testChunkUTF16_ShorterThanLimitFitsInOneChunk() {
        let chunks = TextSwitcher.chunkUTF16("hi", maxCodeUnits: 20)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], Array("hi".utf16))
    }

    func testChunkUTF16_ExactlyLimitFitsInOneChunk() {
        let text = String(repeating: "a", count: 20)
        let chunks = TextSwitcher.chunkUTF16(text, maxCodeUnits: 20)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 20)
    }

    func testChunkUTF16_LongerThanLimitSplitsCorrectly() {
        let text = String(repeating: "a", count: 25)
        let chunks = TextSwitcher.chunkUTF16(text, maxCodeUnits: 10)
        XCTAssertEqual(chunks.map(\.count), [10, 10, 5])
    }

    func testChunkUTF16_LosslessRoundTripASCII() {
        let original = String(repeating: "x", count: 73)
        let chunks = TextSwitcher.chunkUTF16(original, maxCodeUnits: 20)
        let flat = chunks.flatMap { $0 }
        XCTAssertEqual(String(utf16CodeUnits: flat, count: flat.count), original)
    }

    /// The actual bug case input — typed in EN layout but produced via RU
    /// keyboard, ~50 chars. Must round-trip cleanly through chunking.
    func testChunkUTF16_LosslessRoundTripMixedScripts() {
        let original = "он закатил скандал; раньше был более аккуратный"
        let chunks = TextSwitcher.chunkUTF16(original, maxCodeUnits: 20)
        let flat = chunks.flatMap { $0 }
        XCTAssertEqual(String(utf16CodeUnits: flat, count: flat.count), original)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 20)
        }
    }

    func testChunkUTF16_NeverExceedsLimit() {
        let chunks = TextSwitcher.chunkUTF16(String(repeating: "a", count: 1000), maxCodeUnits: 20)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 20)
        }
        XCTAssertEqual(chunks.count, 50)
    }

    func testChunkUTF16_RespectsCustomLimit() {
        let chunks = TextSwitcher.chunkUTF16("abcdefghij", maxCodeUnits: 3)
        XCTAssertEqual(chunks.map(\.count), [3, 3, 3, 1])
    }

    /// Regression for reviewer-found bug: naive UTF-16 slicing splits the
    /// 🙂 surrogate pair across chunk 1 (high surrogate) and chunk 2 (low
    /// surrogate), sending malformed UTF-16 to CoreGraphics. The scalar-aware
    /// packer must flush the chunk early so the pair stays together.
    func testChunkUTF16_DoesNotSplitSurrogatePairAtBoundary() {
        let text = String(repeating: "a", count: 19) + "🙂"
        let chunks = TextSwitcher.chunkUTF16(text, maxCodeUnits: 20)

        XCTAssertEqual(chunks.count, 2,
                       "Chunker must flush early to keep the surrogate pair together")
        XCTAssertEqual(chunks[0].count, 19, "First chunk holds the 19 ASCII chars only")
        XCTAssertEqual(chunks[1].count, 2, "Second chunk holds the full surrogate pair")

        // Validate the pair: 0xD83D 0xDE42 = U+1F642 🙂
        XCTAssertTrue((0xD800...0xDBFF).contains(chunks[1][0]), "High surrogate first")
        XCTAssertTrue((0xDC00...0xDFFF).contains(chunks[1][1]), "Low surrogate second")
    }

    /// Stronger invariant: across any input + any chunk size, no chunk ever
    /// ends with a lone high surrogate or begins with a lone low surrogate.
    func testChunkUTF16_NeverProducesOrphanSurrogates() {
        let mixed = "Hello 🙂 мир 🚀 こんにちは 🎉 test"
        for limit in 2...10 {
            let chunks = TextSwitcher.chunkUTF16(mixed, maxCodeUnits: limit)
            for chunk in chunks {
                if let last = chunk.last {
                    XCTAssertFalse((0xD800...0xDBFF).contains(last),
                                   "Chunk ends with high surrogate at limit \(limit)")
                }
                if let first = chunk.first {
                    XCTAssertFalse((0xDC00...0xDFFF).contains(first),
                                   "Chunk starts with low surrogate at limit \(limit)")
                }
            }
        }
    }

    func testChunkUTF16_LosslessRoundTripWithNonBMP() {
        let original = "Hi 🙂🚀🎉 there"
        let chunks = TextSwitcher.chunkUTF16(original, maxCodeUnits: 4)
        let flat = chunks.flatMap { $0 }
        XCTAssertEqual(String(utf16CodeUnits: flat, count: flat.count), original)
    }

    /// The platform limit constant must match what we chunk at — guards
    /// against someone "optimizing" the chunker and forgetting the platform
    /// constraint.
    func testUnicodeChunkLimitMatchesPlatformConstraint() {
        XCTAssertEqual(TextSwitcher.unicodeChunkLimit, 20)
    }

    // MARK: - Modifier-release wait

    /// In a CI/test environment no hardware keys are held, so the wait must
    /// return immediately. Catches regressions where the function busy-waits
    /// or sleeps regardless of state.
    func testWaitForModifierRelease_ReturnsImmediatelyWhenNothingHeld() {
        let start = Date()
        let cleared = TextSwitcher.waitForModifierRelease(
            mask: [.maskCommand, .maskAlternate, .maskControl],
            timeout: 0.5,
            pollInterval: 0.01
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(cleared, "Should report success when modifiers are not held")
        XCTAssertLessThan(elapsed, 0.05,
                          "Should return well under the timeout when state is already clean")
    }

    /// An empty mask means "no modifiers are problematic", so we must
    /// short-circuit and never sleep.
    func testWaitForModifierRelease_EmptyMaskReturnsImmediately() {
        let start = Date()
        let cleared = TextSwitcher.waitForModifierRelease(
            mask: [],
            timeout: 0.5,
            pollInterval: 0.01
        )
        XCTAssertTrue(cleared)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.02)
    }

    // MARK: - Strategy routing

    func testPickStrategy_UsesSelectionReplaceByDefault() {
        XCTAssertEqual(
            TextSwitcher.pickStrategy(bundleID: "com.apple.Notes"),
            .selectionReplace
        )
        XCTAssertEqual(
            TextSwitcher.pickStrategy(bundleID: "com.tinyspeck.slackmacgap"),
            .selectionReplace,
            "Slack uses selection-replace: typing replaces the still-active Cmd+A selection"
        )
        XCTAssertEqual(
            TextSwitcher.pickStrategy(bundleID: "com.microsoft.VSCode"),
            .selectionReplace
        )
        XCTAssertEqual(
            TextSwitcher.pickStrategy(bundleID: "com.jetbrains.goland"),
            .selectionReplace
        )
    }

    func testPickStrategy_UsesBackspaceFloodForTerminals() {
        let terminals = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.github.wez.wezterm",
            "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty",
            "dev.warp.Warp-Stable"
        ]
        for bundle in terminals {
            XCTAssertEqual(
                TextSwitcher.pickStrategy(bundleID: bundle),
                .backspaceFlood,
                "\(bundle) needs backspace flood — shell input buffer doesn't track visual selection"
            )
        }
    }

    func testPickStrategy_UsesSelectionReplaceWhenBundleIDIsUnknown() {
        XCTAssertEqual(
            TextSwitcher.pickStrategy(bundleID: nil),
            .selectionReplace,
            "Unknown app defaults to the modern strategy"
        )
    }

    /// Hidden triage knob: `defaults write com.komandakycto.bilingual-switcher
    /// BILINGUAL_BACKEND backspaceFlood` forces the flood path in any app —
    /// useful when an unknown app gets the wrong default.
    func testPickStrategy_HonorsUserDefaultsOverride() {
        let key = "BILINGUAL_BACKEND"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set("backspaceFlood", forKey: key)
        XCTAssertEqual(
            TextSwitcher.pickStrategy(bundleID: "com.apple.Notes"),
            .backspaceFlood,
            "User override must force flood even in a non-terminal app"
        )

        UserDefaults.standard.set("selectionReplace", forKey: key)
        XCTAssertEqual(
            TextSwitcher.pickStrategy(bundleID: "com.apple.Terminal"),
            .selectionReplace,
            "User override must force selection-replace even in a terminal"
        )
    }

    func testPickStrategy_IgnoresGarbageOverrideValue() {
        let key = "BILINGUAL_BACKEND"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set("nonsense", forKey: key)
        XCTAssertEqual(
            TextSwitcher.pickStrategy(bundleID: "com.apple.Notes"),
            .selectionReplace,
            "Unrecognized override values must fall through to the bundle-ID heuristic"
        )
    }

    // MARK: - chunkUTF16 performance

    func testChunkUTF16_PerformanceOnLongMixedScriptText() {
        let unit = "Hello мир 🙂 "
        let text = String(repeating: unit, count: 200)  // ~2400 UTF-16 units
        measure { _ = TextSwitcher.chunkUTF16(text, maxCodeUnits: TextSwitcher.unicodeChunkLimit) }
    }

    // MARK: - snapshot / restore

    func testSnapshotOfEmptyClipboardReturnsEmpty() {
        pasteboard.clearContents()
        XCTAssertTrue(TextSwitcher.snapshot(of: pasteboard).isEmpty)
    }

    func testSnapshotAndRestoreRoundTripsPlainString() {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        let snapshot = TextSwitcher.snapshot(of: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("garbage", forType: .string)

        TextSwitcher.restoreClipboard(snapshot, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testSnapshotAndRestorePreservesMultiplePasteboardTypes() {
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setData(Data("{\\rtf1 hello}".utf8), forType: .rtf)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let snapshot = TextSwitcher.snapshot(of: pasteboard)
        pasteboard.clearContents()

        TextSwitcher.restoreClipboard(snapshot, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "plain")
        XCTAssertEqual(pasteboard.data(forType: .rtf), Data("{\\rtf1 hello}".utf8))
    }

    /// Regression for reviewer-found bug: an empty snapshot means the
    /// original clipboard was empty. After Cmd+C the clipboard holds the
    /// selected text; restoring must put it back into the empty state,
    /// not leave the selected text behind.
    func testRestoreOfEmptySnapshotClearsClipboard() {
        pasteboard.clearContents()
        pasteboard.setString("intermediate (post-Cmd+C content)", forType: .string)

        TextSwitcher.restoreClipboard([], to: pasteboard)

        XCTAssertNil(pasteboard.string(forType: .string),
                     "Empty snapshot must clear the pasteboard, not no-op")
    }

    // MARK: - pollForClipboardChange

    func testPollDetectsClipboardChange() {
        pasteboard.clearContents()
        let initial = pasteboard.changeCount

        let done = expectation(description: "polling completes")
        var result: Bool?

        TextSwitcher.pollForClipboardChange(
            initialChangeCount: initial,
            timeout: 1.0,
            pollInterval: 0.01,
            pasteboard: pasteboard
        ) { changed in
            result = changed
            done.fulfill()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [pasteboard] in
            pasteboard?.clearContents()
            pasteboard?.setString("simulated copy", forType: .string)
        }

        wait(for: [done], timeout: 2.0)
        XCTAssertEqual(result, true)
    }

    func testPollTimesOutWhenClipboardUnchanged() {
        pasteboard.clearContents()
        let initial = pasteboard.changeCount

        let done = expectation(description: "polling times out")
        var result: Bool?

        TextSwitcher.pollForClipboardChange(
            initialChangeCount: initial,
            timeout: 0.1,
            pollInterval: 0.01,
            pasteboard: pasteboard
        ) { changed in
            result = changed
            done.fulfill()
        }

        wait(for: [done], timeout: 1.0)
        XCTAssertEqual(result, false)
    }

    /// If the clipboard already differs from `initialChangeCount` when polling
    /// starts (e.g., the host filled it before our first read), the callback
    /// must fire immediately — not after one poll-interval tick.
    func testPollReturnsImmediatelyWhenClipboardAlreadyDifferent() {
        pasteboard.clearContents()
        pasteboard.setString("preexisting", forType: .string)
        let staleChangeCount = pasteboard.changeCount - 1

        let done = expectation(description: "polling returns immediately")
        var result: Bool?

        TextSwitcher.pollForClipboardChange(
            initialChangeCount: staleChangeCount,
            timeout: 5.0,
            pollInterval: 0.5,
            pasteboard: pasteboard
        ) { changed in
            result = changed
            done.fulfill()
        }

        wait(for: [done], timeout: 0.05)
        XCTAssertEqual(result, true)
    }
}
