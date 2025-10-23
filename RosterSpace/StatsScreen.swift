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
    @State private var selectedTimeRange: TimeRangeOption = .all
    @State private var selectedCoworker: CoworkerSelection = .all

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
        let lowerBound = selectedTimeRange.lowerBound(referenceDate: referenceDate, calendar: calendar)
        let upperBound = calendar.startOfDay(for: referenceDate)
        let shouldApplyUpperBound = selectedTimeRange != .all

        var shifts: [Date: ShiftType] = [:]
        var coworkers: [Date: Set<String>] = [:]

        for (date, shift) in store.shiftAssignments {
            if let lowerBound, date < lowerBound {
                continue
            }
            if shouldApplyUpperBound && date > upperBound {
                continue
            }
            shifts[date] = shift
            coworkers[date] = store.coworkerAssignments[date] ?? Set()
        }

        if case .person(let name) = selectedCoworker {
            for date in Array(shifts.keys) {
                let selections = coworkers[date] ?? Set()
                guard selections.contains(name) else {
                    shifts.removeValue(forKey: date)
                    coworkers.removeValue(forKey: date)
                    continue
                }
                coworkers[date] = Set([name])
            }
        }

        return (shifts, coworkers)
    }

    private var selectedCoworkerDisplay: String {
        switch selectedCoworker {
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

                Picker("时间范围", selection: $selectedTimeRange) {
                    ForEach(TimeRangeOption.allCases) { option in
                        Text(option.title)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("共事成员")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(selection: $selectedCoworker) {
                    ForEach(coworkerOptions) { option in
                        Text(option.label)
                            .tag(option)
                    }
                } label: {
                    HStack {
                        Text(selectedCoworkerDisplay)
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

    private let weekdayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

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
                        title: "工作负载趋势",
                        subtitle: stats.totalTrackedDays == 0 ? "暂无排班记录" : "按周汇总出勤班次"
                    ) {
                        workloadTrendChart(stats.workloadTrend)
                    }

                    StatsCard(
                        title: "共事频次排行榜",
                        subtitle: stats.coworkerCounts.isEmpty ? "暂无共事记录" : "统计班次共事次数（前 10）"
                    ) {
                        coworkerFrequencyChart(stats.coworkerCounts)
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
                        coworkerHeatmap(stats.coworkerShiftMatrix)
                    }

                    StatsCard(
                        title: "出勤贡献图",
                        subtitle: stats.contributionDays.isEmpty ? "暂无排班记录" : "仿 GitHub，每日排班一览"
                    ) {
                        contributionHeatmap(stats.contributionDays)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("统计")
        }
        .onChange(of: store.colleagues) { _ in
            if case .person(let name) = selectedCoworker, !store.colleagues.contains(name) {
                selectedCoworker = .all
            }
        }
    }

    private enum TimeRangeOption: String, CaseIterable, Identifiable {
        case all
        case last30Days
        case last90Days
        case last365Days

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "全部"
            case .last30Days:
                return "近30天"
            case .last90Days:
                return "近90天"
            case .last365Days:
                return "近一年"
            }
        }

        func lowerBound(referenceDate: Date, calendar: Calendar) -> Date? {
            let startOfDay = calendar.startOfDay(for: referenceDate)
            switch self {
            case .all:
                return nil
            case .last30Days:
                return calendar.date(byAdding: .day, value: -29, to: startOfDay) ?? startOfDay
            case .last90Days:
                return calendar.date(byAdding: .day, value: -89, to: startOfDay) ?? startOfDay
            case .last365Days:
                return calendar.date(byAdding: .day, value: -364, to: startOfDay) ?? startOfDay
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
    private func workloadTrendChart(_ data: [RosterStatistics.WorkloadPoint]) -> some View {
        if data.isEmpty {
            StatsPlaceholder(message: "暂无趋势数据")
        } else {
            Chart {
                ForEach(data) { point in
                    AreaMark(
                        x: .value("周", point.weekStart),
                        y: .value("出勤天数", point.totalShifts)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.25))
                }

                ForEach(data) { point in
                    LineMark(
                        x: .value("周", point.weekStart),
                        y: .value("出勤天数", point.totalShifts)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)
                }

                ForEach(data) { point in
                    PointMark(
                        x: .value("周", point.weekStart),
                        y: .value("出勤天数", point.totalShifts)
                    )
                    .foregroundStyle(Color.accentColor)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(6, max(1, data.count)))) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let dateValue = value.as(Date.self) {
                            Text(dateValue, format: .dateTime.month().day())
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 260)
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

    @ViewBuilder
    private func contributionHeatmap(_ data: [RosterStatistics.ContributionDay]) -> some View {
        if data.isEmpty {
            StatsPlaceholder(message: "暂无排班记录")
        } else {
            Chart(data) { day in
                RectangleMark(
                    x: .value("周", day.weekStart),
                    y: .value("星期", weekdayLabels[day.weekdayIndex])
                )
                .foregroundStyle(contributionColor(for: day.level))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(6, max(1, data.count / 7)))) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let dateValue = value.as(Date.self) {
                            Text(dateValue, format: .dateTime.month().day())
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: weekdayLabels) { value in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .frame(minHeight: 180)
                    .padding(.vertical, 8)
            }
            .frame(height: 220)
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

    private func contributionColor(for level: Int) -> Color {
        switch level {
        case 0:
            return Color(.systemFill)
        case 1:
            return Color.green.opacity(0.35)
        case 2:
            return Color.green.opacity(0.6)
        default:
            return Color.green
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

    struct WorkloadPoint: Identifiable {
        let weekStart: Date
        let totalShifts: Int
        var id: Date { weekStart }
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

    struct ContributionDay: Identifiable {
        let date: Date
        let weekStart: Date
        let weekdayIndex: Int
        let level: Int
        var id: Date { date }
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
        return ShiftType.allCases.map { ShiftCount(shift: $0, count: grouped[$0] ?? 0) }
    }

    var workloadTrend: [WorkloadPoint] {
        var accumulator: [Date: Int] = [:]
        for (date, shift) in shiftAssignments {
            let weekStart = calendar.startOfWeek(for: date)
            let contribution = shift.isWorkingShift ? 1 : 0
            accumulator[weekStart, default: 0] += contribution
        }
        return accumulator
            .map { WorkloadPoint(weekStart: $0.key, totalShifts: $0.value) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    var coworkerCounts: [CoworkerCount] {
        var counts: [String: Int] = [:]
        for (date, members) in coworkerAssignments {
            let shift = shiftAssignments[date] ?? .none
            guard shift.allowsCoworkers else { continue }
            for name in members {
                counts[name, default: 0] += 1
            }
        }
        let sorted = counts
            .map { CoworkerCount(name: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.name < $1.name
                }
                return $0.count > $1.count
            }
        return Array(sorted.prefix(10))
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

    var contributionDays: [ContributionDay] {
        guard let minDate = shiftAssignments.keys.min(),
              let maxDate = shiftAssignments.keys.max() else {
            return []
        }
        var results: [ContributionDay] = []
        var cursor = calendar.startOfDay(for: minDate)
        let last = calendar.startOfDay(for: maxDate)
        while cursor <= last {
            let shift = shiftAssignments[cursor] ?? .none
            let weekStart = calendar.startOfWeek(for: cursor)
            let weekday = calendar.weekdayIndex(for: cursor)
            let level = shift.contributionLevel
            results.append(
                ContributionDay(
                    date: cursor,
                    weekStart: weekStart,
                    weekdayIndex: weekday,
                    level: level
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return results
    }
}

extension ShiftType {
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

    var contributionLevel: Int {
        switch self {
        case .none, .rest:
            return 0
        case .morning:
            return 1
        case .afternoon:
            return 2
        case .evening:
            return 3
        }
    }
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }

    func weekdayIndex(for date: Date) -> Int {
        let weekday = component(.weekday, from: date)
        return (weekday - firstWeekday + 7) % 7
    }
}
