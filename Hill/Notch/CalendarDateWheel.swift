import AppKit
import SwiftUI

struct CalendarDateWheel: View {
    @Binding var selectedDate: Date
    let accent: Color

    var body: some View {
        CalendarDateStrip(
            selectedDate: $selectedDate,
            accent: NSColor(accent)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CalendarDateStrip: NSViewRepresentable {
    @Binding var selectedDate: Date
    let accent: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CalendarDateScrollView {
        let view = CalendarDateScrollView()
        let coordinator = context.coordinator
        view.onDateChange = { date in
            coordinator.centerDateChanged(date)
        }
        view.accent = accent
        view.setSelectedDate(selectedDate, animated: false)
        return view
    }

    func updateNSView(
        _ nsView: CalendarDateScrollView,
        context: Context
    ) {
        context.coordinator.parent = self
        nsView.accent = accent
        nsView.setSelectedDate(selectedDate, animated: true)
    }

    final class Coordinator {
        var parent: CalendarDateStrip

        init(_ parent: CalendarDateStrip) {
            self.parent = parent
        }

        func centerDateChanged(_ date: Date) {
            guard !Calendar.current.isDate(
                date,
                inSameDayAs: parent.selectedDate
            ) else {
                return
            }
            parent.selectedDate = date
        }
    }
}

private final class CalendarDateScrollView: NSScrollView {
    var onDateChange: ((Date) -> Void)?
    var accent: NSColor = .systemBlue {
        didSet {
            document.accent = accent
            document.needsDisplay = true
        }
    }

    private let document = CalendarDateDocumentView()
    private let cellWidth: CGFloat = 42
    private var hasPositioned = false
    private var isSnapping = false
    private var isLiveScrolling = false
    private var hapticPending = false
    private var idleWorkItem: DispatchWorkItem?
    private var boundsObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .none
        autohidesScrollers = true
        documentView = document
        document.accent = accent
        setAccessibilityElement(true)
        setAccessibilityRole(.incrementor)
        setAccessibilityRoleDescription("日期滚轮")
        setAccessibilityLabel("日历日期")
        setAccessibilityHelp("使用“上一天”或“下一天”操作切换日期")

        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(liveScrollWillStart),
            name: NSScrollView.willStartLiveScrollNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(liveScrollDidEnd),
            name: NSScrollView.didEndLiveScrollNotification,
            object: self
        )
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            self?.boundsDidChange()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        idleWorkItem?.cancel()
    }

    override func layout() {
        super.layout()

        let inset = max(0, (contentView.bounds.width - cellWidth) / 2)
        let size = NSSize(
            width: inset * 2 + CGFloat(document.dayCount) * cellWidth,
            height: contentView.bounds.height
        )
        guard size.width > 0, size.height > 0 else { return }

        if document.frame.size != size || document.inset != inset {
            document.inset = inset
            document.frame = NSRect(origin: .zero, size: size)
        }

        if !hasPositioned {
            hasPositioned = true
        }
        if !isLiveScrolling && !isSnapping {
            idleWorkItem?.cancel()
            idleWorkItem = nil
            scroll(to: document.highlightIndex, animated: false)
        }
        document.viewportCenterX = contentView.bounds.midX
        document.needsDisplay = true
    }

    func setSelectedDate(_ date: Date, animated: Bool) {
        guard hasPositioned else {
            document.highlightIndex = document.index(for: date)
            document.needsDisplay = true
            return
        }

        let index = document.index(for: date)
        guard index != document.highlightIndex else { return }

        document.highlightIndex = index
        document.needsDisplay = true
        scroll(to: index, animated: animated)
        notifyAccessibilityDateChanged()
    }

    func select(index: Int) {
        guard hasPositioned, (0..<document.dayCount).contains(index)
        else { return }

        document.highlightIndex = index
        document.needsDisplay = true
        hapticPending = false
        onDateChange?(document.date(for: index))
        performHaptic()
        scroll(to: index, animated: true)
        notifyAccessibilityDateChanged()
    }

    override func accessibilityValue() -> Any? {
        document.date(for: document.highlightIndex).formatted(
            .dateTime.year().month().day().weekday(.wide)
        )
    }

    override func accessibilityPerformIncrement() -> Bool {
        selectAdjacentDate(offset: 1)
    }

    override func accessibilityPerformDecrement() -> Bool {
        selectAdjacentDate(offset: -1)
    }

    @objc private func liveScrollWillStart() {
        isLiveScrolling = true
    }

    @objc private func liveScrollDidEnd() {
        isLiveScrolling = false
    }

    private func boundsDidChange() {
        guard hasPositioned else { return }

        document.viewportCenterX = contentView.bounds.midX
        document.needsDisplay = true
        scheduleIdleSnap()

        let index = centerIndex()
        guard index != document.highlightIndex else { return }

        document.highlightIndex = index
        hapticPending = true
        onDateChange?(document.date(for: index))
        notifyAccessibilityDateChanged()
    }

    private func scheduleIdleSnap() {
        idleWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.idleWorkItem = nil
            self?.snapToNearestDay()
        }
        idleWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.12,
            execute: workItem
        )
    }

    private func snapToNearestDay() {
        guard hasPositioned, !isSnapping else { return }

        let index = centerIndex()
        let target = CGFloat(index) * cellWidth
        let origin = contentView.bounds.origin
        guard abs(origin.x - target) > 0.5 else {
            if hapticPending {
                hapticPending = false
                performHaptic()
            }
            return
        }

        isSnapping = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(
                name: .easeOut
            )
            contentView.animator().setBoundsOrigin(
                NSPoint(x: target, y: origin.y)
            )
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.contentView.setBoundsOrigin(
                NSPoint(x: target, y: origin.y)
            )
            self.isSnapping = false
            if self.hapticPending {
                self.hapticPending = false
                self.performHaptic()
            }
        }
    }

    private func scroll(to index: Int, animated: Bool) {
        let target = NSPoint(
            x: CGFloat(index) * cellWidth,
            y: contentView.bounds.origin.y
        )
        guard animated else {
            contentView.setBoundsOrigin(target)
            return
        }

        isSnapping = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(
                name: .easeOut
            )
            contentView.animator().setBoundsOrigin(target)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.contentView.setBoundsOrigin(target)
            self.isSnapping = false
        }
    }

    private func centerIndex() -> Int {
        let raw = contentView.bounds.origin.x / cellWidth
        return min(
            max(Int(raw.rounded()), 0),
            document.dayCount - 1
        )
    }

    private func performHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
    }

    private func selectAdjacentDate(offset: Int) -> Bool {
        let index = document.highlightIndex + offset
        guard (0..<document.dayCount).contains(index) else {
            return false
        }
        select(index: index)
        return true
    }

    private func notifyAccessibilityDateChanged() {
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
}

