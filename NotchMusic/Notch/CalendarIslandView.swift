import AppKit
import EventKit
import SwiftUI

private enum CalendarPixelTypography {
    static func font(size: CGFloat) -> Font {
        .system(size: size)
    }
}

private struct CalendarWeatherInfo {
    let symbolName: String
    let temperature: Int
    let location: String
    let condition: String

    init?(event: EKEvent) {
        guard event.isAllDay else { return nil }
        let calendarName = event.calendar.title
        guard calendarName.contains("天气")
            || calendarName.localizedCaseInsensitiveContains("weather")
        else {
            return nil
        }

        let title = event.title ?? ""
        guard let temperature = Self.temperature(in: title) else {
            return nil
        }

        let firstLine = event.notes?
            .components(separatedBy: .newlines)
            .first ?? title
        let style = Self.style(for: firstLine)
        let rawLocation = event.location?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        symbolName = style.symbolName
        self.temperature = temperature
        location = rawLocation.isEmpty
            ? Self.location(from: calendarName)
            : rawLocation
        condition = Self.condition(from: firstLine) ?? style.condition
    }

    private static func temperature(in title: String) -> Int? {
        guard let range = title.range(
            of: #"-?\d+\s*°"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let digits = title[range].filter {
            $0.isNumber || $0 == "-"
        }
        return Int(digits)
    }

    private static func location(from calendarName: String) -> String {
        let parts = calendarName.components(separatedBy: " - ")
        if parts.count > 1 {
            return parts.last?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return calendarName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func condition(from line: String) -> String? {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = value.firstIndex(where: \.isLetter) else {
            return nil
        }
        let condition = value[index...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return condition.isEmpty ? nil : condition
    }

    private static func style(
        for text: String
    ) -> (symbolName: String, condition: String) {
        if containsScalar(0x26C8, in: text) {
            return ("cloud.bolt.rain.fill", "雷雨")
        }
        if containsScalar(0x1F327, in: text) {
            return ("cloud.rain.fill", "雨")
        }
        if containsScalar(0x1F326, in: text) {
            return ("cloud.sun.rain.fill", "阵雨")
        }
        if containsScalar(0x1F328, in: text)
            || containsScalar(0x2744, in: text) {
            return ("cloud.snow.fill", "雪")
        }
        if containsScalar(0x1F32B, in: text) {
            return ("cloud.fog.fill", "雾")
        }
        if containsScalar(0x2601, in: text) {
            return ("cloud.fill", "阴")
        }
        if containsScalar(0x26C5, in: text)
            || containsScalar(0x1F324, in: text) {
            return ("cloud.sun.fill", "多云")
        }
        if containsScalar(0x1F319, in: text)
            || containsScalar(0x1F31C, in: text) {
            return ("moon.fill", "晴")
        }
        return ("sun.max.fill", "晴")
    }

    private static func containsScalar(
        _ value: UInt32,
        in text: String
    ) -> Bool {
        text.unicodeScalars.contains { $0.value == value }
    }
}

private struct CalendarWeatherIcon: View {
    let symbolName: String
    let size: CGFloat

    var body: some View {
        Group {
            switch symbolName {
            case "sun.max.fill":
                AnimatedSun(size: size)
            case "moon.fill":
                AnimatedMoon(size: size)
            case "cloud.sun.fill":
                AnimatedWeatherScene(kind: .partlyCloudy, size: size)
            case "cloud.fill":
                AnimatedWeatherScene(kind: .cloudy, size: size)
            case "cloud.fog.fill":
                AnimatedWeatherScene(kind: .fog, size: size)
            case "cloud.rain.fill":
                AnimatedWeatherScene(kind: .rain, size: size)
            case "cloud.sun.rain.fill":
                AnimatedWeatherScene(kind: .showers, size: size)
            case "cloud.bolt.rain.fill":
                AnimatedWeatherScene(kind: .storm, size: size)
            case "cloud.snow.fill":
                AnimatedWeatherScene(kind: .snow, size: size)
            default:
                Image(systemName: symbolName)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.multicolor)
            }
        }
        .frame(width: size, height: size)
    }
}

private enum WeatherSceneKind {
    case partlyCloudy
    case cloudy
    case fog
    case rain
    case showers
    case storm
    case snow
}

private struct SunBody: View {
    let size: CGFloat
    let rotation: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.93, blue: 0.55),
                            Color(red: 1.0, green: 0.65, blue: 0.12)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.23
                    )
                )
                .frame(width: size * 0.46, height: size * 0.46)
                .shadow(
                    color: Color(
                        red: 1.0,
                        green: 0.7,
                        blue: 0.2
                    ).opacity(0.55),
                    radius: size * 0.1
                )

            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    let angle = Double(index) * .pi / 4
                    Capsule()
                        .fill(
                            Color(red: 1.0, green: 0.78, blue: 0.24)
                        )
                        .frame(
                            width: size * 0.06,
                            height: size * 0.19
                        )
                        .rotationEffect(
                            .degrees(Double(index) * 45 + 90)
                        )
                        .offset(
                            x: CGFloat(cos(angle)) * size * 0.395,
                            y: CGFloat(sin(angle)) * size * 0.395
                        )
                }
            }
            .rotationEffect(.degrees(rotation))
        }
        .frame(width: size, height: size)
    }
}

