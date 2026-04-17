import XCTest

// Standalone test runner for AddressSanitizer.
// XCTest's `xctest` tool is SIP-protected and strips DYLD_INSERT_LIBRARIES,
// so ASan can't intercept from a .xctest bundle. This runner compiles ASan
// directly into the executable, bypassing the issue.

@main
enum ASanRunner {
    static func main() {
        let testSuite = XCTestSuite.default
        testSuite.run()

        let result = testSuite.testRun!
        let passed = result.totalFailureCount == 0
        print("\(passed ? "✓" : "✗") \(result.executionCount) tests, \(result.totalFailureCount) failures")
        exit(passed ? 0 : 1)
    }
}
