//
//  ContentView.swift
//  RosterSpace
//
//  Created by mengfs on 10/22/25.
//

import SwiftUI

struct ContentView: View {
    @State private var colleagues: [String] = []

    var body: some View {
        TabView {
            CalendarScreen(colleagues: $colleagues)
                .tabItem {
                    Label("日历", systemImage: "calendar")
                }

            SettingsScreen(colleagues: $colleagues)
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
        }
    }
}

struct CalendarScreen: View {
    @Binding private var colleagues: [String]
    private let calendar = Calendar.mondayFirst
    private let monthFormatter: DateFormatter
    private let dayFormatter: DateFormatter

    @State private var displayMonth: Date
    @State private var shiftAssignments: [Date: ShiftType]
    @State private var selectedDate: Date?
    @State private var isManagingShift = false
    @State private var coworkerAssignments: [Date: Set<String>]

    init(colleagues: Binding<[String]>) {
        self._colleagues = colleagues
        let calendar = Calendar.mondayFirst
        let initialMonth = calendar.startOfMonth(for: Date())
        _displayMonth = State(initialValue: initialMonth)
        _shiftAssignments = State(initialValue: ShiftType.sampleAssignments(for: initialMonth, calendar: calendar))
        _coworkerAssignments = State(initialValue: [:])

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM yyyy"
        monthFormatter = formatter

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "zh_CN")
        dayFormatter.calendar = calendar
        dayFormatter.dateFormat = "M月d日"
        self.dayFormatter = dayFormatter
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DynamicShiftBackdrop(shift: activeShift)

                VStack(spacing: 16) {
                    monthHeader
                    weekdayHeader
                    calendarGrid
                    coworkerSummary
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("")
            .gesture(monthSwipeGesture)
            .sheet(isPresented: $isManagingShift) {
                if let selectedDate {
                    let normalizedDate = calendar.startOfDay(for: selectedDate)
                    ShiftManagementView(
                        date: normalizedDate,
                        shift: Binding(
                            get: { shiftAssignments[normalizedDate] ?? .none },
                            set: {
                                shiftAssignments[normalizedDate] = $0
                                if !$0.allowsCoworkers {
                                    coworkerAssignments[normalizedDate] = Set<String>()
                                }
                            }
                        ),
                        coworkers: Binding(
                            get: { coworkerAssignments[normalizedDate] ?? Set<String>() },
                            set: { coworkerAssignments[normalizedDate] = $0 }
                        ),
                        colleagues: colleagues,
                        calendar: calendar
                    )
                }
            }
        }
        .onChange(of: colleagues) { _ in
            pruneCoworkerSelections()
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

    private var activeShift: ShiftType {
        if let selectedDate {
            let normalized = calendar.startOfDay(for: selectedDate)
            return shiftAssignments[normalized] ?? .none
        }
        let today = calendar.startOfDay(for: Date())
        return shiftAssignments[today] ?? .none
    }

    @ViewBuilder
    private var coworkerSummary: some View {
        if let selectedDate {
            let normalized = calendar.startOfDay(for: selectedDate)
            if let set = coworkerAssignments[normalized], !set.isEmpty {
                let names = set.sorted()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(dayFormatter.string(from: normalized))
                            .font(.headline)
                    }

                    Text(names.joined(separator: "、"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
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
        if coworkerAssignments[today] == nil {
            coworkerAssignments[today] = Set<String>()
        }
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
            shiftAssignments[normalized] = ShiftType.none
        }
        if coworkerAssignments[normalized] == nil {
            coworkerAssignments[normalized] = Set<String>()
        }
    }

    private func ensureAssignmentsExist(for month: Date) {
        let monthStart = calendar.startOfMonth(for: month)
        for day in calendar.daysInMonth(for: monthStart) {
            let normalized = calendar.startOfDay(for: day)
            if shiftAssignments[normalized] == nil {
                shiftAssignments[normalized] = ShiftType.defaultAssignment(for: day, calendar: calendar)
            }
            if coworkerAssignments[normalized] == nil {
                coworkerAssignments[normalized] = Set<String>()
            }
        }
    }

    private func pruneCoworkerSelections() {
        let validNames = Set(colleagues)
        for (date, selections) in coworkerAssignments {
            let filtered = selections.filter { validNames.contains($0) }
            coworkerAssignments[date] = Set(filtered)
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
    @Binding var colleagues: [String]
    @State private var newColleagueName: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("添加同事")) {
                    HStack {
                        TextField("输入姓名", text: $newColleagueName)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)

                        Button("添加") {
                            addColleague()
                        }
                        .disabled(!canAddColleague)
                    }
                }

                Section(header: Text("同事名单")) {
                    if colleagues.isEmpty {
                        Text("暂无同事，请先添加。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(colleagues, id: \.self) { colleague in
                            Text(colleague)
                        }
                        .onDelete(perform: removeColleagues)
                    }
                }
            }
            .navigationTitle("我的")
            .toolbar {
                EditButton()
            }
        }
    }

