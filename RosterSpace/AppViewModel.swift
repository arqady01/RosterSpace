//
//  AppViewModel.swift
//  RosterSpace
//
//  Created by Codex on 10/23/25.
//

import Foundation
import Supabase

@MainActor
final class AppViewModel: ObservableObject {
    enum AuthStatus: Equatable {
        case loading
        case signedOut
        case signedIn(user: User)
    }

    struct UserProfile: Equatable {
        var username: String?
        var email: String
    }

    struct AppAlert: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    @Published private(set) var authStatus: AuthStatus = .loading
    @Published private(set) var profile: UserProfile?
    @Published var isAuthBusy = false
    @Published var isSyncing = false
    @Published var alert: AppAlert?
    @Published private(set) var lastSuccessfulSyncAt: Date?

    let dataStore: RosterDataStore

    private var authListener: Task<Void, Never>?
    private var syncEngine: SupabaseRosterSyncEngine?
    private var currentUserId: UUID?
    private var pendingProfileUsername: String?
    private var activeSyncTasks = 0
    private var hasLoadedSnapshot = false

    init(dataStore: RosterDataStore) {
        self.dataStore = dataStore

        dataStore.setSyncHandler { [weak self] request in
            guard let self else { return }
            Task { [weak self] in
                await self?.processSyncRequest(request)
            }
        }

        observeAuthChanges()
    }

    deinit {
        authListener?.cancel()
    }

    // MARK: - Public API

    func signIn(email: String, password: String) async throws {
        guard !email.isEmpty, !password.isEmpty else {
            throw makeError("请输入邮箱和密码")
        }

        await setAuthBusy(true)
        defer { Task { await self.setAuthBusy(false) } }

        do {
            _ = try await supabaseClient.auth.signIn(email: email, password: password)
        } catch {
            throw handleAuthError(error)
        }
    }

    func signUp(email: String, password: String, username: String?) async throws {
        guard !email.isEmpty, !password.isEmpty else {
            throw makeError("请输入邮箱和密码")
        }

        await setAuthBusy(true)
        defer { Task { await self.setAuthBusy(false) } }

        do {
            let sanitizedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingProfileUsername = sanitizedUsername?.isEmpty == false ? sanitizedUsername : nil

            let response = try await supabaseClient.auth.signUp(
                email: email,
                password: password,
                data: pendingProfileUsername.flatMap { ["username": AnyJSON.string($0)] }
            )

            if let session = response.session {
                try await upsertProfileRecord(userId: session.user.id, username: pendingProfileUsername)
                pendingProfileUsername = nil
            }
        } catch {
            throw handleAuthError(error)
        }
    }

    func signOut() async throws {
        do {
            try await supabaseClient.auth.signOut()
        } catch {
            throw handleAuthError(error)
        }
    }

    func updateUsername(_ username: String) async throws {
        guard let userId = currentUserId else {
            throw makeError("当前没有登录用户")
        }

        await runSyncTask(allowsSpinner: true) {
            try await self.upsertProfileRecord(userId: userId, username: username.isEmpty ? nil : username)
            if var existing = self.profile {
                existing.username = username.isEmpty ? nil : username
                self.profile = existing
            } else if case .signedIn(let user) = self.authStatus {
                self.profile = UserProfile(
                    username: username.isEmpty ? nil : username,
                    email: user.email ?? ""
                )
            }
        }
    }

    func refreshRosterSnapshot() async {
        await runInitialSync(force: true)
    }

    // MARK: - Auth handling

    private func observeAuthChanges() {
        authListener?.cancel()
        authListener = Task { [weak self] in
            guard let self else { return }
            for await change in supabaseClient.auth.authStateChanges {
                await self.handleAuthEvent(event: change.event, session: change.session)
            }
        }
    }

