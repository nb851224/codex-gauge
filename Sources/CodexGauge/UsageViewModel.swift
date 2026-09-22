import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var remainingPercent: Int?
    @Published private(set) var resetDate: Date?
    @Published private(set) var windowDurationMinutes: Int?
    @Published private(set) var resetCreditCount: Int?
    @Published private(set) var resetCredits: [ResetCredit] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    private let client = CodexAppServerClient()
    private let defaults = UserDefaults.standard
    private var samples: [UsageSample] = []
    private var refreshTimer: Timer?
    private var retryTimer: Timer?

    var menuTitle: String {
        guard let remainingPercent else { return "--" }
        return "\(remainingPercent)%"
    }

    var cycleRemainingPercent: Int? {
        guard
            let resetDate,
            let windowDurationMinutes,
            windowDurationMinutes > 0
        else { return nil }

        let duration = TimeInterval(windowDurationMinutes * 60)
        let remainingTime = max(0, resetDate.timeIntervalSinceNow)
        return Int((min(1, remainingTime / duration) * 100).rounded())
    }

    var resetText: String {
        guard let resetDate else { return "--" }
        let remaining = resetDate.timeIntervalSinceNow
        return remaining <= 0 ? "即将重置" : "\(DurationText.compact(remaining))后"
    }

    var resetExactText: String {
        guard let resetDate else { return "--" }
        return resetDate.formatted(
            .dateTime
                .locale(Locale(identifier: "zh_CN"))
                .month(.defaultDigits)
                .day(.defaultDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }

    var refreshStatusText: String {
        if errorMessage != nil { return "连接异常" }
        return isRefreshing ? "更新中" : "已更新"
    }

    var lastUpdatedText: String {
        guard let lastUpdated else { return "--:--" }
        return lastUpdated.formatted(date: .omitted, time: .shortened)
    }

    var dailyAllowanceText: String {
        guard
            let remainingPercent,
            let resetDate
        else { return "-- / 24小时" }

        let hours = resetDate.timeIntervalSinceNow / 3_600
        guard hours > 0 else { return "-- / 24小时" }
        let allowance = min(100, Double(remainingPercent) * 24 / hours)
        return String(format: "%.1f%% / 24小时", allowance)
    }

    var recent24HourUsedPercent: Int? {
        let cycleSamples = samplesForCurrentCycle()
        guard cycleSamples.count >= 2, let first = cycleSamples.first, let last = cycleSamples.last else {
            return nil
        }
        return max(0, last.usedPercent - first.usedPercent)
    }

    var todayUsedPercent: Int? {
        guard let resetDate else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: Date())
        let todaySamples = samples
            .filter {
                abs($0.resetsAt.timeIntervalSince(resetDate)) < 60 &&
                $0.collectedAt >= startOfToday
            }
            .sorted { $0.collectedAt < $1.collectedAt }

        guard todaySamples.count >= 2, let first = todaySamples.first, let last = todaySamples.last else {
            return nil
        }
        return max(0, last.usedPercent - first.usedPercent)
    }

    var dailyBudgets: [DailyBudget] {
        guard
            let remainingPercent,
            let resetDate
        else { return [] }
        return DailyBudgetAllocator.allocate(
            remainingPercent: Double(remainingPercent),
            now: Date(),
            resetDate: resetDate,
            calendar: .autoupdatingCurrent
        )
    }

    var allocationSummary: String {
        if let todayUsedPercent {
            return "按剩余额度分配 · 今日已用 \(todayUsedPercent)%"
        }
        return "按剩余额度分配 · 今日数据收集中"
    }

    var relativeUpdateText: String {
        if errorMessage != nil { return "更新失败" }
        guard let lastUpdated else { return "正在更新" }
        let minutes = max(0, Int(Date().timeIntervalSince(lastUpdated) / 60))
        return minutes < 1 ? "刚刚更新" : "\(minutes)分钟前更新"
    }

    var resetCreditSubtitle: String {
        guard let resetCreditCount else {
            return "当前账户未提供重置卡信息"
        }
        guard resetCreditCount > 0 else {
            return "暂无可用重置卡"
        }
        if let expiration = resetCredits.compactMap(\.expiresAt).min() {
            let text = expiration.formatted(
                .dateTime
                    .locale(Locale(identifier: "zh_CN"))
                    .month(.defaultDigits)
                    .day(.defaultDigits)
                    .hour(.twoDigits(amPM: .omitted))
                    .minute(.twoDigits)
            )
            return "\(text) 最早过期"
        }
        return "\(resetCreditCount) 张可用"
    }

    var resetCreditEmptyTitle: String {
        resetCreditCount == nil ? "无重置卡信息" : "暂无可用重置卡"
    }

    func expirationText(for credit: ResetCredit) -> String {
        guard let expiresAt = credit.expiresAt else { return "无过期时间" }
        return expiresAt.formatted(
            .dateTime
                .locale(Locale(identifier: "zh_CN"))
                .year()
                .month(.defaultDigits)
                .day(.defaultDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        ) + " 过期"
    }

    var hourlyUsageBars: [Double] {
        let cycleSamples = samplesForCurrentCycle()
        guard let latest = cycleSamples.last else {
            return Array(repeating: 0, count: 24)
        }

        var bars = Array(repeating: 0.0, count: 24)
        for pair in zip(cycleSamples, cycleSamples.dropFirst()) {
            let delta = max(0, pair.1.usedPercent - pair.0.usedPercent)
            let hoursAgo = Int(latest.collectedAt.timeIntervalSince(pair.1.collectedAt) / 3_600)
            guard hoursAgo >= 0, hoursAgo < 24 else { continue }
            bars[23 - hoursAgo] += Double(delta)
        }
        return bars
    }

    init() {
        loadHistory()
        client.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in
                self?.accept(snapshot)
            }
        }
        client.onError = { [weak self] message in
            Task { @MainActor in
                self?.errorMessage = message
                self?.isRefreshing = false
                self?.scheduleRetry()
            }
        }
        start()
    }

    func start() {
        client.start()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.client.refresh()
            }
        }
    }

    func refresh() {
        errorMessage = nil
        isRefreshing = true
        client.refresh()
    }

    private func accept(_ snapshot: RateLimitSnapshot) {
        errorMessage = nil
        isRefreshing = false
        let sample = UsageSample(
            collectedAt: Date(),
            usedPercent: snapshot.usedPercent,
            resetsAt: snapshot.resetsAt
        )

        samples = samples.filter {
            sample.collectedAt.timeIntervalSince($0.collectedAt) <= 30 * 24 * 60 * 60
        }
        samples.append(sample)
        saveHistory()

        remainingPercent = 100 - snapshot.usedPercent
        resetDate = snapshot.resetsAt
        windowDurationMinutes = snapshot.windowDurationMinutes
        resetCreditCount = snapshot.resetCredits?.availableCount
        resetCredits = snapshot.resetCredits?.credits ?? []
        lastUpdated = sample.collectedAt
    }

    private func samplesForCurrentCycle() -> [UsageSample] {
        guard let resetDate else { return [] }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return samples
            .filter {
                abs($0.resetsAt.timeIntervalSince(resetDate)) < 60 &&
                $0.collectedAt >= cutoff
            }
            .sorted { $0.collectedAt < $1.collectedAt }
    }

    private func loadHistory() {
        guard let data = defaults.data(forKey: "usage.samples") else { return }
        samples = (try? JSONDecoder().decode([UsageSample].self, from: data)) ?? []
        guard
            let latest = samples.max(by: { $0.collectedAt < $1.collectedAt }),
            latest.resetsAt > Date()
        else { return }

        remainingPercent = 100 - latest.usedPercent
        resetDate = latest.resetsAt
        lastUpdated = latest.collectedAt
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        defaults.set(data, forKey: "usage.samples")
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.client.refresh()
            }
        }
    }
}
