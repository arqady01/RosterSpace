//
//  AIChatStorage.swift
//  RosterSpace
//
//  Created by Codex on 10/24/25.
//

import Foundation
import SwiftData

@Model
final class AIChatRecord {
    @Attribute(.unique) var id: UUID
    var modelIdentifier: String
    var roleRaw: String
    var content: String
    var createdAt: Date
    var attachmentsBlob: Data?
    var metadataJSON: String?

    init(
        id: UUID = UUID(),
        modelIdentifier: String,
        role: AIMessageRole,
        content: String,
        createdAt: Date = Date(),
        attachments: [AIMessageAttachment] = [],
        metadataJSON: String? = nil
    ) {
        self.id = id
        self.modelIdentifier = modelIdentifier
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.metadataJSON = metadataJSON
        self.attachmentsBlob = try? JSONEncoder().encode(attachments)
    }

    var role: AIMessageRole {
        get { AIMessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    var attachments: [AIMessageAttachment] {
        get {
            guard let attachmentsBlob,
                  let decoded = try? JSONDecoder().decode([AIMessageAttachment].self, from: attachmentsBlob)
            else {
                return []
            }
            return decoded
        }
        set {
            attachmentsBlob = try? JSONEncoder().encode(newValue)
        }
    }
}

extension AIChatRecord {
    func toMessageItem() -> AIMessageItem {
        AIMessageItem(
            id: id,
            role: role,
            content: content,
            createdAt: createdAt,
            attachments: attachments,
            state: .normal
        )
    }
}

