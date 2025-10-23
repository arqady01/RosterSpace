//
//  StatsScreen.swift
//  RosterSpace
//
//  Created by Codex on 10/22/25.
//

import SwiftUI
import Charts

struct StatsScreen: View {
    @EnvironmentObject private var store: RosterDataStore
    @State private var selectedTimeRange: TimeRangeOption = .currentMonth
    @State private var frequencyCoworker: CoworkerSelection = .all
    @State private var heatmapCoworker: CoworkerSelection = .all

    private var stats: RosterStatistics {
        let scopedData = filteredData
        return RosterStatistics(
            calendar: store.calendar,
            shiftAssignments: scopedData.shifts,
            coworkerAssignments: scopedData.coworkers
        )
    }

    private var attendanceSummary: String {
        if stats.totalTrackedDays == 0 {
            return "暂无考勤记录"
        }
        return "出勤 \(stats.totalWorkingDays) 天 · 休息 \(stats.totalRestDays) 天"
    }

    private var coworkerOptions: [CoworkerSelection] {
        let sortedNames = store.colleagues.sorted()
        return [.all] + sortedNames.map { .person($0) }
    }

    private var filteredData: (shifts: [Date: ShiftType], coworkers: [Date: Set<String>]) {
        let calendar = store.calendar
        let referenceDate = Date()
        let bounds = selectedTimeRange.bounds(referenceDate: referenceDate, calendar: calendar)
        let lowerBound = bounds.lower
        let upperBound = bounds.upper

        var shifts: [Date: ShiftType] = [:]
        var coworkers: [Date: Set<String>] = [:]

        for (date, shift) in store.shiftAssignments {
            if let lowerBound, date < lowerBound {
                continue
            }
            if let upperBound, date > upperBound {
                continue
            }
            shifts[date] = shift
            coworkers[date] = store.coworkerAssignments[date] ?? Set()
        }

        return (shifts, coworkers)
    }

    private var selectedTimeRangeDisplay: String {
        selectedTimeRange.title
    }

