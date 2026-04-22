import Foundation

enum LedgerFormat {
    private static let groupedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    static func number(_ value: Int) -> String {
        if abs(value) < 10_000 {
            return String(value)
        }
        return groupedFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
