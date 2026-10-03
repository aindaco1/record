import Foundation

public enum SessionSearch {
    public static func matches(
        _ query: String, title: String, startedAt: Date, calendar: Calendar = .current
    ) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !title.localizedCaseInsensitiveContains(query) else { return true }
        let date = calendar.dateComponents([.year, .month, .day], from: startedAt)
        let localDate = String(
            format: "%04d-%02d-%02d", date.year ?? 0, date.month ?? 0, date.day ?? 0)
        return localDate.contains(query)
    }
}