    private var canAddColleague: Bool {
        let trimmed = newColleagueName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        return !trimmed.isEmpty && !colleagues.contains(where: { $0.lowercased() == normalized })
    }

    private func addColleague() {
        let trimmed = newColleagueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.lowercased()
        guard !colleagues.contains(where: { $0.lowercased() == normalized }) else { return }
        colleagues.append(trimmed)
        newColleagueName = ""
    }

    private func removeColleagues(at offsets: IndexSet) {
        colleagues.remove(atOffsets: offsets)
    }
}

// MARK: - Dynamic Shift Backdrop

private struct DynamicShiftBackdrop: View {
    let shift: ShiftType

    var body: some View {
        GeometryReader { proxy in
            let scene = shift.sceneConfig
            ZStack {
                GradientLayer(scene: scene)
                ParticlesLayer(scene: scene, size: proxy.size)
                LightRaysLayer(scene: scene)
            }
            .ignoresSafeArea()
        }
    }
}

private struct GradientLayer: View {
    let scene: ShiftSceneConfig

    var body: some View {
        LinearGradient(
            colors: scene.gradient.colors,
            startPoint: scene.gradient.start,
            endPoint: scene.gradient.end
        )
        .overlay(
            RadialGradient(
                colors: scene.gradient.overlayColors,
                center: .top,
                startRadius: 0,
                endRadius: 600
            )
            .opacity(0.35)
        )
        .ignoresSafeArea()
    }
}

private struct ParticlesLayer: View {
    let scene: ShiftSceneConfig
    let size: CGSize

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, canvasSize in
                let time = timeline.date.timeIntervalSinceReferenceDate
                context.addFilter(.blur(radius: scene.particleBlur))
                context.blendMode = .plusLighter
                for index in 0..<scene.particleCount {
                    let hashSeed = UInt64(truncatingIfNeeded: index &+ 1)
                        &* 0x9E3779B97F4A7C15
                        &+ 0xBF58476D1CE4E5B9
                    var generator = SeededGenerator(seed: hashSeed)
                    let baseX = Double.random(in: 0...1, using: &generator)
                    let baseY = Double.random(in: 0...1, using: &generator)
                    let amplitude = Double.random(in: 0.05...0.18, using: &generator) * Double(min(canvasSize.width, canvasSize.height))
                    let sizeFactor = Double.random(in: 0.5...1.2, using: &generator)
                    let phase = Double.random(in: 0...(2 * .pi), using: &generator)
                    let swirl = Double.random(in: 0.2...0.8, using: &generator)

                    let progress = time * scene.particleSpeed + phase
                    let x = baseX * canvasSize.width + sin(progress) * amplitude
                    let yBase = baseY * canvasSize.height
                    let y = yBase - progress * scene.verticalLift * canvasSize.height + cos(progress * swirl) * amplitude * 0.25
                    let heightRange = canvasSize.height + 120
                    let yWrapped = (y + heightRange).truncatingRemainder(dividingBy: heightRange) - 60
                    let xRange = canvasSize.width + 120
                    let xWrapped = (x + xRange).truncatingRemainder(dividingBy: xRange) - 60

                    let particleRect = CGRect(
                        x: xWrapped,
                        y: yWrapped,
                        width: CGFloat(scene.particleBaseSize * sizeFactor),
                        height: CGFloat(scene.particleBaseSize * sizeFactor)
                    )

                    let opacity = 0.25 + 0.5 * (sin(progress) + 1) / 2
                    context.opacity = opacity
                    context.fill(Path(ellipseIn: particleRect), with: .color(scene.particleColor))
                }
            }
        }
    }
}