private struct AnimatedSun: View {
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { context in
            SunBody(
                size: size,
                rotation: rotation(at: context.date)
            )
        }
    }

    private func rotation(at date: Date) -> Double {
        guard !reduceMotion else { return 0 }
        let time = date.timeIntervalSinceReferenceDate
        return (time.truncatingRemainder(dividingBy: 9) / 9) * 360
    }
}

private struct AnimatedMoon: View {
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let wave = reduceMotion
                ? 0
                : sin(time * 2 * .pi / 2.8)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(
                                    red: 0.78,
                                    green: 0.87,
                                    blue: 1.0
                                ).opacity(0.28),
                                .clear
                            ],
                            center: .center,
                            startRadius: size * 0.04,
                            endRadius: size * 0.45
                        )
                    )
                    .frame(width: size * 0.92, height: size * 0.92)
                    .scaleEffect(CGFloat(0.96 + 0.08 * wave))

                Image(systemName: "moon.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.97, blue: 0.86),
                                Color(red: 0.78, green: 0.86, blue: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: Color(
                            red: 0.8,
                            green: 0.88,
                            blue: 1.0
                        ).opacity(0.45),
                        radius: size * 0.1
                    )
                    .scaleEffect(CGFloat(1.0 + 0.035 * wave))
                    .padding(size * 0.06)
            }
        }
    }
}

