import Foundation

private func checkResponseParsing() {
    let response: [String: Any] = [
        "rateLimitsByLimitId": [
            "codex": [
                "primary": [
                    "usedPercent": 16,
                    "windowDurationMins": 10_080,
                    "resetsAt": NSNumber(value: 1_790_412_303)
                ]
            ]
        ],
        "rateLimitResetCredits": [
            "availableCount": NSNumber(value: 1),
            "credits": [[
                "id": "credit-1",
                "status": "available",
                "title": "重置卡",
                "description": "重置 Codex 用量",
                "expiresAt": NSNumber(value: 1_790_400_000),
                "grantedAt": NSNumber(value: 1_780_000_000),
                "resetType": "codexRateLimits"
            ]]
        ]
    ]

    let snapshot = CodexAppServerClient.parseSnapshot(response)
    precondition(snapshot?.usedPercent == 16)
    precondition(snapshot?.windowDurationMinutes == 10_080)
    precondition(snapshot?.resetsAt.timeIntervalSince1970 == 1_790_412_303)
    precondition(snapshot?.resetCredits?.availableCount == 1)
    precondition(snapshot?.resetCredits?.credits.first?.id == "credit-1")

    let fallbackResponse: [String: Any] = [
        "rateLimitsByLimitId": ["codex": ["primary": NSNull()]],
        "rateLimits": [
            "primary": [
                "usedPercent": NSNumber(value: 24.0),
                "windowDurationMins": NSNumber(value: 10_080),
                "resetsAt": NSNumber(value: 1_790_412_303)
            ]
        ]
    ]
    precondition(CodexAppServerClient.parseSnapshot(fallbackResponse)?.usedPercent == 24)
}

private func checkDailyBudgetAllocation() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12))!
    let reset = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 0))!
    let budgets = DailyBudgetAllocator.allocate(
        remainingPercent: 80,
        now: now,
        resetDate: reset,
        calendar: calendar
    )

    precondition(budgets.count == 2)
    precondition(abs(budgets.map(\.percent).reduce(0, +) - 80) < 0.001)
    precondition(budgets[0].isToday)
    precondition(abs(budgets[0].percent * 2 - budgets[1].percent) < 0.001)
}

checkResponseParsing()
checkDailyBudgetAllocation()
print("All Codex Gauge checks passed.")
