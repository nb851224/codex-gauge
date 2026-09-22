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
    private var hoverCloseTimer: Timer?
    private var hoverExitDeadline: Date?
    private static let statusItemAutosaveName = "CodexGauge.StatusItem"

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        prepareStatusItemPosition()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Self.statusItemAutosaveName
        guard let button = item.button else {
            logger.error("Unable to create status bar button")
            return
        }

        button.imagePosition = .imageOnly
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
                self?.closePopover()
            }
        }

        startHoverCloseTimer()

        logger.info("Status item ready")
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let remaining = usage.remainingPercent
        let remainingTime = usage.cycleRemainingPercent
        button.image = makeUsageRingIcon(remaining: remaining, remainingTime: remainingTime)
        button.title = ""
        if let remaining, let remainingTime {
            button.toolTip = L10n.format(
                "tooltip_details",
                remaining,
                remainingTime,
                usage.resetText
            )
        } else {
            button.toolTip = L10n.text("tooltip_usage")
        }
    }

    private func prepareStatusItemPosition() {
        let defaults = UserDefaults.standard
        let positionKey = "NSStatusItem Preferred Position \(Self.statusItemAutosaveName)"
        guard defaults.object(forKey: positionKey) == nil else { return }

        // Seed only this app's first position. AppKit owns subsequent changes,
        // including positions chosen by Command-dragging the status item.
        defaults.set(0, forKey: positionKey)
    }

    private func makeUsageRingIcon(remaining: Int?, remainingTime: Int?) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let startAngle: CGFloat = 90

        drawTimeSector(
            center: center,
            radius: 5.7,
            percent: remainingTime,
            startAngle: startAngle
        )
        drawUsageTrack(center: center, radius: 7.6, lineWidth: 1.7)
        drawUsageArc(
            center: center,
            radius: 7.6,
            lineWidth: 1.7,
            percent: remaining,
            startAngle: startAngle
        )

        drawCenteredPercentage(remaining, in: size)

        image.unlockFocus()
        image.isTemplate = true
        if let remaining, let remainingTime {
            image.accessibilityDescription = L10n.format(
                "accessibility_details",
                remaining,
                remainingTime
            )
        } else {
            image.accessibilityDescription = L10n.text("accessibility_gauge")
        }
        return image
    }

    private func drawCenteredPercentage(_ percent: Int?, in size: NSSize) {
        let text = percent.map(String.init) ?? "--"
        let fontSize: CGFloat = text.count <= 2 ? 7.5 : 5.9
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 + 0.2
        ))
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
        hoverCloseTimer?.invalidate()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        logger.info("Status item clicked; shown=\(self.popover.isShown, privacy: .public)")
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(relativeTo: sender)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        usage.refresh()
        openedAt = Date()
        hoverExitDeadline = nil
        let anchor = button.bounds.insetBy(dx: 2, dy: 0)
        popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)
    }

    private func closePopover(_ sender: Any? = nil) {
        popover.performClose(sender)
        openedAt = nil
        hoverExitDeadline = nil
    }

    private func startHoverCloseTimer() {
        hoverCloseTimer?.invalidate()
        hoverCloseTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateHoverState()
            }
        }
    }

    private func handlePointerMovement() {
        let pointer = NSEvent.mouseLocation
        guard let button = statusItem?.button, let statusFrame = button.window?.frame else { return }

        if statusFrame.insetBy(dx: -3, dy: -3).contains(pointer) {
            hoverExitDeadline = nil
            if !popover.isShown {
                showPopover(relativeTo: button)
            }
        } else if popover.contentViewController?.view.window?.frame.insetBy(dx: -4, dy: -6).contains(pointer) == true {
            hoverExitDeadline = nil
        } else if popover.isShown, hoverExitDeadline == nil {
            hoverExitDeadline = Date().addingTimeInterval(0.22)
        }
    }

    private func updateHoverState() {
        handlePointerMovement()
        guard popover.isShown else { return }

        let pointer = NSEvent.mouseLocation
        let statusFrame = statusItem?.button?.window?.frame.insetBy(dx: -3, dy: -3)
        let popoverFrame = popover.contentViewController?.view.window?.frame.insetBy(dx: -4, dy: -6)
        if statusFrame?.contains(pointer) == true || popoverFrame?.contains(pointer) == true {
            hoverExitDeadline = nil
            return
        }

        if hoverExitDeadline == nil {
            hoverExitDeadline = Date().addingTimeInterval(0.22)
        } else if let deadline = hoverExitDeadline, Date() >= deadline {
            closePopover()
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
                Text(L10n.text("tagline"))
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
                .help(L10n.text("back_to_usage"))
            }

            Menu {
                Button(L10n.text("refresh")) {
                    usage.refresh()
                }
                Button(L10n.text("quit_app")) {
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
                    Text(L10n.text("future_available"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(L10n.text("weekly_average"))
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
                    title: L10n.text("quota_5_hour"),
                    remainingPercent: usage.shortRemainingPercent,
                    resetText: usage.shortResetText,
                    exactText: usage.shortResetExactText,
                    tint: .blue
                )
                QuotaCard(
                    title: L10n.text("quota_weekly"),
                    remainingPercent: usage.remainingPercent,
                    resetText: L10n.format("reset_suffix", usage.resetText),
                    exactText: usage.resetExactText,
                    tint: .purple
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        } else {
            QuotaCard(
                title: usage.windowDurationMinutes == 10_080
                    ? L10n.text("quota_weekly")
                    : L10n.text("quota_current"),
                remainingPercent: usage.remainingPercent,
                resetText: L10n.format("reset_suffix", usage.resetText),
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
                    Text(L10n.text("reset_cards"))
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
            Text(L10n.text("tagline"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 17)
        .frame(height: 34)
    }

    private var resetCardsDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("reset_cards"))
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Text(usage.resetCreditCount.map { L10n.format("available_count", $0) } ?? L10n.text("no_data"))
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
                                Text(credit.title ?? L10n.text("default_card_title"))
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
                Text(L10n.text("sync_cards_on_open"))
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
                Text(L10n.text("calculating_daily"))
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
        if budget.isToday { return L10n.text("today") }
        return budget.date.formatted(
            .dateTime.locale(L10n.locale).weekday(.abbreviated)
        )
    }

    private var dateText: String {
        budget.date.formatted(
            .dateTime.locale(L10n.locale).month(.defaultDigits).day(.defaultDigits)
        )
    }
}