private struct AnimatedWeatherScene: View {
    let kind: WeatherSceneKind
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { context in
            scene(time: context.date.timeIntervalSinceReferenceDate)
        }
    }

    @ViewBuilder
    private func scene(time: TimeInterval) -> some View {
        switch kind {
        case .cloudy:
            WeatherCloud(width: size * 0.82)
                .offset(
                    x: drift(
                        time,
                        amplitude: size * 0.05,
                        period: 4.4
                    ),
                    y: size * 0.06
                )

        case .partlyCloudy:
            ZStack {
                SunBody(size: size * 0.64, rotation: rotation(time))
                    .offset(x: size * 0.17, y: -size * 0.16)

                WeatherCloud(width: size * 0.8)
                    .offset(x: -size * 0.06, y: size * 0.09)
            }

        case .fog:
            ZStack {
                WeatherCloud(width: size * 0.8)
                    .offset(y: -size * 0.15)

                FogLines(size: size, time: time)
                    .offset(y: size * 0.18)
            }

        case .rain:
            ZStack {
                RainDrops(size: size, time: time)
                    .offset(y: size * 0.22)

                WeatherCloud(width: size * 0.8)
                    .offset(y: -size * 0.1)
            }

        case .showers:
            ZStack {
                SunBody(size: size * 0.58, rotation: rotation(time))
                    .offset(x: size * 0.19, y: -size * 0.2)

                RainDrops(size: size, time: time)
                    .offset(y: size * 0.3)

                WeatherCloud(width: size * 0.76)
                    .offset(x: -size * 0.05, y: -size * 0.02)
            }

        case .storm:
            ZStack {
                RainDrops(size: size, time: time)
                    .offset(y: size * 0.22)

                WeatherCloud(width: size * 0.8)
                    .offset(y: -size * 0.1)

                Image(systemName: "bolt.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.95, blue: 0.55),
                                Color(red: 1.0, green: 0.72, blue: 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.26)
                    .shadow(
                        color: Color.yellow.opacity(0.85),
                        radius: size * 0.09
                    )
                    .offset(x: size * 0.04, y: size * 0.1)
                    .opacity(flashOpacity(time))
            }

        case .snow:
            ZStack {
                SnowFlakes(size: size, time: time)
                    .offset(y: size * 0.24)

                WeatherCloud(width: size * 0.8)
                    .offset(y: -size * 0.1)
            }
        }
    }

    private func rotation(_ time: TimeInterval) -> Double {
        guard !reduceMotion else { return 0 }
        return (time.truncatingRemainder(dividingBy: 9) / 9) * 360
    }

    private func drift(
        _ time: TimeInterval,
        amplitude: CGFloat,
        period: Double
    ) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return CGFloat(sin(time * 2 * .pi / period)) * amplitude
    }

    private func flashOpacity(_ time: TimeInterval) -> Double {
        guard !reduceMotion else { return 1 }
        let phase = time.truncatingRemainder(dividingBy: 1.8)
        if phase < 0.08 || (phase > 0.16 && phase < 0.24) {
            return 1
        }
        let glow = 0.5 + 0.5 * sin(time * 2 * .pi / 0.9)
        return 0.5 + 0.2 * glow
    }
}

private struct WeatherCloud: View {
    let width: CGFloat

    var body: some View {
        Image(systemName: "cloud.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(white: 1.0),
                        Color(red: 0.8, green: 0.86, blue: 0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width)
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
    }
}

private struct RainDrops: View {
    let size: CGFloat
    let time: TimeInterval

    private let count = 5

    var body: some View {
        let frameHeight = size * 0.4
        let dropHeight = size * 0.17
        let travel = frameHeight - dropHeight

        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let phase = weatherPhase(
                    time,
                    offset: Double(index) / Double(count),
                    period: 0.9
                )

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.6, green: 0.9, blue: 1.0),
                                Color(red: 0.2, green: 0.6, blue: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.05, height: dropHeight)
                    .offset(
                        x: dropOffset(index: index),
                        y: -travel / 2 + CGFloat(phase) * travel
                    )
                    .opacity(0.5 + 0.5 * (1 - phase))
            }
        }
        .frame(width: size, height: frameHeight)
    }

    private func dropOffset(index: Int) -> CGFloat {
        let positions: [CGFloat] = [
            -0.17, -0.085, 0, 0.085, 0.17
        ]
        return positions[index] * size
    }
}

private struct SnowFlakes: View {
    let size: CGFloat
    let time: TimeInterval

    private let count = 4

    var body: some View {
        let frameHeight = size * 0.38
        let flakeSize = size * 0.18
        let travel = frameHeight - flakeSize

        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let phase = weatherPhase(
                    time,
                    offset: Double(index) / Double(count),
                    period: 2.8
                )
                let sway = sin(
                    time * 1.6 + Double(index) * 2.1
                )

                Image(systemName: "snowflake")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: flakeSize, height: flakeSize)
                    .shadow(
                        color: Color.white.opacity(0.8),
                        radius: size * 0.04
                    )
                    .rotationEffect(.degrees(phase * 240))
                    .offset(
                        x: snowOffset(index: index)
                            + CGFloat(sway) * size * 0.03,
                        y: -travel / 2 + CGFloat(phase) * travel
                    )
                    .opacity(0.8 + 0.2 * (1 - phase))
            }
        }
        .frame(width: size, height: frameHeight)
    }

    private func snowOffset(index: Int) -> CGFloat {
        let positions: [CGFloat] = [-0.15, -0.05, 0.06, 0.15]
        return positions[index] * size
    }
}