    private func coworkerDisplay(for selection: CoworkerSelection) -> String {
        switch selection {
        case .all:
            return store.colleagues.isEmpty ? "暂无同事" : "全部同事"
        case .person(let name):
            return name
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("筛选条件")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("时间范围")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(selection: $selectedTimeRange) {
                    ForEach(TimeRangeOption.allCases) { option in
                        Text(option.title)
                            .tag(option)
                    }
                } label: {
                    HStack {
                        Text(selectedTimeRangeDisplay)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemFill))
                    )
                }
                .pickerStyle(.menu)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.05))
        )
    }

    private var filteredFrequencyCounts: [RosterStatistics.CoworkerCount] {
        switch frequencyCoworker {
        case .all:
            return stats.coworkerCounts
        case .person(let name):
            guard let count = stats.coworkerCount(for: name) else { return [] }
            return [count]
        }
    }

    private var filteredHeatmapEntries: [RosterStatistics.CoworkerShiftEntry] {
        switch heatmapCoworker {
        case .all:
            return stats.coworkerShiftMatrix
        case .person(let name):
            return stats.coworkerShiftEntries(for: name)
        }
    }

    private func coworkerFilterPicker(selection: Binding<CoworkerSelection>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("共事成员")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(selection: selection) {
                ForEach(coworkerOptions) { option in
                    Text(option.label)
                        .tag(option)
                }
            } label: {
                HStack {
                    Text(coworkerDisplay(for: selection.wrappedValue))
                        .foregroundStyle(store.colleagues.isEmpty ? .secondary : .primary)
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemFill))
                )
            }
            .pickerStyle(.menu)
            .disabled(store.colleagues.isEmpty)
            .opacity(store.colleagues.isEmpty ? 0.6 : 1)
        }
    }

    private func sanitizeCoworkerSelections() {
        let validNames = Set(store.colleagues)
        if case .person(let name) = frequencyCoworker, !validNames.contains(name) {
            frequencyCoworker = .all
        }
        if case .person(let name) = heatmapCoworker, !validNames.contains(name) {
            heatmapCoworker = .all
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    filterControls

                    StatsCard(
                        title: "班次分布",
                        subtitle: stats.totalTrackedDays == 0 ? "暂无排班记录" : "覆盖 \(stats.totalTrackedDays) 天排班"
                    ) {
                        shiftDistributionChart(stats.shiftCounts)
                    }

        StatsCard(
            title: "班次趋势折线图",
            subtitle: stats.shiftTrendSeries.isEmpty ? "暂无班次趋势" : "按月统计早/中/晚班与休息次数"
        ) {
            shiftTrendChart()
        }

        StatsCard(
            title: "共事频次排行榜",
            subtitle: stats.coworkerCounts.isEmpty ? "暂无共事记录" : "统计班次共事次数（前 10）"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                coworkerFilterPicker(selection: $frequencyCoworker)
                coworkerFrequencyChart(filteredFrequencyCounts)
            }
        }

        StatsCard(
            title: "出勤 vs 休息",
            subtitle: attendanceSummary
                    ) {
                        attendanceDonutChart(stats.attendanceBreakdown)
                    }

        StatsCard(
            title: "班次与同事热力图",
            subtitle: stats.coworkerShiftMatrix.isEmpty ? "暂无共事统计" : "展示不同班次的共事活跃度"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                coworkerFilterPicker(selection: $heatmapCoworker)
                coworkerHeatmap(filteredHeatmapEntries)
            }
        }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("统计")
        }
        .onAppear(perform: sanitizeCoworkerSelections)
        .onChange(of: store.colleagues) { _ in
            sanitizeCoworkerSelections()
        }
    }

    private enum TimeRangeOption: String, Identifiable {
        case currentMonth
        case currentYear
        case all

        var id: String { rawValue }

        static var allCases: [TimeRangeOption] {
            [.currentMonth, .currentYear, .all]
        }

        var title: String {
            switch self {
            case .currentMonth:
                return "仅本月"
            case .currentYear:
                return "仅今年"
            case .all:
                return "全部"
            }
        }

        func bounds(referenceDate: Date, calendar: Calendar) -> (lower: Date?, upper: Date?) {
            let today = calendar.startOfDay(for: referenceDate)
            switch self {
            case .all:
                return (nil, nil)
            case .currentMonth:
                let startOfMonth = calendar.startOfMonth(for: today)
                return (startOfMonth, today)
            case .currentYear:
                let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: today))
                return (startOfYear, today)
            }
        }
    }

    private enum CoworkerSelection: Hashable, Identifiable {
        case all
        case person(String)

        var id: String {
            switch self {
            case .all:
                return "all"
            case .person(let name):
                return "person-\(name)"
            }
        }

        var label: String {
            switch self {
            case .all:
                return "全部同事"
            case .person(let name):
                return name
            }
        }
    }

    @ViewBuilder
    private func shiftDistributionChart(_ data: [RosterStatistics.ShiftCount]) -> some View {
        if data.allSatisfy({ $0.count == 0 }) {
            StatsPlaceholder(message: "暂无班次数据")
        } else {
            let maxValue = data.map(\.count).max() ?? 0
            Chart {
                ForEach(data) { item in
                    BarMark(
                        x: .value("班次", item.shift.displayName),
                        y: .value("天数", item.count)
                    )
                    .foregroundStyle(item.shift.chartColor)
                    .cornerRadius(6)
                    .annotation(position: .top, alignment: .center) {
                        if item.count > 0 {
                            Text("\(item.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartYScale(domain: 0...(Double(max(maxValue, 1)) * 1.2))
            .frame(height: 240)
        }
    }

    @ViewBuilder
    private func shiftTrendChart() -> some View {
        let months = stats.expandedShiftTrendMonths
        let actualMonths = stats.actualShiftTrendMonths
        let seriesByShift = stats.shiftTrendSeriesByShift
        let maxCount = stats.shiftTrendMaxCount

        if actualMonths.isEmpty {
            return AnyView(StatsPlaceholder(message: "暂无班次趋势数据"))
        } else if actualMonths.count <= 1 {
            return AnyView(StatsPlaceholder(message: "时间跨度太小，不予显示"))
        } else {
            let chartHeight: CGFloat = 260
            let yUpper = max(1, Double(maxCount)) * 1.1

            let chart = Chart {
                ForEach(seriesByShift, id: \.shift) { series in
                    ForEach(series.points) { point in
                        LineMark(
                            x: .value("月份", point.periodStart),
                            y: .value("次数", point.count)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(by: .value("班次", series.shift.displayName))
                        .symbol(by: .value("班次", series.shift.displayName))
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: seriesByShift.map { $0.shift.displayName },
                range: seriesByShift.map { $0.shift.chartColor }
            )
            .chartXScale(domain: months.first!...months.last!)
            .chartYScale(domain: 0...yUpper)
            .chartXAxis {
                AxisMarks(values: months) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let dateValue = value.as(Date.self) {
                            Text(dateValue, format: .dateTime.month(.abbreviated))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartScrollableAxes(.horizontal)
            .chartLegend(.hidden)
            .chartPlotStyle { plot in
                plot
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
            .frame(height: chartHeight)
            .ifLet(stats.shiftTrendVisibleSpan) { view, span in
                view.chartXVisibleDomain(length: span)
            }

            return AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    chart
                    shiftLegend
                }
            )
        }
    }

    private var shiftLegend: some View {
        HStack(spacing: 16) {
            ForEach(ShiftType.trendShifts, id: \.self) { shift in
                HStack(spacing: 6) {
                    Circle()
                        .fill(shift.chartColor)
                        .frame(width: 8, height: 8)
                    Text(shift.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func coworkerFrequencyChart(_ data: [RosterStatistics.CoworkerCount]) -> some View {
        if data.isEmpty {
            StatsPlaceholder(message: "暂无共事记录")
        } else {
            let height = max(160, CGFloat(data.count) * 36)
            Chart(data) { item in
                BarMark(
                    x: .value("次数", item.count),
                    y: .value("成员", item.name)
                )
                .foregroundStyle(Color.purple.opacity(0.75))
                .annotation(position: .trailing, alignment: .center) {
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(values: data.map(\.name))
            }
            .frame(height: height)
        }
    }

    @ViewBuilder
    private func attendanceDonutChart(_ data: [RosterStatistics.AttendanceSlice]) -> some View {
        let total = data.reduce(0) { $0 + $1.value }
        if total == 0 {
            StatsPlaceholder(message: "暂无考勤数据")
        } else {
            Chart(data) { slice in
                SectorMark(
                    angle: .value("天数", slice.value),
                    innerRadius: .ratio(0.6)
                )
                .cornerRadius(6)
                .foregroundStyle(slice.kind == .working ? Color.green : Color.gray.opacity(0.4))
                .annotation(position: .overlay) {
                    if slice.value > 0 {
                        VStack(spacing: 4) {
                            Text(slice.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("\(slice.value)")
                                .font(.caption2)
                        }
                        .foregroundStyle(slice.kind == .working ? Color.white : Color.primary)
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 220)
        }
    }

    @ViewBuilder
    private func coworkerHeatmap(_ data: [RosterStatistics.CoworkerShiftEntry]) -> some View {
        if data.isEmpty {
            StatsPlaceholder(message: "暂无共事统计")
        } else {
            let coworkers = Array(Set(data.map(\.coworker))).sorted()
            let shifts = ShiftType.managementOptions.filter { $0.allowsCoworkers }
            Chart(data) { entry in
                RectangleMark(
                    x: .value("班次", entry.shift.displayName),
                    y: .value("成员", entry.coworker)
                )
                .foregroundStyle(heatColor(for: entry.count))
                .cornerRadius(4)
                .annotation(position: .overlay) {
                    if entry.count > 0 {
                        Text("\(entry.count)")
                            .font(.caption2)
                            .foregroundStyle(Color.white)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: shifts.map { $0.displayName })
            }
            .chartYAxis {
                AxisMarks(values: coworkers)
            }
            .frame(height: max(220, CGFloat(coworkers.count) * 36))
        }
    }

    private func heatColor(for value: Int) -> Color {
        switch value {
        case 0:
            return Color(.systemFill)
        case 1:
            return Color.accentColor.opacity(0.35)
        case 2...3:
            return Color.accentColor.opacity(0.65)
        default:
            return Color.accentColor
        }
    }

}

private struct StatsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder private let content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.05))
        )
    }
}

private struct StatsPlaceholder: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
    }
}

struct RosterStatistics {
    struct ShiftCount: Identifiable {
        let shift: ShiftType
        let count: Int
        var id: ShiftType { shift }
    }

    struct ShiftTrendPoint: Identifiable {
        let periodStart: Date
        let shift: ShiftType
        let count: Int
        var id: String { "\(shift.rawValue)|\(periodStart.timeIntervalSinceReferenceDate)" }
    }

    struct CoworkerCount: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    struct AttendanceSlice: Identifiable {
        enum Kind {
            case working
            case rest
        }

        let kind: Kind
        let value: Int
        var id: Kind { kind }

        var label: String {
            switch kind {
            case .working:
                return "出勤"
            case .rest:
                return "休息"
            }
        }
    }

    struct CoworkerShiftEntry: Identifiable {
        let coworker: String
        let shift: ShiftType
        let count: Int
        var id: String { "\(coworker)|\(shift.rawValue)" }
    }

    let calendar: Calendar
    let shiftAssignments: [Date: ShiftType]
    let coworkerAssignments: [Date: Set<String>]

    var totalTrackedDays: Int {
        shiftAssignments.count
    }

    var totalWorkingDays: Int {
        shiftAssignments.values.filter { $0.isWorkingShift }.count
    }

    var totalRestDays: Int {
        max(0, totalTrackedDays - totalWorkingDays)
    }

    var shiftCounts: [ShiftCount] {
        let grouped = shiftAssignments.values.reduce(into: [ShiftType: Int]()) { result, shift in
            result[shift, default: 0] += 1
        }
        return ShiftType.visualOrder.map { ShiftCount(shift: $0, count: grouped[$0] ?? 0) }
    }

    var shiftTrendSeries: [ShiftTrendPoint] {
        let trackedShifts = ShiftType.trendShifts
        var aggregated: [Date: [ShiftType: Int]] = [:]
        for (date, shift) in shiftAssignments {
            guard trackedShifts.contains(shift) else { continue }
            let bucket = calendar.startOfMonth(for: date)
            aggregated[bucket, default: [:]][shift, default: 0] += 1
        }
        let sortedBuckets = aggregated.keys.sorted()
        return sortedBuckets.flatMap { bucket in
            trackedShifts.map { shift in
                ShiftTrendPoint(
                    periodStart: bucket,
                    shift: shift,
                    count: aggregated[bucket]?[shift] ?? 0
                )
            }
        }
    }

    var actualShiftTrendMonths: [Date] {
        let months = Set(shiftTrendSeries.map(\.periodStart))
        return months.sorted()
    }

    var expandedShiftTrendMonths: [Date] {
        let actual = actualShiftTrendMonths
        guard !actual.isEmpty else { return [] }
        let years = Set(actual.map { calendar.component(.year, from: $0) }).sorted()
        var allMonths: [Date] = []
        for year in years {
            for month in 1...12 {
                if let date = calendar.date(from: DateComponents(year: year, month: month)) {
                    allMonths.append(calendar.startOfMonth(for: date))
                }
            }
        }
        return allMonths
    }

    var shiftTrendSeriesByShift: [(shift: ShiftType, points: [ShiftTrendPoint])] {
        let grouped = Dictionary(grouping: shiftTrendSeries, by: \.shift)
        let months = expandedShiftTrendMonths
        return ShiftType.trendShifts.map { shift in
            let lookup = Dictionary(uniqueKeysWithValues: (grouped[shift] ?? []).map { ($0.periodStart, $0) })
            let filledPoints = months.map { month in
                lookup[month] ?? ShiftTrendPoint(periodStart: month, shift: shift, count: 0)
            }
            return (shift, filledPoints)
        }
    }

    var shiftTrendMaxCount: Int {
        shiftTrendSeries.map(\.count).max() ?? 0
    }

    var shiftTrendVisibleSpan: TimeInterval? {
        let months = expandedShiftTrendMonths
        guard let start = months.first else { return nil }
        let calendar = calendar
        let visibleMonths = min(4, max(1, months.count))
        guard let end = calendar.date(byAdding: .month, value: visibleMonths - 1, to: start) else {
            return nil
        }
        return end.timeIntervalSince(start) + 1
    }

    private var coworkerTotals: [String: Int] {
        var counts: [String: Int] = [:]
        for (date, members) in coworkerAssignments {
            let shift = shiftAssignments[date] ?? .none
            guard shift.allowsCoworkers else { continue }
            for name in members {
                counts[name, default: 0] += 1
            }
        }
        return counts
    }

    var coworkerCounts: [CoworkerCount] {
        let sorted = coworkerTotals
            .map { CoworkerCount(name: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.name < $1.name
                }
                return $0.count > $1.count
            }
        return Array(sorted.prefix(10))
    }

    func coworkerCount(for name: String) -> CoworkerCount? {
        guard let value = coworkerTotals[name] else { return nil }
        return CoworkerCount(name: name, count: value)
    }

    var attendanceBreakdown: [AttendanceSlice] {
        [
            AttendanceSlice(kind: .working, value: totalWorkingDays),
            AttendanceSlice(kind: .rest, value: totalRestDays)
        ]
    }

    var coworkerShiftMatrix: [CoworkerShiftEntry] {
        var matrix: [String: [ShiftType: Int]] = [:]
        var coworkerSet = Set<String>()
        for (date, members) in coworkerAssignments {
            let shift = shiftAssignments[date] ?? .none
            guard shift.allowsCoworkers else { continue }
            guard !members.isEmpty else { continue }
            for name in members {
                coworkerSet.insert(name)
                matrix[name, default: [:]][shift, default: 0] += 1
            }
        }
        let workingShifts = ShiftType.managementOptions.filter { $0.allowsCoworkers }
        var entries: [CoworkerShiftEntry] = []
        let orderedCoworkers = coworkerSet.sorted()
        for name in orderedCoworkers {
            let shiftCounts = matrix[name] ?? [:]
            for shift in workingShifts {
                let total = shiftCounts[shift] ?? 0
                entries.append(
                    CoworkerShiftEntry(
                        coworker: name,
                        shift: shift,
                        count: total
                    )
                )
            }
        }
        return entries
    }

    func coworkerShiftEntries(for name: String) -> [CoworkerShiftEntry] {
        let entries = coworkerShiftMatrix.filter { $0.coworker == name }
        if !entries.isEmpty {
            return entries
        }
        let workingShifts = ShiftType.managementOptions.filter { $0.allowsCoworkers }
        return workingShifts.map {
            CoworkerShiftEntry(coworker: name, shift: $0, count: 0)
        }
    }
}

extension ShiftType {
    static var trendShifts: [ShiftType] {
        [.morning, .afternoon, .evening, .rest]
    }

    static var visualOrder: [ShiftType] {
        [.morning, .afternoon, .evening, .rest, .none]
    }

    var isWorkingShift: Bool {
        allowsCoworkers
    }

    var chartColor: Color {
        switch self {
        case .morning:
            return Color.orange
        case .afternoon:
            return Color.red
        case .evening:
            return Color.blue
        case .rest:
            return Color.green.opacity(0.75)
        case .none:
            return Color.gray.opacity(0.45)
        }
    }
}

extension View {
    @ViewBuilder
    func ifLet<T>(_ value: T?, transform: (Self, T) -> some View) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }
}
