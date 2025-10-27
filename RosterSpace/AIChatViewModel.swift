//
//  AIChatViewModel.swift
//  RosterSpace
//
//  Created by Codex on 10/24/25.
//

import Foundation
import SwiftData
import Supabase
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AIChatViewModel: ObservableObject {
    @Published private(set) var models: [AIModelOption] = []
    @Published var selectedModel: AIModelOption? {
        didSet {
            Task { await loadMessagesForSelectedModel() }
        }
    }

    @Published var messages: [AIMessageItem] = []
    @Published var inputText: String = ""
    @Published var isLoadingModels = false
    @Published var isStreaming = false
    @Published var isUploadingAttachment = false
    @Published var attachmentError: String?
    @Published var serviceError: String?
    @Published var usageMetrics: AIUsageMetrics?
    @Published var draftAttachments: [AIMessageAttachment] = []
    @Published var activeScrollTarget: UUID?

    private let service: AIChatService
    private weak var modelContext: ModelContext?
    private var streamTask: Task<Void, Never>?
    private var pendingAssistantId: UUID?
    private var cachedHistory: [String: [AIMessageItem]] = [:]
    private var lastUsedModelIdentifier: String?
    private var throttledHapticDate = Date.distantPast
    private let maxContextPairs = 6

    init(service: AIChatService = AIChatService()) {
        self.service = service
    }

    func attachModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func resetForSignOut() {
        cancelStreaming()
        messages = []
        usageMetrics = nil
        draftAttachments = []
        cachedHistory.removeAll()
        serviceError = nil
    }

    func initializeIfNeeded() async {
        guard !isLoadingModels else { return }
        await loadModels()
    }

    func loadModels(force: Bool = false) async {
        guard force || models.isEmpty else {
            await loadMessagesForSelectedModel()
            return
        }

        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            let options = try await service.fetchModelOptions()
            models = options
            if let lastUsed = lastUsedModelIdentifier,
               let restored = options.first(where: { $0.modelIdentifier == lastUsed }) {
                selectedModel = restored
            } else {
                selectedModel = options.first
            }
        } catch {
            serviceError = localized(error)
        }
    }

    func addImageAttachment(data: Data, contentType: String, suggestedFileName: String) async {
        guard !isUploadingAttachment else { return }
        isUploadingAttachment = true
        attachmentError = nil
        do {
            let fileName = suggestedFileName.isEmpty ? "image-\(UUID().uuidString).jpg" : suggestedFileName
            let url = try await service.uploadImage(data: data, fileName: fileName, contentType: contentType)
            let attachment = AIMessageAttachment(url: url, contentType: contentType)
            draftAttachments.append(attachment)
            activeScrollTarget = attachment.id
        } catch {
            attachmentError = localized(error)
        }
        isUploadingAttachment = false
    }

    func removeDraftAttachment(_ attachment: AIMessageAttachment) {
        draftAttachments.removeAll { $0.id == attachment.id }
    }

    func sendMessage() {
        guard let model = selectedModel else {
            serviceError = "暂无可用模型"
            return
        }
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty || !draftAttachments.isEmpty else { return }

        let userMessage = AIMessageItem(
            id: UUID(),
            role: .user,
            content: trimmedInput,
            createdAt: Date(),
            attachments: draftAttachments,
            state: .normal
        )

        inputText = ""
        draftAttachments = []
        messages.append(userMessage)
        activeScrollTarget = userMessage.id
        persist(message: userMessage, for: model)

        startStreamingResponse(for: userMessage, model: model)
    }

    func stopGeneration() {
        guard isStreaming else { return }
        streamTask?.cancel()
        isStreaming = false
        if let pendingId = pendingAssistantId,
           let index = messages.firstIndex(where: { $0.id == pendingId }) {
            messages[index].state = .stopped
            persistAssistant(messages[index])
        }
        pendingAssistantId = nil
    }

    func retryLastRequest() {
        guard let model = selectedModel else { return }
        guard let userMessage = messages.last(where: { $0.role == .user }) else { return }
        removeTrailingAssistant()
        startStreamingResponse(for: userMessage, model: model)
    }

    func regenerateResponse() {
        guard let model = selectedModel else { return }
        guard let lastUser = messages.last(where: { $0.role == .user }) else { return }
        removeTrailingAssistant()
        startStreamingResponse(for: lastUser, model: model)
    }

    func clearHistory() {
        guard let model = selectedModel else { return }
        cancelStreaming()
        messages.removeAll()
        usageMetrics = nil
        deleteRecords(for: model.modelIdentifier)
    }

    func canRetry() -> Bool {
        guard let last = messages.last, last.role == .assistant else { return false }
        if case .failed = last.state {
            return true
        }
        return false
    }

    func canRegenerate() -> Bool {
        guard let last = messages.last else { return false }
        return last.role == .assistant && last.state == .normal
    }

    // MARK: - Private helpers

    private func startStreamingResponse(for userMessage: AIMessageItem, model: AIModelOption) {
        cancelStreaming()
        usageMetrics = nil

        let trimmedHistory = historyIncluding(userMessage, for: model)
        let payload = buildPayload(
            from: trimmedHistory,
            modelIdentifier: model.modelIdentifier,
            latestUserMessage: userMessage
        )

        let assistantMessage = AIMessageItem(
            id: UUID(),
            role: .assistant,
            content: "",
            createdAt: Date(),
            attachments: [],
            state: .streaming
        )
        messages.append(assistantMessage)
        pendingAssistantId = assistantMessage.id
        activeScrollTarget = assistantMessage.id

        isStreaming = true

        let accessToken = supabaseClient.auth.currentSession?.accessToken

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await service.streamChat(request: payload, accessToken: accessToken)
                var accumulated = ""
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    accumulated.append(chunk.textDelta)
                    await MainActor.run {
                        self.applyDelta(chunk.textDelta)
                        if let usage = chunk.usage {
                            self.usageMetrics = usage
                        }
                    }
                }
                await MainActor.run {
                    self.finalizeStreaming(text: accumulated, usage: self.usageMetrics, model: model)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.handleStreamError(error)
                }
            }
        }
    }

    private func applyDelta(_ delta: String) {
        guard let pendingId = pendingAssistantId,
              let index = messages.firstIndex(where: { $0.id == pendingId })
        else { return }

        messages[index].content.append(delta)
        activeScrollTarget = pendingId
        triggerHaptic()
    }

    private func finalizeStreaming(text: String, usage: AIUsageMetrics?, model: AIModelOption) {
        isStreaming = false
        guard let pendingId = pendingAssistantId,
              let index = messages.firstIndex(where: { $0.id == pendingId })
        else { return }

        messages[index].state = text.isEmpty ? .failed(reason: "输出为空，请重试。") : .normal
        if !text.isEmpty {
            messages[index].content = text
            messages[index].createdAt = Date()
            persistAssistant(messages[index], model: model)
        }
        usageMetrics = usage
        pendingAssistantId = nil
        streamTask = nil
    }

    private func handleStreamError(_ error: Error) {
        isStreaming = false
        let message = localized(error)
        serviceError = message
        if let pendingId = pendingAssistantId,
           let index = messages.firstIndex(where: { $0.id == pendingId }) {
            messages[index].state = .failed(reason: message)
        }
        pendingAssistantId = nil
        streamTask = nil
    }

    private func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        pendingAssistantId = nil
    }

    private func loadMessagesForSelectedModel() async {
        guard let model = selectedModel else {
            messages = []
            return
        }
        lastUsedModelIdentifier = model.modelIdentifier
        if let cached = cachedHistory[model.modelIdentifier] {
            messages = cached
            return
        }
        guard let context = modelContext else { return }
        do {
            let modelIdentifier = model.modelIdentifier
            let descriptor = FetchDescriptor<AIChatRecord>(
                predicate: #Predicate { $0.modelIdentifier == modelIdentifier },
                sortBy: [SortDescriptor(\AIChatRecord.createdAt, order: .forward)]
            )
            let records = try context.fetch(descriptor)
            let items = records.map { $0.toMessageItem() }
            messages = items
            cachedHistory[model.modelIdentifier] = items
        } catch {
            serviceError = localized(error)
        }
    }

    private func historyIncluding(_ message: AIMessageItem, for model: AIModelOption) -> [AIMessageItem] {
        var combined = messages.filter { $0.state == .normal }
        if combined.contains(where: { $0.id == message.id }) == false {
            combined.append(message)
        }
        var trimmed: [AIMessageItem] = []
        var userCount = 0
        for item in combined.reversed() {
            trimmed.insert(item, at: 0)
            if item.role == .user {
                userCount += 1
            }
            if userCount >= maxContextPairs {
                break
            }
        }
        return trimmed
    }

    private func buildPayload(
        from messages: [AIMessageItem],
        modelIdentifier: String,
        latestUserMessage: AIMessageItem
    ) -> AIChatService.AIChatRequestPayload {
        let requestMessages: [AIChatService.AIChatRequestPayload.Message] = messages.map { message in
            var contents: [AIChatService.AIChatRequestPayload.MessageContent] = []
            if !message.content.isEmpty {
                contents.append(
                    AIChatService.AIChatRequestPayload.MessageContent(
                        type: "text",
                        text: message.content,
                        imageURL: nil
                    )
                )
            }
            message.attachments.forEach { attachment in
                contents.append(
                    AIChatService.AIChatRequestPayload.MessageContent(
                        type: "image_url",
                        text: nil,
                        imageURL: .init(url: attachment.url.absoluteString)
                    )
                )
            }
            return AIChatService.AIChatRequestPayload.Message(
                role: message.role,
                content: contents
            )
        }

        let attachmentPayloads = latestUserMessage.attachments.map {
            AIChatService.AIChatRequestPayload.Attachment(
                type: $0.kind.rawValue,
                url: $0.url.absoluteString,
                contentType: $0.contentType
            )
        }

        return AIChatService.AIChatRequestPayload(
            modelIdentifier: modelIdentifier,
            messages: requestMessages,
            clientMessageId: latestUserMessage.id,
            attachments: attachmentPayloads
        )
    }

    private func persist(message: AIMessageItem, for model: AIModelOption) {
        guard let context = modelContext else { return }
        let record = AIChatRecord(
            id: message.id,
            modelIdentifier: model.modelIdentifier,
            role: message.role,
            content: message.content,
            createdAt: message.createdAt,
            attachments: message.attachments
        )
        context.insert(record)
        do {
            try context.save()
        } catch {
            serviceError = localized(error)
        }
        cachedHistory[model.modelIdentifier] = messages
    }

    private func persistAssistant(_ message: AIMessageItem, model: AIModelOption? = nil) {
        guard let context = modelContext else { return }
        let identifier = model?.modelIdentifier ?? selectedModel?.modelIdentifier
        guard let modelIdentifier = identifier else { return }
        do {
            let messageID = message.id
            let descriptor = FetchDescriptor<AIChatRecord>(
                predicate: #Predicate { $0.id == messageID }
            )
            if var record = try context.fetch(descriptor).first {
                record.content = message.content
                record.createdAt = message.createdAt
                record.attachments = message.attachments
                record.role = message.role
            } else {
                let newRecord = AIChatRecord(
                    id: message.id,
                    modelIdentifier: modelIdentifier,
                    role: message.role,
                    content: message.content,
                    createdAt: message.createdAt,
                    attachments: message.attachments
                )
                context.insert(newRecord)
            }
            try context.save()
            cachedHistory[modelIdentifier] = messages
        } catch {
            serviceError = localized(error)
        }
    }

    private func deleteRecords(for modelIdentifier: String) {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<AIChatRecord>(
                predicate: #Predicate { $0.modelIdentifier == modelIdentifier }
            )
            let records = try context.fetch(descriptor)
            records.forEach { context.delete($0) }
            try context.save()
            cachedHistory[modelIdentifier] = []
        } catch {
            serviceError = localized(error)
        }
    }

    private func removeTrailingAssistant() {
        if let last = messages.last, last.role == .assistant {
            messages.removeLast()
            deleteRecord(with: last.id)
            if let identifier = selectedModel?.modelIdentifier {
                cachedHistory[identifier] = messages
            }
        }
    }

    private func deleteRecord(with id: UUID) {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<AIChatRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let record = try context.fetch(descriptor).first {
                context.delete(record)
                try context.save()
            }
        } catch {
            serviceError = localized(error)
        }
    }

    private func localized(_ error: Error) -> String {
        if let error = error as? AIChatService.AIChatServiceError {
            switch error {
            case .invalidResponse:
                return "服务响应格式异常"
            case .invalidPublicURL:
                return "上传图片失败，无法获取访问链接"
            case .httpError(let status, _):
                return "调用失败（\(status)）"
            }
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return "网络连接异常，请检查网络后重试"
        }
        return error.localizedDescription
    }

    private func triggerHaptic() {
#if canImport(UIKit)
        let now = Date()
        guard now.timeIntervalSince(throttledHapticDate) > 0.4 else { return }
        throttledHapticDate = now
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.5)
#endif
    }
}
