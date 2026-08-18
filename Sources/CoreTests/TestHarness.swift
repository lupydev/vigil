import Foundation

/// A dependency-free test harness.
///
/// XCTest and swift-testing both ship with full Xcode, and this machine has only
/// the Command Line Tools. Rather than drop the tests, the domain — which is
/// pure Swift by design — is exercised by a plain executable that exits non-zero
/// on failure, so it still works in a pre-commit hook or CI.
/// Installing Xcode makes `swift test` available and this can be retired.
final class Assertions {
    private(set) var failures: [String] = []

    func expect(_ condition: Bool, _ message: @autoclosure () -> String = "expectation failed", line: UInt = #line) {
        guard !condition else { return }
        failures.append("line \(line): \(message())")
    }

    func equal<T: Equatable>(_ actual: T?, _ expected: T?, line: UInt = #line) {
        guard actual != expected else { return }
        failures.append(
            "line \(line): expected \(String(describing: expected)), got \(String(describing: actual))"
        )
    }

    func isNil(_ value: Any?, line: UInt = #line) {
        guard value != nil else { return }
        failures.append("line \(line): expected nil, got \(String(describing: value!))")
    }
}

struct TestCase {
    let name: String
    let run: (Assertions) -> Void
}

struct Suite {
    let name: String
    let cases: [TestCase]
}

enum TestRunner {
    static func run(_ suites: [Suite]) -> Int32 {
        var passed = 0
        var failed = 0

        for suite in suites {
            print("\n\(suite.name)")
            for testCase in suite.cases {
                let assertions = Assertions()
                testCase.run(assertions)

                if assertions.failures.isEmpty {
                    passed += 1
                    print("  ✓ \(testCase.name)")
                } else {
                    failed += 1
                    print("  ✗ \(testCase.name)")
                    for failure in assertions.failures {
                        print("      \(failure)")
                    }
                }
            }
        }

        print("\n\(passed) passed, \(failed) failed\n")
        return failed == 0 ? 0 : 1
    }
}
