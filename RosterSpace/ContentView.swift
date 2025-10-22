//
//  ContentView.swift
//  RosterSpace
//
//  Created by mengfs on 10/22/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CalendarScreen()
                .tabItem {
                    Label("日历", systemImage: "calendar")
                }

            SettingsScreen()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
        }
    }
}

struct CalendarScreen: View {
    private let calendar = Calendar.mondayFirst
    private let monthFormatter: DateFormatter

    @State private var displayMonth: Date
    @State private var shiftAssignments: [Date: ShiftType]
    @State private var selectedDate: Date?
    @State private var isManagingShift = false

    init() {
        let calendar = Calendar.mondayFirst
        let initialMonth = calendar.startOfMonth(for: Date())
        _displayMonth = State(initialValue: initialMonth)
        _shiftAssignments = State(initialValue: ShiftType.sampleAssignments(for: initialMonth, calendar: calendar))

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM yyyy"
        monthFormatter = formatter
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                monthHeader
                weekdayHeader
                calendarGrid
                Spacer()
            }
            .padding()
            .navigationTitle("")
            .gesture(monthSwipeGesture)
            .sheet(isPresented: $isManagingShift) {
                if let selectedDate {
                    let normalizedDate = calendar.startOfDay(for: selectedDate)
                    ShiftManagementView(
                        date: normalizedDate,
                        shift: Binding(
                            get: { shiftAssignments[normalizedDate] ?? .none },
                            set: { shiftAssignments[normalizedDate] = $0 }
                        ),
                        calendar: calendar
                    )
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(monthFormatter.string(from: displayMonth))
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            if let selectedDate {
                let isTodaySelected = calendar.isDateInToday(selectedDate)

                if !isTodaySelected {
                    Button {
                        jumpToToday()
                    } label: {
                        Text("今")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .stroke(Color.accentColor, lineWidth: 1.2)
                    )
                }

                Button {
                    isManagingShift = true
                } label: {
                    Image(systemName: "line.3.horizontal.circle")
                        .imageScale(.large)
                }
                .accessibilityLabel("管理班次")
            }
        }
    }

    private var weekdayHeader: some View {
        let titles = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return HStack {
            ForEach(titles, id: \.self) { title in
                Text(title)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        let dates = calendarGridDates(for: displayMonth)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                if let date {
                    let normalized = calendar.startOfDay(for: date)
                    let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                    DayCell(
                        date: date,
                        shift: shiftAssignments[normalized] ?? .none,
                        isSelected: isSelected,
                        calendar: calendar
                    ) {
                        handleSelect(date: date)
                    }
                } else {
                    Color.clear
                        .frame(height: DayCell.height)
                        .id(index)
                }
            }
        }
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 24 else {
                    return
                }

                guard abs(horizontal) > abs(vertical) * 0.6 else {
                    return
                }

                if horizontal < 0 {
                    changeMonth(by: 1)
                } else {
                    changeMonth(by: -1)
                }
            }
    }

private func jumpToToday() {
        let today = calendar.startOfDay(for: Date())
        displayMonth = calendar.startOfMonth(for: today)
        selectedDate = today
        ensureAssignmentsExist(for: displayMonth)
    }

    private func changeMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayMonth) else { return }
        displayMonth = calendar.startOfMonth(for: newMonth)
        ensureAssignmentsExist(for: displayMonth)
        if let selectedDate, !calendar.isDate(selectedDate, equalTo: displayMonth, toGranularity: .month) {
            self.selectedDate = nil
        }
    }

    private func handleSelect(date: Date) {
        let normalized = calendar.startOfDay(for: date)
        withAnimation {
            selectedDate = normalized
        }
        if shiftAssignments[normalized] == nil {
            shiftAssignments[normalized] = .none
        }
    }

    private func ensureAssignmentsExist(for month: Date) {
        let monthStart = calendar.startOfMonth(for: month)
        for day in calendar.daysInMonth(for: monthStart) {
            let normalized = calendar.startOfDay(for: day)
            if shiftAssignments[normalized] == nil {
                shiftAssignments[normalized] = ShiftType.defaultAssignment(for: day, calendar: calendar)
            }
        }
    }

    private func calendarGridDates(for month: Date) -> [Date?] {
        let monthStart = calendar.startOfMonth(for: month)
        let days = calendar.daysInMonth(for: monthStart)
        let prefix = calendar.firstWeekdayOffset(for: monthStart)
        var grid: [Date?] = Array(repeating: nil, count: prefix)
        grid.append(contentsOf: days.map { $0 })
        let remainder = grid.count % 7
        if remainder != 0 {
            grid.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
        }
        return grid
    }
}

