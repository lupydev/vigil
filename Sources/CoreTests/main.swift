import Foundation

let status = TestRunner.run([
    LifetimeCpuRuleTests.suite,
    SustainedCpuRuleTests.suite,
    InMemorySampleStoreTests.suite,
    SwapPressureRuleTests.suite,
    DiskPressureRuleTests.suite,
    DiagnosticianTests.suite,
    SampleHistoryTests.suite,
    SampleCompactorTests.suite,
])

exit(status)
