import AppKit
import EventKit
import SwiftUI

private enum CalendarPixelTypography {
    static func font(size: CGFloat) -> Font {
        .system(size: size)
    }
}

private struct CalendarEventItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
    let calendarName: String
    let location: String?

    var timeLabel: String {
        if isAllDay {
            return "全天"
        }
        return start.formatted(
            .dateTime.hour().minute()
        )
    }
}

private enum CalendarAccessState: Equatable {
    case loading
    case granted
    case denied
    case failed(String)
}

@MainActor
private final class CalendarMonitor: ObservableObject {
    static let shared = CalendarMonitor()

    @Published private(set) var events: [CalendarEventItem] = []
    @Published private(set) var accessState: CalendarAccessState = .loading
    @Published var selectedDate = Date()

    private let store = EKEventStore()
    private var storeObserver: NSObjectProtocol?
    private let fetchQueue = DispatchQueue(
        label: "NotchMusic.calendarFetch",
        qos: .userInitiated
    )
    private var fetchGeneration = 0

    init() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reloadSelectedDate()
            }
        }
    }

    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }

    func load(for date: Date, requestsAccess: Bool = false) async {
        if !Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            events = []
        }
        selectedDate = date
        let status = EKEventStore.authorizationStatus(for: .event)

        if canReadEvents(status) {
            accessState = .granted
            fetchEvents(for: date)
            return
        }

        switch status {
        case .denied, .restricted, .writeOnly:
            events = []
            accessState = .denied
        case .notDetermined:
            guard requestsAccess else {
                events = []
                accessState = .loading
                return
            }
            accessState = .loading
            let result = await requestAccess()
            switch result {
            case .success(true):
                accessState = .granted
                fetchEvents(for: date)
            case .success(false):
                events = []
                accessState = .denied
            case .failure(let error):
                events = []
                accessState = .failed(error.localizedDescription)
            }
        default:
            events = []
            accessState = .failed("无法读取日历权限状态")
        }
    }

    private func reloadSelectedDate() async {
        await load(for: selectedDate)
    }

    private func canReadEvents(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }

    private func requestAccess() async -> Result<Bool, Error> {
        await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(granted))
                }
            }
        }
    }

    private func fetchEvents(for date: Date) {
        fetchGeneration &+= 1
        let generation = fetchGeneration
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            events = []
            return
        }
        let store = self.store

        fetchQueue.async { [weak self] in
            let predicate = store.predicateForEvents(
                withStart: start,
                end: end,
                calendars: nil
            )
            let matching = store.events(matching: predicate)

            Task { @MainActor [weak self] in
                guard let self,
                      self.fetchGeneration == generation else {
                    return
                }
                self.events = matching
                    .map { event in
                        CalendarEventItem(
                            id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                            title: event.title?.isEmpty == false
                                ? event.title
                                : "未命名日程",
                            start: event.startDate,
                            end: event.endDate,
                            isAllDay: event.isAllDay,
                            color: NSColor(cgColor: event.calendar.cgColor)
                                ?? .systemBlue,
                            calendarName: event.calendar.title,
                            location: event.location?.isEmpty == false
                                ? event.location
                                : nil
                        )
                    }
                    .sorted { lhs, rhs in
                        if lhs.isAllDay != rhs.isAllDay {
                            return lhs.isAllDay
                        }
                        return lhs.start < rhs.start
                    }
            }
        }
    }
}

@MainActor
enum CalendarPrefetch {
    static func start() {
        Task {
            await CalendarMonitor.shared.load(for: Date())
        }
    }
}

struct CalendarIslandView: View {
    let accent: Color
    let width: CGFloat

    @ObservedObject private var monitor = CalendarMonitor.shared
    @State private var eventLoadTask: Task<Void, Never>?
    @Environment(\.openURL) private var openURL

    private var selectedDate: Date {
        monitor.selectedDate
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { monitor.selectedDate },
            set: { monitor.selectedDate = $0 }
        )
    }

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter
    }()

    private let calendar = Calendar.current

    var body: some View {
        let monthWidth = min(max(width * 0.45, 186), 218)

        HStack(spacing: 11) {
            dateWheelPane
                .frame(width: monthWidth)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 0.5)

            eventPane
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                await monitor.load(
                    for: selectedDate,
                    requestsAccess: true
                )
            }
        }
        .onChange(of: selectedDate) { _, newDate in
            eventLoadTask?.cancel()
            eventLoadTask = Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                await monitor.load(for: newDate)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            Task {
                await monitor.load(for: selectedDate)
            }
        }
    }

    private var dateWheelPane: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text(Self.yearFormatter.string(from: selectedDate))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
                .contentTransition(.numericText())
                .animation(
                    .easeInOut(duration: 0.16),
                    value: calendar.component(.year, from: selectedDate)
                )

            Spacer(minLength: 0)

            Text(Self.monthFormatter.string(from: selectedDate))
                .font(CalendarPixelTypography.font(size: 30))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(
                    .easeInOut(duration: 0.16),
                    value: calendar.component(.month, from: selectedDate)
                )

            Spacer(minLength: 0)

            CalendarDateWheel(
                selectedDate: selectedDateBinding,
                accent: accent
            )
            .frame(height: 58)
            .padding(.vertical, -7)
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var eventPane: some View {
        eventContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(
                .easeOut(duration: 0.18),
                value: monitor.accessState
            )
            .animation(
                .easeOut(duration: 0.18),
                value: monitor.events.count
            )
    }

    @ViewBuilder
    private var eventContent: some View {
        switch monitor.accessState {
        case .loading:
            VStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .tint(accent)
                Text("正在读取日历")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .denied:
            VStack(spacing: 5) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Text("需要日历访问权限")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                Button("打开系统设置") {
                    openCalendarPrivacySettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.45))
                Text(message)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task {
                        await monitor.load(
                            for: selectedDate,
                            requestsAccess: true
                        )
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .granted:
            if monitor.events.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white.opacity(0.38))
                    Text("暂无日程")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(monitor.events) { event in
                            eventRow(event)
                        }
                    }
                    .padding(.top, 1)
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func eventRow(_ event: CalendarEventItem) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color(nsColor: event.color))
                .frame(width: 2.5, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                HStack(spacing: 3) {
                    Text(event.timeLabel)
                    Text("·")
                    Text(event.calendarName)
                        .lineLimit(1)
                }
                .font(.system(size: 7.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.38))
            }

            Spacer(minLength: 2)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(height: 31)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .help(event.location ?? event.title)
    }

    private func openCalendarPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else {
            return
        }
        openURL(url)
    }
}

private struct CalendarDateWheel: View {
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