private final class CalendarDateDocumentView: NSView {
    let cellWidth: CGFloat = 42
    let dayCount = 731

    var inset: CGFloat = 0
    var highlightIndex = 365
    var viewportCenterX: CGFloat = 0
    var accent: NSColor = .systemBlue {
        didSet { needsDisplay = true }
    }

    private let calendar = Calendar.current
    private let baseDate: Date
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    private lazy var weekdayFont = NSFont.systemFont(
        ofSize: 8,
        weight: .medium
    )
    private lazy var dayFont = Self.roundedFont(
        size: 14,
        weight: .medium
    )
    private lazy var selectedDayFont = Self.roundedFont(
        size: 14,
        weight: .semibold
    )

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        let today = Calendar.current.startOfDay(for: Date())
        baseDate = Calendar.current.date(
            byAdding: .day,
            value: -365,
            to: today
        ) ?? today
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func index(for date: Date) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: baseDate,
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        return min(max(days, 0), dayCount - 1)
    }

    func date(for index: Int) -> Date {
        calendar.date(
            byAdding: .day,
            value: index,
            to: baseDate
        ) ?? baseDate
    }

    override func draw(_ dirtyRect: NSRect) {
        guard inset > 0, bounds.width > 0 else { return }

        let centerX = viewportCenterX
        let first = max(
            0,
            Int(((dirtyRect.minX - inset) / cellWidth).rounded(.down))
        )
        let last = min(
            dayCount - 1,
            Int(((dirtyRect.maxX - inset) / cellWidth).rounded(.up))
        )
        guard first <= last else { return }

        for index in first...last {
            let cellCenterX =
                inset + CGFloat(index) * cellWidth + cellWidth / 2
            let distance = abs(cellCenterX - centerX)
            let focus = max(0, 1 - distance / 88)
            drawCell(
                index: index,
                centerX: cellCenterX,
                focus: focus
            )
        }
    }

    private func drawCell(
        index: Int,
        centerX: CGFloat,
        focus: CGFloat
    ) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let scale = 0.7 + focus * 0.7
        let alpha = 0.5 + focus * 0.5
        let date = date(for: index)
        let isSelected = index == highlightIndex
        let isToday = calendar.isDateInToday(date)
        let middleY = bounds.height / 2

        context.saveGState()
        context.translateBy(x: centerX, y: middleY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -centerX, y: -middleY)
        defer { context.restoreGState() }

        let weekday = weekdaySymbols[
            min(
                max(calendar.component(.weekday, from: date) - 1, 0),
                weekdaySymbols.count - 1
            )
        ]
        let weekdayColor: NSColor =
            isSelected
                ? accent.withAlphaComponent(0.82 * alpha)
                : NSColor.white.withAlphaComponent(0.34 * alpha)
        draw(
            weekday,
            font: weekdayFont,
            color: weekdayColor,
            center: NSPoint(x: centerX, y: middleY - 15.5)
        )

        if isToday && !isSelected {
            let ring = NSBezierPath(
                ovalIn: NSRect(
                    x: centerX - 13,
                    y: middleY + 6.25 - 13,
                    width: 26,
                    height: 26
                )
            )
            ring.lineWidth = 0.8
            accent.withAlphaComponent(0.7 * alpha).setStroke()
            ring.stroke()
        }

        let dayColor: NSColor
        if isSelected || isToday {
            dayColor = accent.withAlphaComponent(alpha)
        } else {
            dayColor = NSColor.white.withAlphaComponent(0.72 * alpha)
        }
        draw(
            "\(calendar.component(.day, from: date))",
            font: isSelected ? selectedDayFont : dayFont,
            color: dayColor,
            center: NSPoint(x: centerX, y: middleY + 6.25)
        )
    }

    private func draw(
        _ text: String,
        font: NSFont,
        color: NSColor,
        center: NSPoint
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2
            ),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = min(
            max(Int((point.x - inset) / cellWidth), 0),
            dayCount - 1
        )

        highlightIndex = index
        needsDisplay = true
        (enclosingScrollView as? CalendarDateScrollView)?
            .select(index: index)
    }

    private static func roundedFont(
        size: CGFloat,
        weight: NSFont.Weight
    ) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded)
        else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}
