//
//  RosterDataStore.swift
//  RosterSpace
//
//  Created by Codex on 10/22/25.
//

import Foundation

@MainActor
final class RosterDataStore: ObservableObject {
    @Published private(set) var colleagues: [String]
    @Published private(set) var shiftAssignments: [Date: ShiftType]
    @Published private(set) var coworkerAssignments: [Date: Set<String>]

    let calendar: Calendar
    private let currentDate: () -> Date

    init(
        calendar: Calendar = .mondayFirst,
        currentDate: @escaping () -> Date = { Date() }
    ) {
        self.calendar = calendar
        self.currentDate = currentDate
        self.colleagues = []
        self.shiftAssignments = [:]
        self.coworkerAssignments = [:]

        seedInitialData()
    }

    func ensureMonthAvailable(containing date: Date) {
        let monthStart = calendar.startOfMonth(for: date)
        for day in calendar.daysInMonth(for: monthStart) {
            ensureDayAvailable(day)
        }
    }

    func ensureDayAvailable(_ date: Date) {
        let normalized = normalized(date)
        if shiftAssignments[normalized] == nil {
            shiftAssignments[normalized] = ShiftType.defaultAssignment(for: normalized, calendar: calendar)
        }
        if coworkerAssignments[normalized] == nil {
            coworkerAssignments[normalized] = Set<String>()
        }
    }

    func shift(on date: Date) -> ShiftType {
        let normalized = normalized(date)
        return shiftAssignments[normalized] ?? .none
    }

    func coworkers(on date: Date) -> Set<String> {
        let normalized = normalized(date)
        return coworkerAssignments[normalized] ?? Set()
    }

    func setShift(_ shift: ShiftType, for date: Date) {
        let normalized = normalized(date)
        ensureDayAvailable(normalized)

        shiftAssignments[normalized] = shift
        if !shift.allowsCoworkers {
            coworkerAssignments[normalized] = Set()
        }
    }

    func setCoworkers(_ selections: Set<String>, for date: Date) {
        let normalized = normalized(date)
        ensureDayAvailable(normalized)

        let validNames = Set(colleagues)
        coworkerAssignments[normalized] = selections.filter { validNames.contains($0) }
    }

    func addColleague(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalizedName = trimmed.lowercased()
        guard !colleagues.contains(where: { $0.lowercased() == normalizedName }) else { return }
        colleagues.append(trimmed)
    }

    func removeColleagues(at offsets: IndexSet) {
        colleagues.remove(atOffsets: offsets)
        pruneCoworkers()
    }

    func overwriteColleagues(with names: [String]) {
        colleagues = names
        pruneCoworkers()
    }

    func allActiveDates() -> [Date] {
        Array(shiftAssignments.keys)
    }

    func resetAssignments(_ assignments: [Date: ShiftType]) {
        shiftAssignments = assignments.reduce(into: [:]) { partial, pair in
            let normalized = normalized(pair.key)
            partial[normalized] = pair.value
        }
    }

    func resetCoworkerAssignments(_ assignments: [Date: Set<String>]) {
        coworkerAssignments = assignments.reduce(into: [:]) { partial, pair in
            let normalized = normalized(pair.key)
            partial[normalized] = pair.value
        }
    }

    private func normalized(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func seedInitialData() {
        ensureMonthAvailable(containing: currentDate())
    }

    private func pruneCoworkers() {
        let validNames = Set(colleagues)
        for (date, selections) in coworkerAssignments {
            let filtered = selections.filter { validNames.contains($0) }
            coworkerAssignments[date] = Set(filtered)
        }
    }
}
