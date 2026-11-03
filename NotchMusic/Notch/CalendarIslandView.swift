import AppKit
import EventKit
import SwiftUI

private enum CalendarPixelTypography {
    static let pixel = "Fusion-Pixel-12px-Prop-zh-Hans-Regular"

    static func font(size: CGFloat) -> Font {
        .custom(pixel, fixedSize: size)
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
    @Published private(set) var events: [CalendarEventItem] = []
    @Published private(set) var accessState: CalendarAccessState = .loading

    private let store = EKEventStore()
    private var selectedDate = Date()
    private var storeObserver: NSObjectProtocol?

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
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            events = []
            return
        }

        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )

        events = store.events(matching: predicate)
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

struct CalendarIslandView: View {
    let accent: Color

    @StateObject private var monitor = CalendarMonitor()
    @State private var selectedDate = Date()
    @Environment(\.openURL) private var openURL

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

    private static let selectedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private let calendar = Calendar.current

    var body: some View {
        GeometryReader { geometry in
            let monthWidth = min(
                max(geometry.size.width * 0.45, 186),
                218
            )

            HStack(spacing: 11) {
                dateWheelPane
                    .frame(width: monthWidth)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 0.5)

                eventPane
                    .frame(maxWidth: .infinity)
            }
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
            Task {
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

            Spacer(minLength: 0)

            Text(Self.monthFormatter.string(from: selectedDate))
                .font(CalendarPixelTypography.font(size: 30))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Spacer(minLength: 0)

            CalendarDateWheel(
                selectedDate: $selectedDate,
                accent: accent
            )
            .frame(height: 44)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.16), value: selectedDate)
    }

    private var eventPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(selectedDateTitle)
                    .font(
                        .system(
                            size: 10.5,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 2)

                if monitor.accessState == .granted,
                   !monitor.events.isEmpty {
                    Text("\(monitor.events.count) 项")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(height: 17)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            eventContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
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

    private var selectedDateTitle: String {
        if calendar.isDateInToday(selectedDate) {
            return "今天 · " + Self.monthDayFormatter.string(
                from: selectedDate
            )
        }
        return Self.selectedDateFormatter.string(
            from: selectedDate
        )
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

    @State private var scrollPosition: Int?
    @State private var hasAppeared = false

    private let calendar = Calendar.current
    private let cellWidth: CGFloat = 42
    private let pastDays = 365
    private let futureDays = 365
    private let spacerCount = 2

    var body: some View {
        GeometryReader { geometry in
            let sidePadding = max(
                0,
                (geometry.size.width - cellWidth) / 2
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<totalItemCount, id: \.self) { index in
                        if isDateIndex(index) {
                            dateButton(
                                date: dateForItemIndex(index),
                                index: index
                            )
                            .id(index)
                        } else {
                            Color.clear
                                .frame(width: cellWidth, height: 1)
                                .id(index)
                        }
                    }
                }
                .frame(height: 44)
                .scrollTargetLayout()
            }
            .scrollIndicators(.never)
            .safeAreaPadding(.horizontal, sidePadding)
            .scrollPosition(id: $scrollPosition, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        selectDate(
                            at: value.location.x,
                            width: geometry.size.width
                        )
                    }
            )
            .onAppear {
                DispatchQueue.main.async {
                    scrollPosition = indexForDate(selectedDate)
                    hasAppeared = true
                }
            }
            .onChange(of: scrollPosition) { _, newValue in
                guard hasAppeared,
                      let newValue,
                      isDateIndex(newValue) else {
                    return
                }
                let date = dateForItemIndex(newValue)
                guard !calendar.isDate(date, inSameDayAs: selectedDate) else {
                    return
                }
                selectedDate = date
                performHaptic()
            }
            .onChange(of: selectedDate) { _, newDate in
                guard hasAppeared else { return }
                let target = indexForDate(newDate)
                if scrollPosition != target {
                    scrollPosition = target
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectDate(at x: CGFloat, width: CGFloat) {
        let centerIndex = scrollPosition ?? indexForDate(selectedDate)
        let offset = Int(round((x - width / 2) / cellWidth))
        let target = centerIndex + offset
        guard isDateIndex(target) else { return }

        let date = dateForItemIndex(target)
        withAnimation(.easeOut(duration: 0.16)) {
            selectedDate = date
            scrollPosition = target
        }
        performHaptic()
    }

    private func dateButton(date: Date, index: Int) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)

        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                selectedDate = date
                scrollPosition = index
            }
            performHaptic()
        } label: {
            VStack(spacing: 3) {
                Text(weekdaySymbol(for: date))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(
                        isSelected
                            ? Color.white.opacity(0.82)
                            : Color.white.opacity(0.34)
                    )

                ZStack {
                    if isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 26, height: 26)
                    } else if isToday {
                        Circle()
                            .stroke(accent.opacity(0.7), lineWidth: 0.8)
                            .frame(width: 26, height: 26)
                    }

                    Text("\(calendar.component(.day, from: date))")
                        .font(
                            .system(
                                size: 14,
                                weight: isSelected ? .semibold : .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            isSelected
                                ? Color.white
                                : isToday
                                    ? accent
                                    : Color.white.opacity(0.72)
                        )
                }
                .frame(width: 28, height: 28)
            }
            .frame(width: cellWidth, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            date.formatted(
                .dateTime.year().month().day()
            )
        )
    }

    private var dateCount: Int {
        pastDays + futureDays + 1
    }

    private var totalItemCount: Int {
        dateCount + spacerCount * 2
    }

    private var baseDate: Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(
            byAdding: .day,
            value: -pastDays,
            to: today
        ) ?? today
    }

    private func isDateIndex(_ index: Int) -> Bool {
        (spacerCount..<(spacerCount + dateCount)).contains(index)
    }

    private func dateForItemIndex(_ index: Int) -> Date {
        calendar.date(
            byAdding: .day,
            value: index - spacerCount,
            to: baseDate
        ) ?? baseDate
    }

    private func indexForDate(_ date: Date) -> Int {
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents(
            [.day],
            from: baseDate,
            to: target
        ).day ?? 0
        return spacerCount + min(max(days, 0), dateCount - 1)
    }

    private func weekdaySymbol(for date: Date) -> String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let weekday = calendar.component(.weekday, from: date)
        let index = min(max(weekday - 1, 0), symbols.count - 1)
        return symbols[index]
    }

    private func performHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }
}
