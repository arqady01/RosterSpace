//
//  AIChatModels.swift
//  RosterSpace
//
//  Created by Codex on 10/24/25.
//

import Foundation

enum AIMessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum AIMessageState: Equatable {
    case normal
    case streaming
    case failed(reason: String?)
    case stopped

    var isStreaming: Bool {
        if case .streaming = self {
            return true
        }
        return false
    }

    var errorDescription: String? {
        if case .failed(let reason) = self {
            return reason
        }
        return nil
    }
}

struct AIMessageAttachment: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case image
    }

    var id: UUID
    var kind: Kind
    var url: URL
    var contentType: String

    init(id: UUID = UUID(), kind: Kind = .image, url: URL, contentType: String) {
        self.id = id
        self.kind = kind
        self.url = url
        self.contentType = contentType
    }
}

struct AIMessageItem: Identifiable, Equatable {
    var id: UUID
    var role: AIMessageRole
    var content: String
    var createdAt: Date
    var attachments: [AIMessageAttachment]
    var state: AIMessageState

    init(
        id: UUID = UUID(),
        role: AIMessageRole,
        content: String,
        createdAt: Date = Date(),
        attachments: [AIMessageAttachment] = [],
        state: AIMessageState = .normal
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.attachments = attachments
        self.state = state
    }
}

struct AIModelOption: Identifiable, Hashable {
    var id: UUID
    var displayName: String
    var modelIdentifier: String
    var baseURL: URL
    var isActive: Bool
    var ordering: Int

    init(
        id: UUID,
        displayName: String,
        modelIdentifier: String,
        baseURL: URL,
        isActive: Bool = true,
        ordering: Int = 100
    ) {
        self.id = id
        self.displayName = displayName
        self.modelIdentifier = modelIdentifier
        self.baseURL = baseURL
        self.isActive = isActive
        self.ordering = ordering
    }
}

struct AIUsageMetrics: Equatable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
}

