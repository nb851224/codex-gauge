import Foundation

struct UsageSample: Codable, Equatable {
    let collectedAt: Date
    let usedPercent: Int
    let resetsAt: Date
}

struct DailyBudget: Identifiable, Equatable {
    let date: Date
    let percent: Double
    let isToday: Bool

    var id: Date { date }
}

enum DailyBudgetAllocator {
    static func allocate(
        remainingPercent: Double,
        now: Date,
        resetDate: Date,
        calendar: Calendar
    ) -> [DailyBudget] {
        guard resetDate > now, remainingPercent >= 0 else { return [] }

        let totalDuration = resetDate.timeIntervalSince(now)
        var cursor = now
        var result: [DailyBudget] = []

        while cursor < resetDate, result.count < 7 {
            let day = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let segmentEnd = min(nextDay, resetDate)
            let share = segmentEnd.timeIntervalSince(cursor) / totalDuration
            result.append(
                DailyBudget(
                    date: day,
                    percent: remainingPercent * share,
                    isToday: calendar.isDate(day, inSameDayAs: now)
                )
            )
            cursor = segmentEnd
        }
        return result
    }
}

enum DurationText {
    static func compact(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "\(days)天\(hours)小时" : "\(days)天"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)小时\(minutes)分钟" : "\(hours)小时"
        }
        return "\(minutes)分钟"
    }
}
