//
//  SupabaseConfig.swift
//  RosterSpace
//
//  Created by Codex on 10/23/25.
//

import Foundation
import OSLog
import Supabase

enum SupabaseConfig {
    static let url: URL = {
        guard let url = URL(string: "https://leudpctfhbaknnuynrev.supabase.co") else {
            fatalError("Supabase URL 配置错误")
        }
        return url
    }()

    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxldWRwY3RmaGJha25udXlucmV2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjEzNjMzNDQsImV4cCI6MjA3NjkzOTM0NH0.MqNQmz-xHgnecxoYjXWpO5Wuriit1Xl9V6wfbI_fkEw"
}

let supabaseClient: SupabaseClient = {
    SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey,
        options: .init(
            auth: .init(autoRefreshToken: true),
            global: .init(logger: SupabaseLoggerAdapter.shared)
        )
    )
}()

struct SupabaseLoggerAdapter: SupabaseLogger {
    static let shared = SupabaseLoggerAdapter()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RosterSpace", category: "Supabase")

    func log(message: SupabaseLogMessage) {
        switch message.level {
        case .debug:
            logger.debug("\(message.description, privacy: .public)")
        case .verbose:
            logger.notice("\(message.description, privacy: .public)")
        case .warning:
            logger.warning("\(message.description, privacy: .public)")
        case .error:
            logger.error("\(message.description, privacy: .public)")
        }
    }
}
