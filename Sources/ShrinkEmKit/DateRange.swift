import Foundation

public enum DateRange {
    public static var cal: Calendar { Calendar.current }
    public static func monthStart(_ d: Date) -> Date { cal.dateInterval(of: .month, for: d)?.start ?? d }
    public static func monthEnd(_ d: Date) -> Date { (cal.dateInterval(of: .month, for: d)?.end ?? d).addingTimeInterval(-1) }
    public static func dayStart(_ d: Date) -> Date { cal.startOfDay(for: d) }
    public static func dayEnd(_ d: Date) -> Date { cal.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart(d)) ?? d }
    public static func yearStart(_ y: Int) -> Date { cal.date(from: DateComponents(year: y, month: 1, day: 1))! }
    public static func yearEnd(_ y: Int) -> Date { yearStart(y + 1).addingTimeInterval(-1) }
    public static func ago(_ c: Calendar.Component, _ n: Int, from now: Date = Date()) -> Date { cal.date(byAdding: c, value: -n, to: now)! }

    /// Whether `date` falls in the optional, inclusive range.
    public static func contains(_ date: Date, from: Date?, to: Date?) -> Bool {
        (from == nil || date >= from!) && (to == nil || date <= to!)
    }

    /// Whether any part of `month` overlaps the optional range.
    public static func monthOverlaps(_ month: Date, from: Date?, to: Date?) -> Bool {
        (from == nil || monthEnd(month) >= from!) && (to == nil || monthStart(month) <= to!)
    }
}

/// Storage used by the videos of one month.
public struct MonthBucket: Identifiable, Equatable {
    public let month: Date
    public var bytes: Int64
    public var count: Int
    public var id: Date { month }
    public var gb: Double { Double(bytes) / 1_000_000_000 }

    /// Groups (date, bytes) pairs by month, oldest first. `.distantPast` (no date) is left out.
    public static func make<S: Sequence>(_ entries: S) -> [MonthBucket] where S.Element == (date: Date, bytes: Int64) {
        var map: [Date: MonthBucket] = [:]
        for e in entries where e.date != .distantPast {
            let m = DateRange.monthStart(e.date)
            map[m, default: MonthBucket(month: m, bytes: 0, count: 0)].bytes += e.bytes
            map[m, default: MonthBucket(month: m, bytes: 0, count: 0)].count += 1
        }
        return map.values.sorted { $0.month < $1.month }
    }
}
