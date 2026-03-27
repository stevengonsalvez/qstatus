import Testing
@testable import Core

@Suite("MetricsCalculator")
struct MetricsCalculatorTests {
    @Test func usagePercent() {
        let calc = MetricsCalculator()
        #expect(calc.usagePercent(used: 2000, limit: 4000) == 50.0)
        #expect(calc.usagePercent(used: 0, limit: 0) == 0.0)
        #expect(calc.usagePercent(used: 5000, limit: 4000) == 100.0)
    }
}
