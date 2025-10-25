//
//  ContentView.swift
//  RosterSpace
//
//  Created by mengfs on 10/22/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    private var alertBinding: Binding<AppViewModel.AppAlert?> {
        Binding(
            get: { appViewModel.alert },
            set: { appViewModel.alert = $0 }
        )
    }

    var body: some View {
        TabView {
            CalendarScreen()
                .tabItem {
                    Label("日历", systemImage: "calendar")
                }

            StatsScreen()
                .tabItem {
                    Label("统计", systemImage: "chart.bar.xaxis")
                }

            SettingsScreen()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
        }
        .alert(item: alertBinding) { alert in
            Alert(title: Text(alert.message))
        }
    }
}

struct CalendarScreen: View {
    @EnvironmentObject private var store: RosterDataStore
    private let calendar = Calendar.mondayFirst

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar.mondayFirst
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar.mondayFirst
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    @State private var displayMonth: Date = Calendar.mondayFirst.startOfMonth(for: Date())
    @State private var selectedDate: Date?
    @State private var isManagingShift = false

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
                            get: { store.shift(on: normalizedDate) },
                            set: { store.setShift($0, for: normalizedDate) }
                        ),
                        coworkers: Binding(
                            get: { store.coworkers(on: normalizedDate) },
                            set: { store.setCoworkers($0, for: normalizedDate) }
                        ),
                        calendar: calendar
                    )
                }
            }
        }
        .onAppear {
            store.ensureMonthAvailable(containing: displayMonth)
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
                        shift: store.shift(on: normalized),
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
            store.ensureDayAvailable(normalized)
            return store.shift(on: normalized)
        }
        let today = calendar.startOfDay(for: Date())
        store.ensureDayAvailable(today)
        return store.shift(on: today)
    }

    @ViewBuilder
    private var coworkerSummary: some View {
        if let selectedDate {
            let normalized = calendar.startOfDay(for: selectedDate)
            let selections = store.coworkers(on: normalized)
            if !selections.isEmpty {
                let names = selections.sorted()
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
                        .fill(.thinMaterial.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12))
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
        store.ensureMonthAvailable(containing: displayMonth)
        store.ensureDayAvailable(today)
    }

    private func changeMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayMonth) else { return }
        displayMonth = calendar.startOfMonth(for: newMonth)
        store.ensureMonthAvailable(containing: displayMonth)
        if let selectedDate, !calendar.isDate(selectedDate, equalTo: displayMonth, toGranularity: .month) {
            self.selectedDate = nil
        }
    }

    private func handleSelect(date: Date) {
        let normalized = calendar.startOfDay(for: date)
        withAnimation {
            selectedDate = normalized
        }
        store.ensureDayAvailable(normalized)
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
    @EnvironmentObject private var store: RosterDataStore
    @EnvironmentObject private var appViewModel: AppViewModel
    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountManagementView()
                    } label: {
                        AccountEntryRow()
                    }
                }

                syncSection

                Section {
                    NavigationLink {
                        ColleagueManagementView()
                    } label: {
                        Label("同事名单管理", systemImage: "person.2.badge.gearshape")
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("我的")
        }
    }

    private var syncSection: some View {
        Section(header: Text("同步状态")) {
            HStack {
                Label("Supabase 同步", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                if appViewModel.isSyncing {
                    ProgressView()
                } else if let last = appViewModel.lastSuccessfulSyncAt {
                    Text(relativeDateFormatter.localizedString(for: last, relativeTo: Date()))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("等待首次同步")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task {
                    await appViewModel.refreshRosterSnapshot()
                }
            } label: {
                Text("手动刷新")
            }
            .disabled(appViewModel.isSyncing)
        }
    }
}

private struct ColleagueManagementView: View {
    @EnvironmentObject private var store: RosterDataStore
    @State private var newColleagueName: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var isInputPresented = false

    var body: some View {
        List {
            Section(header: Text("添加同事")) {
                Button {
                    isInputPresented = true
                    DispatchQueue.main.async {
                        isInputFocused = true
                    }
                } label: {
                    HStack {
                        Label("添加新同事", systemImage: "plus.circle.fill")
                            .font(.headline)
                        Spacer()
                        if !newColleagueName.isEmpty {
                            Text(newColleagueName)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "keyboard")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isInputPresented || !newColleagueName.isEmpty || isInputFocused {
                    HStack(spacing: 12) {
                        TextField("输入姓名", text: $newColleagueName)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .focused($isInputFocused)
                            .submitLabel(.done)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .onSubmit { addColleague() }

                        Button("添加") { addColleague() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canAddColleague)

                        Button(action: dismissInput) {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            Section(header: Text("同事名单")) {
                if store.colleagues.isEmpty {
                    Text("暂无同事，请先添加。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.colleagues, id: \.self) { colleague in
                        Text(colleague)
                    }
                    .onDelete(perform: removeColleagues)
                }
            }
        }
        .navigationTitle("同事名单管理")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("关闭") { dismissInput() }
            }
        }
    }

    private var canAddColleague: Bool {
        let trimmed = newColleagueName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        return !trimmed.isEmpty && !store.colleagues.contains(where: { $0.lowercased() == normalized })
    }

    private func addColleague() {
        let trimmed = newColleagueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.lowercased()
        guard !store.colleagues.contains(where: { $0.lowercased() == normalized }) else { return }
        store.addColleague(trimmed)
        newColleagueName = ""
        dismissInput()
    }

    private func removeColleagues(at offsets: IndexSet) {
        store.removeColleagues(at: offsets)
    }

    private func dismissInput() {
        isInputFocused = false
        isInputPresented = false
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
                if scene.cloudsEnabled {
                    CloudLayer(scene: scene)
                }
                if scene.sunEnabled {
                    SunLayer(scene: scene)
                }
                if scene.starsEnabled {
                    StarfieldLayer(scene: scene)
                }
                if scene.shootingStarsEnabled {
                    ShootingStarLayer(scene: scene)
                }
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

private struct CloudLayer: View {
    let scene: ShiftSceneConfig

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard scene.cloudsEnabled, scene.cloudCount > 0 else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                context.blendMode = .screen
                for index in 0..<scene.cloudCount {
                    let hashSeed = UInt64(truncatingIfNeeded: index &+ 17) &* 0xBF58476D1CE4E5B9 &+ 0x94D049BB133111EB
                    var generator = SeededGenerator(seed: hashSeed)
                    let baseX = Double.random(in: 0...1, using: &generator)
                    let baseY = Double.random(in: 0.02...0.35, using: &generator)
                    let scale = Double.random(in: 0.7...1.15, using: &generator)
                    let speed = scene.cloudSpeed * Double.random(in: 0.4...0.8, using: &generator)
                    let offset = (baseX + time * speed).truncatingRemainder(dividingBy: 1)
                    let x = CGFloat(offset) * (size.width + 200) - 100
                    let y = CGFloat(baseY) * size.height * 0.7
                    let cloudWidth = size.width * 0.35 * CGFloat(scale)
                    let cloudHeight = cloudWidth * 0.45

                    let cloudRect = CGRect(x: x, y: y, width: cloudWidth, height: cloudHeight)
                    let path = cloudPath(in: cloudRect, generator: &generator)
                    context.opacity = scene.cloudOpacity
                    context.addFilter(.blur(radius: 12))
                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(stops: [
                            .init(color: scene.cloudColor.opacity(0.25), location: 0),
                            .init(color: scene.cloudColor.opacity(0.6), location: 0.4),
                            .init(color: scene.cloudColor.opacity(0.85), location: 1)
                        ]),
                        startPoint: CGPoint(x: cloudRect.midX, y: cloudRect.minY),
                        endPoint: CGPoint(x: cloudRect.midX, y: cloudRect.maxY)
                    )
                    context.fill(path, with: shading)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cloudPath(in rect: CGRect, generator: inout SeededGenerator) -> Path {
        var path = Path()
        let circles = [
            CGRect(x: rect.minX, y: rect.midY - rect.height * 0.25, width: rect.width * 0.45, height: rect.height * 0.75),
            CGRect(x: rect.midX - rect.width * 0.25, y: rect.minY, width: rect.width * 0.55, height: rect.height * 0.9),
            CGRect(x: rect.maxX - rect.width * 0.45, y: rect.midY - rect.height * 0.3, width: rect.width * 0.5, height: rect.height * 0.8)
        ]
        for circle in circles {
            path.addEllipse(in: circle)
        }
        let baseRect = CGRect(x: rect.minX + rect.width * 0.1, y: rect.midY, width: rect.width * 0.8, height: rect.height * 0.6)
        path.addRoundedRect(in: baseRect, cornerSize: CGSize(width: rect.height * 0.3, height: rect.height * 0.25))
        return path
    }
}

private struct SunLayer: View {
    let scene: ShiftSceneConfig

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard scene.sunEnabled else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                let progress = (time * scene.sunSpeed).truncatingRemainder(dividingBy: 1)
                let angle = Double.pi * (progress - 0.5)
                let baseRadius = size.width * 0.12
                let arcHeight = size.height * scene.sunArcHeight
                let centerX = size.width * 0.5 + CGFloat(cos(angle)) * size.width * 0.35
                let centerY = size.height * 0.75 - CGFloat(sin(angle)) * arcHeight

                let fadeStart: Double = 0.8
                let fadeProgress: Double
                if progress >= fadeStart {
                    fadeProgress = max(0, 1 - (progress - fadeStart) / (1 - fadeStart))
                } else {
                    fadeProgress = 1
                }
                let easedFade = pow(fadeProgress, 1.4)
                let radius = baseRadius * CGFloat(1 + (1 - easedFade) * 0.9)
                let sunRect = CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)

                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 18))
                    layer.fill(
                        Path(ellipseIn: sunRect.insetBy(dx: -radius * 0.6, dy: -radius * 0.6)),
                        with: .radialGradient(
                            Gradient(colors: [
                                scene.sunGlowColor.opacity(0.55 * easedFade),
                                scene.sunGlowColor.opacity(0)
                            ]),
                            center: CGPoint(x: centerX, y: centerY),
                            startRadius: radius * 0.2,
                            endRadius: radius * 1.6
                        )
                    )
                }

                context.fill(
                    Path(ellipseIn: sunRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            scene.sunColor.opacity(easedFade),
                            scene.sunColor.opacity(0.2 * easedFade)
                        ]),
                        center: CGPoint(x: centerX, y: centerY),
                        startRadius: radius * 0.1,
                        endRadius: radius
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct StarfieldLayer: View {
    let scene: ShiftSceneConfig

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard scene.starsEnabled, scene.starCount > 0 else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<scene.starCount {
                    let seed = UInt64(truncatingIfNeeded: index &+ 31) &* 0x94D049BB133111EB &+ 0x2545F4914F6CDD1D
                    var generator = SeededGenerator(seed: seed)
                    let x = CGFloat(Double.random(in: 0...1, using: &generator)) * size.width
                    let y = CGFloat(Double.random(in: 0...0.6, using: &generator)) * size.height
                    let baseSize = CGFloat(Double.random(in: 1.8...3.2, using: &generator))
                    let speed = Double.random(in: 0.25...0.55, using: &generator)
                    let phase = Double.random(in: 0...Double.pi * 2, using: &generator)
                    let shaping = Double.random(in: 2.4...4.0, using: &generator)
                    let twinkle = sin(time * scene.starTwinkle * speed + phase)
                    let normalized = (twinkle + 1) / 2
                    let eased = pow(normalized, shaping)
                    context.opacity = eased
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: baseSize * CGFloat(0.55 + 0.85 * eased), height: baseSize * CGFloat(0.55 + 0.85 * eased))),
                        with: .color(scene.starColor)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ShootingStarLayer: View {
    let scene: ShiftSceneConfig

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard scene.shootingStarsEnabled, scene.shootingStarCount > 0 else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                let baseFrequency = max(scene.shootingStarFrequency, 0.01)

                for index in 0..<scene.shootingStarCount {
                    let seed = UInt64(truncatingIfNeeded: index &+ 57) &* 0x2545F4914F6CDD1D &+ 0x9E3779B97F4A7C15
                    var generator = SeededGenerator(seed: seed)
                    let phaseOffset = Double.random(in: 0.0...1.0, using: &generator)
                    let startYOffset = Double.random(in: 0.08...0.28, using: &generator)
                    let laneTilt = Double.random(in: 0.22...0.42, using: &generator)
                    let travel = Double.random(in: 1.35...1.55, using: &generator) * Double(size.width)
                    let startXOffset = Double.random(in: (-0.35)...(-0.18), using: &generator)
                    let headGlow = Double.random(in: 9.0...14.0, using: &generator)
                    let blurRadius = Double.random(in: 1.6...2.3, using: &generator)
                    let tailScale = Double.random(in: 0.85...1.25, using: &generator)

                    let cycle = (time * baseFrequency + phaseOffset).truncatingRemainder(dividingBy: 1)
                    guard cycle < 0.35 else { continue }

                    let phase = cycle / 0.35
                    let easedPhase = pow(phase, max(scene.shootingStarSpeed, 0.5))

                    let startPoint = CGPoint(
                        x: size.width * CGFloat(startXOffset),
                        y: size.height * CGFloat(startYOffset)
                    )

                    let direction = CGVector(dx: 1, dy: laneTilt)
                    let norm = sqrt(direction.dx * direction.dx + direction.dy * direction.dy)
                    let unit = CGVector(dx: direction.dx / norm, dy: direction.dy / norm)

                    let headDistance = CGFloat(travel) * CGFloat(easedPhase)
                    let head = CGPoint(
                        x: startPoint.x + unit.dx * headDistance,
                        y: startPoint.y + unit.dy * headDistance
                    )
                    let tailLength = size.width * CGFloat(scene.shootingStarLength) * CGFloat(tailScale)
                    let tail = CGPoint(
                        x: head.x - unit.dx * tailLength,
                        y: head.y - unit.dy * tailLength
                    )

                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: 6))
                        layer.fill(
                            Path(ellipseIn: CGRect(x: head.x - headGlow, y: head.y - headGlow, width: headGlow * 2, height: headGlow * 2)),
                            with: .radialGradient(
                                Gradient(colors: [
                                    scene.shootingStarColor.opacity(0.95),
                                    scene.shootingStarColor.opacity(0)
                                ]),
                                center: head,
                                startRadius: 0,
                                endRadius: headGlow
                            )
                        )
                    }

                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: blurRadius))
                        layer.stroke(
                            Path { path in
                                path.move(to: tail)
                                path.addLine(to: head)
                            },
                            with: .linearGradient(
                                Gradient(stops: [
                                    .init(color: scene.shootingStarColor.opacity(0), location: 0),
                                    .init(color: scene.shootingStarColor.opacity(0.4), location: 0.45),
                                    .init(color: scene.shootingStarColor.opacity(0.95), location: 1)
                                ]),
                                startPoint: tail,
                                endPoint: head
                            ),
                            style: StrokeStyle(lineWidth: 2.1, lineCap: .round)
                        )
                    }

                    context.fill(
                        Path(ellipseIn: CGRect(x: head.x - 3.5, y: head.y - 3.5, width: 7, height: 7)),
                        with: .color(scene.shootingStarColor)
                    )
                }
            }
        }
        .allowsHitTesting(false)
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
    let cloudsEnabled: Bool
    let cloudColor: Color
    let cloudCount: Int
    let cloudSpeed: Double
    let cloudOpacity: Double
    let sunEnabled: Bool
    let sunColor: Color
    let sunGlowColor: Color
    let sunSpeed: Double
    let sunArcHeight: Double
    let starsEnabled: Bool
    let starColor: Color
    let starCount: Int
    let starTwinkle: Double
    let shootingStarsEnabled: Bool
    let shootingStarColor: Color
    let shootingStarFrequency: Double
    let shootingStarSpeed: Double
    let shootingStarLength: Double
    let shootingStarCount: Int
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
                lightBlur: 26,
                cloudsEnabled: true,
                cloudColor: Color(hex: 0xE4F2FF),
                cloudCount: 5,
                cloudSpeed: 0.02,
                cloudOpacity: 0.75,
                sunEnabled: false,
                sunColor: Color(hex: 0xFFE28D),
                sunGlowColor: Color(hex: 0xFFF3C1),
                sunSpeed: 0.0,
                sunArcHeight: 0.0,
                starsEnabled: false,
                starColor: Color.white,
                starCount: 0,
                starTwinkle: 0.0,
                shootingStarsEnabled: false,
                shootingStarColor: Color.white,
                shootingStarFrequency: 0.0,
                shootingStarSpeed: 0.0,
                shootingStarLength: 0.0,
                shootingStarCount: 0
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
                lightBlur: 24,
                cloudsEnabled: false,
                cloudColor: Color.white.opacity(0.75),
                cloudCount: 0,
                cloudSpeed: 0,
                cloudOpacity: 0,
                sunEnabled: true,
                sunColor: Color(hex: 0xFFCE73),
                sunGlowColor: Color(hex: 0xFFD9A0),
                sunSpeed: 0.08,
                sunArcHeight: 0.38,
                starsEnabled: false,
                starColor: Color.white,
                starCount: 0,
                starTwinkle: 0,
                shootingStarsEnabled: false,
                shootingStarColor: Color.white,
                shootingStarFrequency: 0,
                shootingStarSpeed: 0,
                shootingStarLength: 0,
                shootingStarCount: 0
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
                lightBlur: 34,
                cloudsEnabled: false,
                cloudColor: Color.white.opacity(0.6),
                cloudCount: 0,
                cloudSpeed: 0,
                cloudOpacity: 0,
                sunEnabled: false,
                sunColor: Color.white,
                sunGlowColor: Color.white,
                sunSpeed: 0,
                sunArcHeight: 0,
                starsEnabled: true,
                starColor: Color.white.opacity(0.9),
                starCount: 110,
                starTwinkle: 0.8,
                shootingStarsEnabled: true,
                shootingStarColor: Color.white.opacity(0.9),
                shootingStarFrequency: 0.12,
                shootingStarSpeed: 1.35,
                shootingStarLength: 0.22,
                shootingStarCount: 2
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
                lightBlur: 20,
                cloudsEnabled: false,
                cloudColor: Color.white.opacity(0.6),
                cloudCount: 0,
                cloudSpeed: 0,
                cloudOpacity: 0,
                sunEnabled: false,
                sunColor: Color.white,
                sunGlowColor: Color.white,
                sunSpeed: 0,
                sunArcHeight: 0,
                starsEnabled: false,
                starColor: Color.white,
                starCount: 0,
                starTwinkle: 0,
                shootingStarsEnabled: false,
                shootingStarColor: Color.white,
                shootingStarFrequency: 0,
                shootingStarSpeed: 0,
                shootingStarLength: 0,
                shootingStarCount: 0
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
    let calendar: Calendar
    @EnvironmentObject private var store: RosterDataStore
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
            .onChange(of: shift) { _, newValue in
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
            } else if store.colleagues.isEmpty {
                Text("暂无同事名单，请前往“我的”页面添加。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.colleagues, id: \.self) { colleague in
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

enum ShiftType: String, CaseIterable, Identifiable {
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

struct ShiftBadgeStyle {
    let text: String
    let textColor: Color
    let backgroundColor: Color
}

extension Calendar {
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
    let viewModel = AppViewModel(dataStore: RosterDataStore())
    viewModel.dataStore.addColleague("示例同事")
    viewModel.dataStore.setShift(.morning, for: Date())
    return ContentView()
        .environmentObject(viewModel)
        .environmentObject(viewModel.dataStore)
}
