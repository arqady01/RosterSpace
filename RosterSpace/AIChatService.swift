//
//  AIChatService.swift
//  RosterSpace
//
//  Created by Codex on 10/24/25.
//

import Foundation
import Supabase

struct AIStreamChunk: Equatable {
    var textDelta: String
    var finishReason: String?
    var usage: AIUsageMetrics?
}

final class AIChatService: ObservableObject {
    private enum Constants {
        static let edgeFunctionName = "ai-chat"
        static let storageBucket = "ai-chat-uploads"
        static let maxContextPairs = 6
    }

    private let client: SupabaseClient
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    init(client: SupabaseClient = supabaseClient) {
        self.client = client
    }

    func fetchModelOptions() async throws -> [AIModelOption] {
        let rows: [ModelConfigRow] = try await client.database
            .from("ai_model_configs")
            .select("id,display_name,model_identifier,base_url,is_active,ordering")
            .eq("is_active", value: true)
            .order("ordering")
            .execute()
            .value

        return rows.compactMap { row in
            guard let url = URL(string: row.baseURL) else { return nil }
            return AIModelOption(
                id: row.id,
                displayName: row.displayName,
                modelIdentifier: row.modelIdentifier,
                baseURL: url,
                isActive: row.isActive ?? true,
                ordering: row.ordering ?? 100
            )
        }
        .sorted { lhs, rhs in
            if lhs.ordering == rhs.ordering {
                return lhs.displayName < rhs.displayName
            }
            return lhs.ordering < rhs.ordering
        }
    }

    func uploadImage(data: Data, fileName: String, contentType: String) async throws -> URL {
        let bucket = client.storage.from(Constants.storageBucket)
        let path = "ios/\(UUID().uuidString)/\(fileName)"
        let options = FileOptions(
            cacheControl: "3600",
            contentType: contentType,
            upsert: false
        )

        _ = try await bucket.upload(path, data: data, options: options)
        let publicURL = try bucket.getPublicURL(path: path)
        return publicURL
    }

    func streamChat(
        request: AIChatRequestPayload,
        accessToken: String?
    ) async throws -> AsyncThrowingStream<AIStreamChunk, Error> {
        let url = SupabaseConfig.url.appendingPathComponent("functions/v1/\(Constants.edgeFunctionName)")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let accessToken {
            urlRequest.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try jsonEncoder.encode(request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIChatServiceError.invalidResponse
                    }
                    guard 200..<300 ~= httpResponse.statusCode else {
                        var fallback = Data()
                        for try await byte in bytes {
                            fallback.append(byte)
                        }
                        throw AIChatServiceError.httpError(statusCode: httpResponse.statusCode, payload: fallback)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            break
                        }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" {
                            break
                        }
                        guard !payload.isEmpty else { continue }
                        guard let data = payload.data(using: .utf8) else { continue }
                        let chunk = try jsonDecoder.decode(OpenAIStreamEnvelope.self, from: data)
                        let textDelta = chunk.choices
                            .compactMap { $0.delta?.content }
                            .joined()
                        let usage = chunk.usage.map {
                            AIUsageMetrics(
                                promptTokens: $0.promptTokens,
                                completionTokens: $0.completionTokens,
                                totalTokens: $0.totalTokens
                            )
                        }
                        let streamChunk = AIStreamChunk(
                            textDelta: textDelta,
                            finishReason: chunk.choices.first?.finishReason,
                            usage: usage
                        )
                        continuation.yield(streamChunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

extension AIChatService {
    enum AIChatServiceError: Error {
        case invalidResponse
        case invalidPublicURL
        case httpError(statusCode: Int, payload: Data)
    }
}

extension AIChatService {
    struct AIChatRequestPayload: Encodable {
        var modelIdentifier: String
        var messages: [Message]
        var clientMessageId: UUID
        var attachments: [Attachment]

        struct Message: Encodable {
            var role: AIMessageRole
            var content: [MessageContent]
        }

        struct MessageContent: Encodable {
            var type: String
            var text: String?
            var imageURL: ImageURL?

            enum CodingKeys: String, CodingKey {
                case type
                case text
                case imageURL = "image_url"
            }
        }

        struct ImageURL: Encodable {
            var url: String
        }

        struct Attachment: Encodable {
            var type: String
            var url: String
            var contentType: String
        }
    }

    private struct OpenAIStreamEnvelope: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                var role: String?
                var content: String?
            }

            var delta: Delta?
            var finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        struct Usage: Decodable {
            var promptTokens: Int?
            var completionTokens: Int?
            var totalTokens: Int?
        }

        var choices: [Choice]
        var usage: Usage?
    }

    private struct ModelConfigRow: Decodable {
        var id: UUID
        var displayName: String
        var modelIdentifier: String
        var baseURL: String
        var isActive: Bool?
        var ordering: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case modelIdentifier = "model_identifier"
            case baseURL = "base_url"
            case isActive = "is_active"
            case ordering
        }
    }
}
