import SwiftUI
import Charts
import ClaudeTokenManagerCore

struct HistoryView: View {

    @EnvironmentObject var store: UsageStore
    @StateObject private var aggregator = HistoryAggregator.shared
    @State private var period: Period = .sevenDays
    var onClose: (() -> Void)?

    enum Period: String, CaseIterable, Identifiable {
        case oneDay     = "1d"
        case sevenDays  = "7d"
        case thirtyDays = "30d"
        var id: String { rawValue }
    }

    private let bg = Color(red: 31/255, green: 31/255, blue: 30/255)
    private let fg = Color(red: 241/255, green: 239/255, blue: 232/255)
    private let cardBg = Color.white.opacity(0.04)
    private let tokensColor = Color(red: 29/255, green: 158/255, blue: 117/255)
    private let costColor   = Color(red: 217/255, green: 119/255, blue: 87/255)

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    currentSessionSection
                    periodSection
                    impactSection
                    disclaimerNote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(bg)
        .foregroundColor(fg)
        .onAppear {
            Task {
                let events = await Task.detached(priority: .userInitiated) {
                    LogScanner.shared.scan().historyEvents
                }.value
                HistoryAggregator.shared.ingest(events: events)
            }
        }
    }

    // MARK: - Header (mirrors PreferencesView: Back | Title | symmetric spacer)

    private var header: some View {
        HStack {
            Button(action: { onClose?() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
                    Text("Back").font(AppFont.inter(size: 12))
                }.foregroundColor(.white.opacity(0.7))
            }.buttonStyle(.plain)
            Spacer()
            Text("History")
                .font(AppFont.inter(size: 14, weight: .semibold))
            Spacer()
            Spacer().frame(width: 60)
        }
    }

    // MARK: - Current session

    @ViewBuilder
    private var currentSessionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current session")
                .font(AppFont.inter(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .textCase(.uppercase)

            if store.snapshot.sessionStart != nil {
                HStack(spacing: 8) {
                    metricCard(
                        label: "Session tokens",
                        value: TokenFormatter.compact(store.snapshot.sessionTokens),
                        color: tokensColor
                    )
                    metricCard(
                        label: "Session cost",
                        value: CostFormatter.format(store.snapshot.sessionCost),
                        color: costColor
                    )
                }
                Text(store.sessionResetLabel)
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("No active session")
                    .font(AppFont.inter(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Period section (picker + date range + metrics + chart)

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $period) {
                ForEach(Period.allCases) { p in Text(p.rawValue).tag(p) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            Text(periodRangeLabel)
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.5))

            metricsRow
            chartSection
        }
    }

    private var periodRangeLabel: String {
        let labelFmt = DateFormatter()
        labelFmt.locale = Locale(identifier: "en_US_POSIX")
        labelFmt.dateFormat = "MMM d"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch period {
        case .oneDay:
            return "Today · " + labelFmt.string(from: today)
        case .sevenDays:
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return "Last 7 days · \(labelFmt.string(from: start)) → \(labelFmt.string(from: today))"
        case .thirtyDays:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return "Last 30 days · \(labelFmt.string(from: start)) → \(labelFmt.string(from: today))"
        }
    }

    // MARK: - Data shaping

    private struct ChartPoint: Identifiable {
        let label: String
        let order: Int
        let tokensM: Double
        let costUSD: Double
        var id: Int { order }
    }

    private var chartPoints: [ChartPoint] {
        switch period {
        case .oneDay:
            return aggregator.hourlyTodayBuckets.map {
                ChartPoint(
                    label: String(format: "%02dh", $0.hour),
                    order: $0.hour,
                    tokensM: Double($0.totalTokens) / 1_000_000,
                    costUSD: $0.totalCostUSD
                )
            }
        case .sevenDays:
            return makeDailyPoints(days: 7)
        case .thirtyDays:
            return makeDailyPoints(days: 30)
        }
    }

    private func makeDailyPoints(days: Int) -> [ChartPoint] {
        let buckets = aggregator.recentDailyHistory(days: days)
        let byKey = Dictionary(uniqueKeysWithValues: buckets.map { ($0.date, $0) })
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let labelFmt = DateFormatter()
        labelFmt.locale = Locale(identifier: "en_US_POSIX")
        labelFmt.dateFormat = "MM-dd"

        var points: [ChartPoint] = []
        let today = calendar.startOfDay(for: Date())
        for offset in (0..<days).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = formatter.string(from: day)
            let bucket = byKey[key]
            points.append(
                ChartPoint(
                    label: labelFmt.string(from: day),
                    order: -offset,
                    tokensM: Double(bucket?.totalTokens ?? 0) / 1_000_000,
                    costUSD: bucket?.totalCostUSD ?? 0
                )
            )
        }
        return points
    }

    private var totalTokensM: Double { chartPoints.reduce(0) { $0 + $1.tokensM } }
    private var totalCost:    Double { chartPoints.reduce(0) { $0 + $1.costUSD } }

    // MARK: - Metrics

    private var metricsRow: some View {
        HStack(spacing: 8) {
            metricCard(label: "Total tokens", value: formatTokensM(totalTokensM), color: tokensColor)
            metricCard(label: "API equiv. cost", value: String(format: "$%.2f", totalCost), color: costColor)
        }
    }

    private func metricCard(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .font(AppFont.inter(size: 18, weight: .semibold))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                legendDot(color: tokensColor, label: "Tokens (M)")
            }

            Chart(chartPoints) { point in
                AreaMark(
                    x: .value("Period", point.order),
                    y: .value("Tokens", point.tokensM)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [tokensColor.opacity(0.28), tokensColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Period", point.order),
                    y: .value("Tokens", point.tokensM)
                )
                .foregroundStyle(tokensColor)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis {
                AxisMarks(values: chartXTicks) { mark in
                    AxisValueLabel {
                        if let order = mark.as(Int.self),
                           let label = chartPoints.first(where: { $0.order == order })?.label {
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel {
                        Text(yAxisLabel(v.as(Double.self) ?? 0))
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .frame(height: 140)
            .padding(10)
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var chartXTicks: [Int] {
        let orders = chartPoints.map { $0.order }
        guard !orders.isEmpty else { return [] }
        let target: Int
        switch period {
        case .oneDay:     target = 6
        case .sevenDays:  target = 7
        case .thirtyDays: target = 6
        }
        guard orders.count > target else { return orders }
        let step = max(1, orders.count / target)
        return stride(from: 0, to: orders.count, by: step).map { orders[$0] }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 3)
            Text(label).font(AppFont.inter(size: 10)).foregroundColor(.white.opacity(0.55))
        }
    }

    // MARK: - Environmental impact

    private var impact: EnvironmentalImpact {
        EnvironmentalConstants.compute(millionTokens: totalTokensM)
    }

    private var impactSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Estimated environmental impact")
                .font(AppFont.inter(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .textCase(.uppercase)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                impactCard(icon: "bolt.fill",            color: Color(red: 239/255, green: 159/255, blue: 39/255), value: formatKWh(impact.energyKWh),    label: "Energy")
                impactCard(icon: "drop.fill",            color: Color(red: 55/255,  green: 138/255, blue: 221/255), value: formatLiters(impact.waterLiters), label: "Water")
                impactCard(icon: "aqi.medium",           color: Color(red: 136/255, green: 135/255, blue: 128/255), value: formatCO2(impact.co2Grams),     label: "Carbon")
                impactCard(icon: "car.fill",             color: Color(red: 216/255, green: 90/255,  blue: 48/255),  value: formatKm(impact.carKm),         label: "≈ car trip")
                impactCard(icon: "magnifyingglass",      color: Color(red: 186/255, green: 117/255, blue: 23/255),  value: formatCount(impact.googleSearches), label: "≈ Google searches")
                impactCard(icon: "play.rectangle.fill",  color: Color(red: 212/255, green: 83/255,  blue: 126/255), value: formatHours(impact.netflixHours),   label: "≈ Netflix stream")
            }
        }
    }

    private func impactCard(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.15)).frame(width: 26, height: 26)
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(AppFont.inter(size: 12, weight: .medium))
                    .monospacedDigit()
                Text(label)
                    .font(AppFont.inter(size: 9))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Disclaimer

    private var disclaimerNote: some View {
        Text("* Estimated values based on academic averages. Actual figures vary by model, datacenter, and energy mix. Methodology in README.")
            .font(.system(size: 9))
            .foregroundColor(.white.opacity(0.35))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Formatters

    private func formatTokensM(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.2fB", m / 1000) }
        if m >= 1    { return String(format: "%.2fM", m) }
        if m >= 0.001 { return String(format: "%.0fK", m * 1000) }
        return "0"
    }

    private func yAxisLabel(_ m: Double) -> String {
        if m >= 1 { return String(format: "%.1fM", m) }
        if m > 0  { return String(format: "%.0fK", m * 1000) }
        return "0"
    }

    private func formatKWh(_ kwh: Double) -> String {
        if kwh >= 1   { return String(format: "%.2f kWh", kwh) }
        if kwh >= 0.001 { return String(format: "%.0f Wh", kwh * 1000) }
        return "0 Wh"
    }

    private func formatLiters(_ l: Double) -> String {
        if l >= 1000 { return String(format: "%.1f kL", l / 1000) }
        if l >= 1    { return String(format: "%.0f L", l) }
        if l >= 0.001 { return String(format: "%.0f mL", l * 1000) }
        return "0 L"
    }

    private func formatCO2(_ g: Double) -> String {
        if g >= 1000 { return String(format: "%.2f kg", g / 1000) }
        if g >= 1    { return String(format: "%.0f g", g) }
        return "0 g"
    }

    private func formatKm(_ km: Double) -> String {
        if km >= 1   { return String(format: "%.1f km", km) }
        if km >= 0.001 { return String(format: "%.0f m", km * 1000) }
        return "0 m"
    }

    private func formatHours(_ h: Double) -> String {
        if h >= 1     { return String(format: "%.1f h", h) }
        if h >= 1/60  { return String(format: "%.0f min", h * 60) }
        return "0 min"
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