private struct LightRaysLayer: View {
    let scene: ShiftSceneConfig

    var body: some View {
        TimelineView(.animation) { timeline in
            LightRaysFrame(
                scene: scene,
                time: timeline.date.timeIntervalSinceReferenceDate
            )
        }
        .allowsHitTesting(false)
    }
}

private struct LightRaysFrame: View {
    let scene: ShiftSceneConfig
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            guard scene.lightOpacity > 0, scene.lightCount > 0 else { return }
            let rect = CGRect(origin: .zero, size: size)
            let baseHeight = rect.height * 1.6
            let baseWidth = rect.width * 0.45
            context.addFilter(.blur(radius: scene.lightBlur))
            context.blendMode = .screen

            for beamIndex in 0..<scene.lightCount {
                let phase = Double(beamIndex) / Double(scene.lightCount)
                let swing = sin((time * scene.lightSpeed) + phase * .pi * 2) * scene.lightSwing
                let angle = CGFloat(swing)
                let widthScale = 0.6 + 0.4 * Double(beamIndex + 1) / Double(scene.lightCount)
                let beamWidth = CGFloat(widthScale) * baseWidth
                let beamHeight = baseHeight * (0.85 + 0.15 * CGFloat(beamIndex) / CGFloat(scene.lightCount))
                let cornerRadius = beamWidth * CGFloat(0.35)

                var beam = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .path(in: CGRect(x: -beamWidth / 2, y: -beamHeight, width: beamWidth, height: beamHeight))

                var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY * 0.9)
                transform = transform.rotated(by: angle)
                beam = beam.applying(transform)

                let pulse = 0.8 + 0.2 * sin(time * scene.lightSpeed * 1.5 + phase * .pi)
                context.opacity = scene.lightOpacity * pulse

                let bounds = beam.boundingRect
                let gradient = Gradient(stops: [
                    .init(color: scene.lightColor.opacity(0), location: 0),
                    .init(color: scene.lightColor.opacity(scene.lightOpacity), location: 0.5),
                    .init(color: scene.lightColor.opacity(0), location: 1)
                ])
                context.fill(
                    beam,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                        endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
                    )
                )
            }
        }
    }
}

private struct ShiftSceneConfig {
    struct GradientSpec {
        let colors: [Color]
        let overlayColors: [Color]
        let start: UnitPoint
        let end: UnitPoint
    }

