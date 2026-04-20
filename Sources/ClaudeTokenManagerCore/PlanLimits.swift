import Foundation

// MARK: - Plan definitions

public enum ClaudePlan: String, CaseIterable, Identifiable {
    case pro = "Pro"
    case max5 = "Max 5×"
    case max20 = "Max 20×"

    public var id: String { rawValue }

    public var limits: PlanLimits {
        switch self {
        case .pro:
            return PlanLimits(
                sessionAllModels:   2_000_000,
                weeklyAllModels:   25_000_000,
                weeklySonnetOnly:  20_000_000,
                weeklyOpus:                 0
            )
        case .max5:
            return PlanLimits(
                sessionAllModels:  10_000_000,
                weeklyAllModels:  125_000_000,
                weeklySonnetOnly: 100_000_000,
                weeklyOpus:        15_000_000
            )
        case .max20:
            return PlanLimits(
                sessionAllModels:  40_000_000,
                weeklyAllModels:  500_000_000,
                weeklySonnetOnly: 400_000_000,
                weeklyOpus:        60_000_000
            )
        }
    }
}

public struct PlanLimits {
    public let sessionAllModels: Int
    public let weeklyAllModels: Int
    public let weeklySonnetOnly: Int
    public let weeklyOpus: Int

    public init(sessionAllModels: Int, weeklyAllModels: Int, weeklySonnetOnly: Int, weeklyOpus: Int) {
        self.sessionAllModels = sessionAllModels
        self.weeklyAllModels = weeklyAllModels
        self.weeklySonnetOnly = weeklySonnetOnly
        self.weeklyOpus = weeklyOpus
    }
}

// MARK: - Window computation

public enum LimitWindow {
    case session(start: Date, end: Date)
    case week(start: Date, end: Date)
}

public enum LimitCalculator {

    public static func currentSessionWindow(activityDates: [Date], now: Date = Date()) -> LimitWindow? {
        let fiveHours: TimeInterval = 5 * 3600
        let recent = activityDates.filter { now.timeIntervalSince($0) < fiveHours }
        guard let earliest = recent.min() else { return nil }
        let end = earliest.addingTimeInterval(fiveHours)
        return .session(start: earliest, end: end)
    }

    public static func currentWeekWindow(now: Date = Date(), calendar: Calendar = .current) -> LimitWindow {
        var cal = calendar
        cal.firstWeekday = 2 // Monday

        let today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let mondayMidnight = cal.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
        let mondayMorning = cal.date(bySettingHour: 9, minute: 0, second: 0, of: mondayMidnight) ?? mondayMidnight

        let start: Date
        if now < mondayMorning {
            start = cal.date(byAdding: .day, value: -7, to: mondayMorning) ?? mondayMorning
        } else {
            start = mondayMorning
        }
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        return .week(start: start, end: end)
    }
}

// MARK: - Usage vs limit

public struct LimitProgress: Identifiable {
    public let id: String
    public let label: String
    public let sublabel: String
    public let percent: Double
    public let used: Int
    public let total: Int
    public let accentHue: Hue

    public enum Hue {
        case blue, green, orange, gray

        public var hex: String {
            switch self {
            case .blue:   return "#378ADD"
            case .green:  return "#1D9E75"
            case .orange: return "#D97757"
            case .gray:   return "#888780"
            }
        }
    }

    public var isHot: Bool { percent >= 0.70 }
    public var clampedPercent: Double { max(0, min(1, percent)) }

    public init(id: String, label: String, sublabel: String, percent: Double, used: Int, total: Int, accentHue: Hue) {
        self.id = id
        self.label = label
        self.sublabel = sublabel
        self.percent = percent
        self.used = used
        self.total = total
        self.accentHue = accentHue
    }
}
