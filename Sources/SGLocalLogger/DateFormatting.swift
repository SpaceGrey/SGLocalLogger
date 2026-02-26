import Foundation

struct DateFormatting {
    private let formatter: ISO8601DateFormatter

    init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
    }

    func timestampString(for date: Date) -> String {
        formatter.string(from: date)
    }
}
