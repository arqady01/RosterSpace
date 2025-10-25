//
//  RosterSyncService.swift
//  RosterSpace
//
//  Created by Codex on 10/23/25.
//

import Foundation
import Supabase

struct RosterSyncSnapshot {
    let colleagues: [String]
    let shiftAssignments: [Date: ShiftType]
    let coworkerAssignments: [Date: Set<String>]
}

enum RosterSyncRequest {
    case replaceColleagues([String])
    case upsertShift(Date, ShiftType)
    case updateCoworkers(Date, Set<String>)
}

actor SupabaseRosterSyncEngine {
    private let client: SupabaseClient
    private let userId: UUID
    private let calendar: Calendar
    private let dateFormatter: DateFormatter
    private let userIdString: String

    init(client: SupabaseClient, userId: UUID, calendar: Calendar) {
        self.client = client
        self.userId = userId
        self.calendar = calendar
        self.userIdString = userId.uuidString
        self.dateFormatter = Self.makeDateFormatter(for: calendar)
    }

    func fetchSnapshot() async throws -> RosterSyncSnapshot {
        async let colleaguesTask: [SupabaseColleagueRow] = fetchColleagues()
        async let shiftsTask: [SupabaseShiftRow] = fetchShifts()
        async let coworkersTask: [SupabaseCoworkerRow] = fetchCoworkers()

        let (colleagueRows, shiftRows, coworkerRows) = try await (colleaguesTask, shiftsTask, coworkersTask)

        let colleagues = colleagueRows.map(\.name)

        var shiftAssignments: [Date: ShiftType] = [:]
        for row in shiftRows {
            guard
                let date = decodeDate(row.shiftDate),
                let shift = ShiftType(rawValue: row.shiftType)
            else { continue }
            let normalized = calendar.startOfDay(for: date)
            shiftAssignments[normalized] = shift
        }

        var coworkerAssignments: [Date: Set<String>] = [:]
        for row in coworkerRows {
            guard let date = decodeDate(row.shiftDate) else { continue }
            let normalized = calendar.startOfDay(for: date)
            var stored = coworkerAssignments[normalized] ?? Set<String>()
            stored.insert(row.coworkerName)
            coworkerAssignments[normalized] = stored
        }

        return RosterSyncSnapshot(
            colleagues: colleagues,
            shiftAssignments: shiftAssignments,
            coworkerAssignments: coworkerAssignments
        )
    }

    func replaceColleagues(_ names: [String]) async throws {
        _ = try await client.database
            .from("colleagues")
            .delete()
            .eq("user_id", value: userIdString)
            .execute()

        guard !names.isEmpty else { return }

        let payload = names.map {
            SupabaseColleagueInsert(userId: userIdString, name: $0)
        }
        _ = try await client.database
            .from("colleagues")
            .insert(payload)
            .execute()
    }

    func upsertShift(date: Date, shift: ShiftType) async throws {
        let normalized = calendar.startOfDay(for: date)
        let payload = SupabaseShiftUpsertRow(
            userId: userIdString,
            shiftDate: encodeDate(normalized),
            shiftType: shift.rawValue
        )
        _ = try await client.database
            .from("shift_assignments")
            .upsert(payload, onConflict: "user_id,shift_date")
            .execute()
    }

    func replaceCoworkers(date: Date, coworkers: Set<String>) async throws {
        let normalized = calendar.startOfDay(for: date)
        let dateString = encodeDate(normalized)

        _ = try await client.database
            .from("shift_coworkers")
            .delete()
            .eq("user_id", value: userIdString)
            .eq("shift_date", value: dateString)
            .execute()

        guard !coworkers.isEmpty else { return }

        let payload = coworkers.sorted().map {
            SupabaseCoworkerInsert(
                userId: userIdString,
                shiftDate: dateString,
                coworkerName: $0
            )
        }

        _ = try await client.database
            .from("shift_coworkers")
            .insert(payload)
            .execute()
    }
}

// MARK: - Private helpers

private extension SupabaseRosterSyncEngine {
    func fetchColleagues() async throws -> [SupabaseColleagueRow] {
        try await client.database
            .from("colleagues")
            .select("name")
            .eq("user_id", value: userIdString)
            .order("name")
            .execute()
            .value
    }

    func fetchShifts() async throws -> [SupabaseShiftRow] {
        try await client.database
            .from("shift_assignments")
            .select("shift_date,shift_type")
            .eq("user_id", value: userIdString)
            .execute()
            .value
    }

    func fetchCoworkers() async throws -> [SupabaseCoworkerRow] {
        try await client.database
            .from("shift_coworkers")
            .select("shift_date,coworker_name")
            .eq("user_id", value: userIdString)
            .execute()
            .value
    }

    static func makeDateFormatter(for calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    func encodeDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    func decodeDate(_ value: String) -> Date? {
        dateFormatter.date(from: value)
    }
}

// MARK: - DTOs

private struct SupabaseColleagueRow: Decodable {
    let name: String
}

private struct SupabaseShiftRow: Decodable {
    let shiftDate: String
    let shiftType: String

    enum CodingKeys: String, CodingKey {
        case shiftDate = "shift_date"
        case shiftType = "shift_type"
    }
}

private struct SupabaseCoworkerRow: Decodable {
    let shiftDate: String
    let coworkerName: String

    enum CodingKeys: String, CodingKey {
        case shiftDate = "shift_date"
        case coworkerName = "coworker_name"
    }
}

private struct SupabaseColleagueInsert: Encodable {
    let userId: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
    }
}

private struct SupabaseShiftUpsertRow: Encodable {
    let userId: String
    let shiftDate: String
    let shiftType: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case shiftDate = "shift_date"
        case shiftType = "shift_type"
    }
}

private struct SupabaseCoworkerInsert: Encodable {
    let userId: String
    let shiftDate: String
    let coworkerName: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case shiftDate = "shift_date"
        case coworkerName = "coworker_name"
    }
}
