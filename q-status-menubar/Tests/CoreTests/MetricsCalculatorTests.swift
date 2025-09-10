import XCTest
@testable import Core

final class MetricsCalculatorTests: XCTestCase {
    func testUsagePercent() {
        let calc = MetricsCalculator()
        XCTAssertEqual(calc.usagePercent(used: 2000, limit: 4000), 50.0)
        XCTAssertEqual(calc.usagePercent(used: 0, limit: 0), 0.0)
        XCTAssertEqual(calc.usagePercent(used: 5000, limit: 4000), 100.0)
    }
}