    let gradient: GradientSpec
    let particleColor: Color
    let particleCount: Int
    let particleSpeed: Double
    let particleBaseSize: Double
    let particleBlur: CGFloat
    let verticalLift: Double
    let lightColor: Color
    let lightOpacity: Double
    let lightSwing: Double
    let lightSpeed: Double
    let lightCount: Int
    let lightBlur: CGFloat
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private extension ShiftType {
    var sceneConfig: ShiftSceneConfig {
        switch self {
        case .morning:
            return ShiftSceneConfig(
                gradient: .init(
                    colors: [Color(hex: 0xFFE28D), Color(hex: 0xD5F4FF)],
                    overlayColors: [Color.white.opacity(0.35), Color.clear],
                    start: .bottom,
                    end: .top
                ),
                particleColor: Color.white.opacity(0.4),
                particleCount: 110,
                particleSpeed: 0.12,
                particleBaseSize: 18,
                particleBlur: 6,
                verticalLift: 0.04,
                lightColor: Color.white,
                lightOpacity: 0.55,
                lightSwing: 0.35,
                lightSpeed: 0.85,
                lightCount: 5,
                lightBlur: 26
            )
        case .afternoon:
            return ShiftSceneConfig(
                gradient: .init(
                    colors: [Color(hex: 0xFFB067), Color(hex: 0xFFF5E0)],
                    overlayColors: [Color.white.opacity(0.28), Color.clear],
                    start: .bottom,
                    end: .top
                ),
                particleColor: Color.orange.opacity(0.35),
                particleCount: 130,
                particleSpeed: 0.18,
                particleBaseSize: 16,
                particleBlur: 5,
                verticalLift: 0.06,
                lightColor: Color.white,
                lightOpacity: 0.65,
                lightSwing: 0.42,
                lightSpeed: 1.05,
                lightCount: 6,
                lightBlur: 24
            )
        case .evening:
            return ShiftSceneConfig(
                gradient: .init(
                    colors: [Color(hex: 0x2D3A6A), Color(hex: 0x4A5AA5)],
                    overlayColors: [Color(hex: 0x90A6FF).opacity(0.4), Color.clear],
                    start: .bottom,
                    end: .top
                ),
                particleColor: Color.white.opacity(0.24),
                particleCount: 140,
                particleSpeed: 0.08,
                particleBaseSize: 14,
                particleBlur: 8,
                verticalLift: 0.03,
                lightColor: Color(hex: 0x90A6FF),
                lightOpacity: 0.45,
                lightSwing: 0.28,
                lightSpeed: 0.7,
                lightCount: 4,
                lightBlur: 34
            )
        default:
            return ShiftSceneConfig(
                gradient: .init(
                    colors: [Color(hex: 0xEEF1F6), Color(hex: 0xF6F7FA)],
                    overlayColors: [Color.white.opacity(0.2), Color.clear],
                    start: .top,
                    end: .bottom
                ),
                particleColor: Color.gray.opacity(0.18),
                particleCount: 60,
                particleSpeed: 0.05,
                particleBaseSize: 12,
                particleBlur: 4,
                verticalLift: 0.02,
                lightColor: Color.white.opacity(0.8),
                lightOpacity: 0.3,
                lightSwing: 0.2,
                lightSpeed: 0.55,
                lightCount: 3,
                lightBlur: 20
            )
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
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
    @Binding var coworkers: Set<String>
    let colleagues: [String]
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

                coworkersSection
                    .animation(.default, value: shift)

                Section {
                    Button(role: .destructive) {
                        shift = .none
                        coworkers.removeAll()
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
            .onChange(of: shift) { newValue in
                if !newValue.allowsCoworkers {
                    coworkers.removeAll()
                }
            }
        }
    }

    @ViewBuilder
    private var coworkersSection: some View {
        Section(header: Text("共事成员")) {
            if shift.isRestDay {
                Text("休息日无需选择共事成员。")
                    .foregroundStyle(.secondary)
            } else if shift == .none {
                Text("请先选择班次后再设置共事成员。")
                    .foregroundStyle(.secondary)
            } else if colleagues.isEmpty {
                Text("暂无同事名单，请前往“我的”页面添加。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(colleagues, id: \.self) { colleague in
                    HStack {
                        Text(colleague)
                        Spacer()
                        if coworkers.contains(colleague) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleCoworker(colleague)
                    }
                }

                if coworkers.isEmpty {
                    Text("轻点姓名以选择共事成员。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func toggleCoworker(_ name: String) {
        if coworkers.contains(name) {
            coworkers.remove(name)
        } else {
            coworkers.insert(name)
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

    var allowsCoworkers: Bool {
        switch self {
        case .morning, .afternoon, .evening:
            return true
        default:
            return false
        }
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