    private func handleAuthEvent(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed:
            guard let session else {
                await handleSignOut()
                return
            }
            await handleActiveSession(session)
        case .signedOut, .userDeleted:
            await handleSignOut()
        case .userUpdated:
            await refreshProfileIfNeeded()
        default:
            break
        }
    }

    private func handleActiveSession(_ session: Session) async {
        let user = session.user

        let isNewUser: Bool
        if currentUserId != user.id {
            currentUserId = user.id
            isNewUser = true
        } else {
            isNewUser = false
        }

        authStatus = .signedIn(user: user)

        if syncEngine == nil || isNewUser {
            syncEngine = SupabaseRosterSyncEngine(
                client: supabaseClient,
                userId: user.id,
                calendar: dataStore.calendar
            )
            hasLoadedSnapshot = false
        }

        await refreshProfile(for: user)
        await runInitialSync(force: isNewUser || !hasLoadedSnapshot)
    }

    private func handleSignOut() async {
        authStatus = .signedOut
        profile = nil
        currentUserId = nil
        syncEngine = nil
        hasLoadedSnapshot = false
        pendingProfileUsername = nil
        dataStore.resetForSignedOut()
    }

    private func refreshProfileIfNeeded() async {
        guard case .signedIn(let user) = authStatus else { return }
        await refreshProfile(for: user)
    }

    // MARK: - Sync

    private func runInitialSync(force: Bool) async {
        guard force else { return }
        guard let engine = syncEngine else { return }

        await runSyncTask(allowsSpinner: true) {
            let snapshot = try await engine.fetchSnapshot()
            self.dataStore.applyRemoteSnapshot(snapshot)
            self.dataStore.ensureMonthAvailable(containing: Date())
            self.hasLoadedSnapshot = true
            self.lastSuccessfulSyncAt = Date()
        }
    }

    private func processSyncRequest(_ request: RosterSyncRequest) async {
        guard let engine = syncEngine else { return }

        await runSyncTask(allowsSpinner: false) {
            switch request {
            case .replaceColleagues(let names):
                try await engine.replaceColleagues(names)

            case .upsertShift(let date, let shift):
                try await engine.upsertShift(date: date, shift: shift)

            case .updateCoworkers(let date, let coworkers):
                let currentShift = self.dataStore.shift(on: date)
                try await engine.upsertShift(date: date, shift: currentShift)
                try await engine.replaceCoworkers(date: date, coworkers: coworkers)
            }

            self.lastSuccessfulSyncAt = Date()
        }
    }

    private func runSyncTask(
        allowsSpinner: Bool,
        task: @escaping () async throws -> Void
    ) async {
        if allowsSpinner {
            activeSyncTasks += 1
            isSyncing = true
        }

        do {
            try await task()
        } catch {
            alert = AppAlert(message: friendlyErrorMessage(error))
        }

        if allowsSpinner {
            activeSyncTasks = max(0, activeSyncTasks - 1)
            if activeSyncTasks == 0 {
                isSyncing = false
            }
        }
    }

    // MARK: - Profile helpers

    private func refreshProfile(for user: User) async {
        do {
            let rows: [ProfileRow] = try await supabaseClient.database
                .from("profiles")
                .select("id,username")
                .eq("id", value: user.id.uuidString)
                .execute()
                .value

            if let row = rows.first {
                profile = UserProfile(username: row.username, email: user.email ?? "")
                pendingProfileUsername = nil
            } else {
                let desiredUsername = pendingProfileUsername
                    ?? user.userMetadata["username"]?.stringValue

                try await upsertProfileRecord(userId: user.id, username: desiredUsername)
                profile = UserProfile(username: desiredUsername, email: user.email ?? "")
                pendingProfileUsername = nil
            }
        } catch {
            alert = AppAlert(message: friendlyErrorMessage(error))
        }
    }

    private func upsertProfileRecord(userId: UUID, username: String?) async throws {
        let payload = ProfileUpsertRow(
            id: userId.uuidString,
            username: username
        )

        _ = try await supabaseClient.database
            .from("profiles")
            .upsert(payload, onConflict: "id")
            .execute()
    }

    // MARK: - Utilities

    private func setAuthBusy(_ value: Bool) async {
        isAuthBusy = value
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let postgrestError = error as? PostgrestError {
            return postgrestError.message
        }
        if let authError = error as? AuthError {
            return authError.localizedDescription
        }
        if let appError = error as? AppError {
            return appError.message
        }
        return error.localizedDescription
    }

    private func handleAuthError(_ error: Error) -> Error {
        let message = friendlyErrorMessage(error)
        alert = AppAlert(message: message)
        return AppError(message: message)
    }

    private func makeError(_ message: String) -> AppError {
        let error = AppError(message: message)
        alert = AppAlert(message: message)
        return error
    }
}

// MARK: - DTOs & Error

private struct ProfileRow: Decodable {
    let id: String
    let username: String?
}

private struct ProfileUpsertRow: Encodable {
    let id: String
    let username: String?
}

struct AppError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
