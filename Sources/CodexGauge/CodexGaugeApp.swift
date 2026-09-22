import AppKit
import Combine
import OSLog
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.eric.codex-gauge", category: "ui")
    private let usage = UsageViewModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var observation: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var openedAt: Date?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else {
            logger.error("Unable to create status bar button")
            return
        }

        button.imagePosition = .imageLeading
        button.imageScaling = .scaleNone
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        button.toolTip = "Codex Gauge"
        statusItem = item
        updateStatusItem()

        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 374, height: 430)
        popover.contentViewController = NSHostingController(rootView: GaugePopover(usage: usage))

        observation = usage.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.popover.isShown == true else { return }
                if let openedAt = self?.openedAt,
                   Date().timeIntervalSince(openedAt) < 0.25 {
                    return
                }
                self?.popover.performClose(nil)
            }
        }

        logger.info("Status item ready")
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let remaining = usage.remainingPercent
        let remainingTime = usage.cycleRemainingPercent
        button.image = makeUsageRingIcon(remaining: remaining, remainingTime: remainingTime)
        button.title = usage.menuTitle
        if let remaining, let remainingTime {
            button.toolTip = "外圈：剩余用量 \(remaining)%  ·  扇形：剩余时间 \(remainingTime)%  ·  \(usage.resetText)重置"
        } else {
            button.toolTip = "Codex 用量"
        }
    }

    private func makeUsageRingIcon(remaining: Int?, remainingTime: Int?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let startAngle: CGFloat = 90

        drawTimeSector(
            center: center,
            radius: 4.7,
            percent: remainingTime,
            startAngle: startAngle
        )
        drawUsageTrack(center: center, radius: 6.7, lineWidth: 1.9)
        drawUsageArc(
            center: center,
            radius: 6.7,
            lineWidth: 1.9,
            percent: remaining,
            startAngle: startAngle
        )

        if remaining == nil || remainingTime == nil {
            let dot = NSBezierPath(ovalIn: NSRect(x: 7.8, y: 7.8, width: 2.4, height: 2.4))
            NSColor.black.setFill()
            dot.fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        if let remaining, let remainingTime {
            image.accessibilityDescription = "剩余用量 \(remaining)%，剩余时间 \(remainingTime)%"
        } else {
            image.accessibilityDescription = "Codex 用量比例"
        }
        return image
    }

    private func drawTimeSector(
        center: NSPoint,
        radius: CGFloat,
        percent: Int?,
        startAngle: CGFloat
    ) {
        guard let percent else { return }
        let fraction = CGFloat(min(100, max(0, percent))) / 100
        guard fraction > 0 else { return }

        let sector = NSBezierPath()
        sector.move(to: center)
        sector.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: startAngle - 360 * fraction,
            clockwise: true
        )
        sector.close()
        NSColor.black.withAlphaComponent(0.22).setFill()
        sector.fill()
    }

    private func drawUsageTrack(center: NSPoint, radius: CGFloat, lineWidth: CGFloat) {
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.black.withAlphaComponent(0.16).setStroke()
        track.stroke()
    }

    private func drawUsageArc(
        center: NSPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        percent: Int?,
        startAngle: CGFloat
    ) {
        guard let percent else { return }
        let fraction = CGFloat(min(100, max(0, percent))) / 100
        guard fraction > 0 else { return }

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: startAngle - 360 * fraction,
            clockwise: true
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        NSColor.black.setStroke()
        arc.stroke()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        logger.info("Status item clicked; shown=\(self.popover.isShown, privacy: .public)")
        if popover.isShown {
            popover.performClose(sender)
            openedAt = nil
        } else {
            usage.refresh()
            openedAt = Date()
            let anchor = sender.bounds.insetBy(dx: 2, dy: 0)
            popover.show(relativeTo: anchor, of: sender, preferredEdge: .minY)
        }
    }
}

private struct GaugePopover: View {
    @ObservedObject var usage: UsageViewModel
    @State private var showResetCards = false

