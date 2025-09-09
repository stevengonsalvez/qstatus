import Foundation

public enum CostEstimator {
    public static func estimateUSD(tokens: Int, ratePer1k: Double) -> Double {
        return (Double(tokens) / 1000.0) * ratePer1k
    }
    public static func formatUSD(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