struct SettingsScreen: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("个人中心功能敬请期待")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("我的")
        }
    }
}

private struct DayCell: View {
    static let height: CGFloat = 80

    let date: Date
    let shift: ShiftType
    let isSelected: Bool
    let calendar: Calendar
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .padding(.horizontal, -4)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(.horizontal, -4)
                }

                VStack {
                    Spacer(minLength: 4)

                    Text(dayNumber)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.regular)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let badge = shift.badgeStyle {
                    VStack {
                        Spacer()
                        Text(badge.text)
                            .font(.system(size: 10, weight: .semibold))
                            .fontWeight(.semibold)
                            .foregroundColor(badge.textColor)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(
                                Capsule()
                                    .fill(badge.backgroundColor)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                }

                if shift.isRestDay {
                    Text("休")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Color.green)
                        )
                        .padding(.top, 12)
                        .padding(.trailing, -2)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(height: Self.height)
    }

    private var dayNumber: String {
        String(calendar.component(.day, from: date))
    }
}

private struct ShiftManagementView: View {
    let date: Date
    @Binding var shift: ShiftType
    let calendar: Calendar
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("选择班次")) {
                    ForEach(ShiftType.managementOptions) { option in
                        HStack {
                            Text(option.displayName)
                            Spacer()
                            if option == shift {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            shift = option
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        shift = .none
                    } label: {
                        Text("清除班次")
                    }
                }
            }
            .navigationTitle(dateFormatter.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }
}

private enum ShiftType: String, CaseIterable, Identifiable {
    case none
    case rest
    case morning
    case afternoon
    case evening

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "未排班"
        case .rest:
            return "休息"
        case .morning:
            return "早班"
        case .afternoon:
            return "中班"
        case .evening:
            return "晚班"
        }
    }

    var badgeStyle: ShiftBadgeStyle? {
        switch self {
        case .morning:
            return ShiftBadgeStyle(text: "早班", textColor: .orange, backgroundColor: Color.orange.opacity(0.2))
        case .afternoon:
            return ShiftBadgeStyle(text: "中班", textColor: .red, backgroundColor: Color.red.opacity(0.2))
        case .evening:
            return ShiftBadgeStyle(text: "晚班", textColor: .blue, backgroundColor: Color.blue.opacity(0.2))
        default:
            return nil
        }
    }

    var isRestDay: Bool {
        self == .rest
    }

    static var managementOptions: [ShiftType] {
        [.morning, .afternoon, .evening, .rest]
    }

    static func sampleAssignments(for month: Date, calendar: Calendar) -> [Date: ShiftType] {
        var assignments: [Date: ShiftType] = [:]
        let days = calendar.daysInMonth(for: month)
        for day in days {
            let normalized = calendar.startOfDay(for: day)
            assignments[normalized] = defaultAssignment(for: day, calendar: calendar)
        }
        return assignments
    }

    static func defaultAssignment(for date: Date, calendar: Calendar) -> ShiftType {
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 {
            return .rest
        }

        switch calendar.component(.day, from: date) % 3 {
        case 0:
            return .morning
        case 1:
            return .afternoon
        default:
            return .evening
        }
    }
}

private struct ShiftBadgeStyle {
    let text: String
    let textColor: Color
    let backgroundColor: Color
}

private extension Calendar {
    static var mondayFirst: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }

    func daysInMonth(for date: Date) -> [Date] {
        let monthStart = startOfMonth(for: date)
        guard let range = range(of: .day, in: .month, for: monthStart) else { return [] }
        return range.compactMap { day -> Date? in
            self.date(byAdding: .day, value: day - 1, to: monthStart)
        }
    }

    func firstWeekdayOffset(for date: Date) -> Int {
        let weekday = component(.weekday, from: date)
        let offset = (weekday - firstWeekday + 7) % 7
        return offset
    }
}

#Preview {
    ContentView()
}