private struct FogLines: View {
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let sway = sin(
                    time * (1.6 + Double(index) * 0.35)
                        + Double(index) * 1.9
                )

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                Color(
                                    red: 0.76,
                                    green: 0.84,
                                    blue: 0.93
                                ).opacity(0.7)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: size
                            * CGFloat(0.5 - Double(index) * 0.06),
                        height: size * 0.045
                    )
                    .offset(
                        x: CGFloat(sway) * size * 0.13,
                        y: CGFloat(index - 1) * size * 0.085
                    )
            }
        }
        .frame(width: size, height: size * 0.26)
    }
}

private func weatherPhase(
    _ time: TimeInterval,
    offset: Double,
    period: Double
) -> Double {
    let value = time / period + offset
    return value - floor(value)
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
    let weatherInfo: CalendarWeatherInfo?

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

    func resetSelectedDateToToday() {
        let today = Date()
        guard !Calendar.current.isDate(
            today,
            inSameDayAs: selectedDate
        ) else {
            return
        }
        selectedDate = today
        events = []
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
                        return CalendarEventItem(
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
                                : nil,
                            weatherInfo: CalendarWeatherInfo(event: event)
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

    static func resetToToday() {
        CalendarMonitor.shared.resetSelectedDateToToday()
    }
}

struct CalendarIslandView: View {
    let accent: Color
    let width: CGFloat

    @ObservedObject private var monitor = CalendarMonitor.shared
    @State private var eventLoadTask: Task<Void, Never>?
    @Environment(\.openURL) private var openURL

    private var weatherEventInfo: CalendarWeatherInfo? {
        monitor.events.compactMap(\.weatherInfo).first
    }

    private var visibleEvents: [CalendarEventItem] {
        monitor.events.filter { $0.weatherInfo == nil }
    }

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
    private let headerHeight: CGFloat = 54
    private let weatherIconSize: CGFloat = 40
    private let weatherRowHeight: CGFloat = 54

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

            yearMonthHeader
                .frame(maxWidth: .infinity)
                .frame(height: headerHeight)

            Spacer(minLength: 0)

            CalendarDateWheel(
                selectedDate: selectedDateBinding,
                accent: accent
            )
            .frame(height: 58)
            .padding(.vertical, -7)
            .padding(.top, 12)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 0.94),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, 0)
    }

    private var yearMonthHeader: some View {
        VStack(spacing: 4) {
            Text(Self.yearFormatter.string(from: selectedDate))
                .font(
                    .system(
                        size: 12,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white.opacity(0.46))
                .contentTransition(.numericText())
                .animation(
                    .easeInOut(duration: 0.16),
                    value: calendar.component(.year, from: selectedDate)
                )

            Text(Self.monthFormatter.string(from: selectedDate))
                .font(CalendarPixelTypography.font(size: 30))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(
                    .easeInOut(duration: 0.16),
                    value: calendar.component(.month, from: selectedDate)
                )
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: headerHeight, alignment: .center)
    }

    private func weatherSummary(
        _ weather: CalendarWeatherInfo
    ) -> some View {
        HStack(spacing: 10) {
            CalendarWeatherIcon(
                symbolName: weather.symbolName,
                size: weatherIconSize
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("\(weather.temperature)°")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                HStack(spacing: 4) {
                    if !weather.location.isEmpty {
                        Text(weather.location)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)

                        Text("·")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.3))
                    }

                    Text(weather.condition)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.white.opacity(0.46))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(height: weatherRowHeight)
    }

    private var emptyEventState: some View {
        VStack(spacing: 5) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.38))
            Text("暂无日程")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if weatherEventInfo == nil && visibleEvents.isEmpty {
                emptyEventState
            } else {
                VStack(spacing: 3) {
                    if let weather = weatherEventInfo {
                        weatherSummary(weather)
                    }

                    if !visibleEvents.isEmpty {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 3) {
                                ForEach(visibleEvents) { event in
                                    eventRow(event)
                                }
                            }
                            .padding(.top, 1)
                            .padding(.bottom, 2)
                        }
                        .scrollIndicators(.never)
                    } else {
                        emptyEventState
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
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