    private let accentColor = Color.blue

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if showResetCards {
                resetCardsDetail
                    .transition(.opacity)
            } else {
                overview
                    .transition(.opacity)
            }
        }
        .frame(width: 374, height: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            usage.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text("Codex")
                        .font(.system(size: 19, weight: .bold))
                    Text(usage.planLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
                Text("专注创作，少些顾虑。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if showResetCards {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showResetCards = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("返回用量")
            }

            Menu {
                Button("刷新") {
                    usage.refresh()
                }
                Button("退出 Codex Gauge") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 12)
    }

    private var overview: some View {
        VStack(spacing: 0) {
            quotaSummary

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text("未来可用")
                        .font(.system(size: 12, weight: .semibold))
                    Text("（按周额度平均）")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                DailyBudgetChart(budgets: usage.dailyBudgets, accentColor: accentColor)
                    .frame(height: 91)
            }
            .padding(.horizontal, 13)
            .padding(.top, 9)
            .padding(.bottom, 7)

            Divider()

            resetCardRow

            Divider()

            refreshFooter
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var quotaSummary: some View {
        if usage.usesDualQuotaLayout {
            HStack(spacing: 8) {
                QuotaCard(
                    title: "5小时额度",
                    remainingPercent: usage.shortRemainingPercent,
                    resetText: usage.shortResetText,
                    exactText: usage.shortResetExactText,
                    tint: .blue
                )
                QuotaCard(
                    title: "周额度",
                    remainingPercent: usage.remainingPercent,
                    resetText: "\(usage.resetText)重置",
                    exactText: usage.resetExactText,
                    tint: .purple
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        } else {
            QuotaCard(
                title: usage.windowDurationMinutes == 10_080 ? "周额度" : "当前额度",
                remainingPercent: usage.remainingPercent,
                resetText: "\(usage.resetText)重置",
                exactText: usage.resetExactText,
                tint: accentColor,
                expanded: true
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var resetCardRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                showResetCards = true
            }
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 54, height: 44)
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(accentColor.opacity(0.78))
                        .frame(width: 54, height: 44)

                    if let count = usage.resetCreditCount, count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(accentColor, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("重置卡")
                        .font(.system(size: 14, weight: .semibold))
                    Text(usage.resetCreditSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 17)
        .frame(maxHeight: .infinity)
    }

    private var refreshFooter: some View {
        HStack {
            Button {
                usage.refresh()
            } label: {
                Label(usage.relativeUpdateText, systemImage: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
            Text("Focus on what matters.")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 17)
        .frame(height: 34)
    }

    private var resetCardsDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("重置卡")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Text(usage.resetCreditCount.map { "\($0) 张可用" } ?? "暂无数据")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if usage.resetCredits.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(usage.resetCreditEmptyTitle)
                        .font(.system(size: 14, weight: .semibold))
                    Text(usage.resetCreditSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(usage.resetCredits) { credit in
                        HStack(spacing: 11) {
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundStyle(accentColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(credit.title ?? "Codex 重置卡")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(usage.expirationText(for: credit))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 11)
                        if credit.id != usage.resetCredits.last?.id {
                            Divider()
                                .padding(.leading, 35)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            }

            Spacer(minLength: 0)

            HStack {
                Text("开启面板时会同步最新数量")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    usage.refresh()
                } label: {
                    Label(usage.relativeUpdateText, systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(17)
        .frame(maxHeight: .infinity)
    }
}

private struct QuotaCard: View {
    let title: String
    let remainingPercent: Int?
    let resetText: String
    let exactText: String
    let tint: Color
    var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))

            HStack(alignment: .firstTextBaseline, spacing: expanded ? 18 : 8) {
                Text(remainingPercent.map { "\($0)%" } ?? "--")
                    .font(.system(size: expanded ? 41 : 32, weight: .bold, design: .rounded))
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: 2) {
                    Text(resetText)
                        .font(.system(size: expanded ? 13 : 10, weight: .semibold))
                        .lineLimit(1)
                    Text(exactText)
                        .font(.system(size: expanded ? 11 : 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ProgressView(value: Double(remainingPercent ?? 0), total: 100)
                .progressViewStyle(.linear)
                .tint(tint)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
        .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct DailyBudgetChart: View {
    let budgets: [DailyBudget]
    let accentColor: Color

    var body: some View {
        if budgets.isEmpty {
            HStack {
                Spacer()
                Text("正在计算每日额度")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            let maximum = max(budgets.map(\.percent).max() ?? 0, 1)
            HStack(alignment: .top, spacing: 5) {
                ForEach(budgets) { budget in
                    DailyBudgetBar(
                        budget: budget,
                        maximum: maximum,
                        color: budget.isToday ? accentColor : accentColor.opacity(0.36)
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct DailyBudgetBar: View {
    let budget: DailyBudget
    let maximum: Double
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Int(budget.percent.rounded()))%")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.09))
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(height: max(4, 43 * budget.percent / maximum))
            }
            .frame(width: 27, height: 43)

            Text(dayText)
                .font(.system(size: 10, weight: budget.isToday ? .semibold : .medium))
                .foregroundStyle(budget.isToday ? Color.primary : Color.secondary)
            Text(dateText)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var dayText: String {
        if budget.isToday { return "今天" }
        return budget.date.formatted(
            .dateTime.locale(Locale(identifier: "zh_CN")).weekday(.abbreviated)
        )
    }

    private var dateText: String {
        budget.date.formatted(
            .dateTime.locale(Locale(identifier: "zh_CN")).month(.defaultDigits).day(.defaultDigits)
        )
    }
}
