//
//  AIChatScreen.swift
//  RosterSpace
//
//  Created by Codex on 10/24/25.
//

import PhotosUI
import SwiftData
import SwiftUI

struct AIChatScreen: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = AIChatViewModel()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isShowingAccountSheet = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        let toolbarApplied = navigationContent.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Group {
                    if case .signedIn = appViewModel.authStatus, !viewModel.messages.isEmpty {
                        Button(role: .destructive) {
                            viewModel.clearHistory()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("清空当前会话历史")
                    }
                }
            }
        }

        let appearApplied = toolbarApplied.onAppear {
            viewModel.attachModelContext(modelContext)
            Task {
                if case .signedIn = appViewModel.authStatus {
                    await viewModel.initializeIfNeeded()
                }
            }
        }

        let authChangeApplied = appearApplied.onChange(of: appViewModel.authStatus, initial: false) { _, status in
            switch status {
            case .signedIn:
                Task { await viewModel.loadModels(force: true) }
            case .signedOut:
                viewModel.resetForSignOut()
            case .loading:
                break
            }
        }

        let sheetApplied = authChangeApplied.sheet(isPresented: $isShowingAccountSheet) {
            NavigationStack {
                AccountManagementView()
                    .environmentObject(appViewModel)
            }
        }

        let errorBinding = Binding(
            get: { viewModel.serviceError != nil },
            set: { newValue in
                if !newValue {
                    viewModel.serviceError = nil
                }
            }
        )

        let alertApplied = sheetApplied.alert(
            "出错了",
            isPresented: errorBinding,
            presenting: viewModel.serviceError
        ) { _ in
            Button("好的", role: .cancel) {
                viewModel.serviceError = nil
            }
        } message: { error in
            Text(error)
        }

        let selectionApplied = alertApplied.onChange(of: selectedItems, perform: handleSelectionChange)

        return selectionApplied
    }

    private var navigationContent: some View {
        NavigationStack {
            rootContent
                .navigationTitle("AI 助手")
        }
    }

    private var rootContent: AnyView {
        switch appViewModel.authStatus {
        case .loading:
            return AnyView(
                ProgressView("正在检查登录状态…")
                    .progressViewStyle(.circular)
                    .font(.body)
            )
        case .signedOut:
            return AnyView(
                SignInRequiredView {
                    isShowingAccountSheet = true
                }
            )
        case .signedIn:
            return AnyView(chatLayout)
        }
    }

    private var chatLayout: some View {
        VStack(spacing: 0) {
            modelPicker
            Divider()
            messageList
            Divider()
            inputPanel
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color(.systemBackground))
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var modelPicker: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(viewModel.models) { model in
                    Button {
                        viewModel.selectedModel = model
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if model.id == viewModel.selectedModel?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.selectedModel?.displayName ?? "选择模型")
                        .font(.headline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))
                )
            }

            Spacer()

            if viewModel.isStreaming {
                Label("正在生成", systemImage: "waveform.path")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let usage = viewModel.usageMetrics, let total = usage.totalTokens {
                Label("Tokens: \(total)", systemImage: "number")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        ChatMessageRow(
                            message: message,
                            onRetry: viewModel.retryLastRequest,
                            onRegenerate: viewModel.regenerateResponse
                        )
                        .id(message.id)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.activeScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
        }
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.draftAttachments.isEmpty {
                DraftAttachmentStrip(
                    attachments: viewModel.draftAttachments,
                    isUploading: viewModel.isUploadingAttachment,
                    onRemove: { attachment in
                        viewModel.removeDraftAttachment(attachment)
                    }
                )
            }

            HStack(alignment: .bottom, spacing: 12) {
                PhotosPicker(selection: $selectedItems, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: "paperclip")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 32, height: 32)
                }
                .disabled(viewModel.isUploadingAttachment || viewModel.isStreaming)

                VStack {
                    ZStack(alignment: .topLeading) {
                        if viewModel.inputText.isEmpty {
                            Text("说点什么…")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 8)
                        }

                        TextEditor(text: $viewModel.inputText)
                            .frame(minHeight: 44, maxHeight: 140)
                            .focused($isInputFocused)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }
                }

                if viewModel.isStreaming {
                    Button {
                        viewModel.stopGeneration()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.red)
                    }
                    .accessibilityLabel("停止生成")
                } else {
                    Button {
                        viewModel.sendMessage()
                        isInputFocused = false
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(viewModel.inputText.isEmpty && viewModel.draftAttachments.isEmpty ? .gray : .accentColor)
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.draftAttachments.isEmpty)
                    .accessibilityLabel("发送消息")
                }
            }

            HStack(spacing: 16) {
                if viewModel.canRetry() {
                    Button("重试") {
                        viewModel.retryLastRequest()
                    }
                }

                if viewModel.canRegenerate() {
                    Button("重新生成") {
                        viewModel.regenerateResponse()
                    }
                }

                Spacer()
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.accentColor)
        }
    }
}

// MARK: - Subviews

private struct ChatMessageRow: View {
    let message: AIMessageItem
    let onRetry: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                if message.role == .assistant {
                    profileBadge(systemImage: "sparkles")
                } else {
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.body)
                            .foregroundColor(message.role == .user ? .white : .primary)
                            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                    }

                    if !message.attachments.isEmpty {
                        AttachmentGrid(attachments: message.attachments)
                    }

                    if case .failed(let reason) = message.state {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(reason ?? "生成失败")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    } else if message.state.isStreaming {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .center)
                    } else if case .stopped = message.state {
                        Text("生成已停止")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(message.role == .user ? Color.accentColor : Color(.secondarySystemBackground))
                )

                if message.role == .user {
                    profileBadge(systemImage: "person.crop.circle")
                } else {
                    Spacer(minLength: 0)
                }
            }

            if case .failed = message.state, message.role == .assistant {
                HStack(spacing: 12) {
                    Button("重试", action: onRetry)
                    Button("重新生成", action: onRegenerate)
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.accentColor)
            }
        }
    }

    @ViewBuilder
    private func profileBadge(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(message.role == .user ? .accentColor : .purple)
            .padding(6)
            .background(
                Circle()
                    .fill(
                        message.role == .user
                            ? Color(.systemBackground)
                            : Color(.secondarySystemBackground)
                    )
            )
    }
}

private struct AttachmentGrid: View {
    let attachments: [AIMessageAttachment]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            ForEach(attachments) { attachment in
                AsyncImage(url: attachment.url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.tertiarySystemFill))
                            ProgressView()
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .clipped()
                    case .failure:
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.tertiarySystemFill))
                            Image(systemName: "xmark.octagon")
                                .foregroundColor(.red)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct DraftAttachmentStrip: View {
    let attachments: [AIMessageAttachment]
    let isUploading: Bool
    let onRemove: (AIMessageAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: attachment.url) { phase in
                            switch phase {
                            case .empty:
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.tertiarySystemFill))
                                    .overlay {
                                        if isUploading {
                                            ProgressView()
                                        }
                                    }
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.tertiarySystemFill))
                                    .overlay {
                                        Image(systemName: "xmark.octagon")
                                            .foregroundColor(.red)
                                    }
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button {
                            onRemove(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.footnote)
                                .foregroundColor(.white)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.4))
                                )
                        }
                        .padding(6)
                    }
                }

                if isUploading {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct SignInRequiredView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
            Text("登录后即可使用 AI 助手")
                .font(.title3.weight(.semibold))
            Text("请先登录或注册账号，我们将为你保留个性化配置与会话记录。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Text("立即登录 / 注册")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.accentColor)
                    )
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

@MainActor
private extension AIChatScreen {
    func handleSelectionChange(_ newItems: [PhotosPickerItem]) {
        guard !newItems.isEmpty else { return }
        Task {
            for item in newItems {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                    let fileName = "image-\(UUID().uuidString).jpg"
                    await viewModel.addImageAttachment(
                        data: data,
                        contentType: mimeType,
                        suggestedFileName: fileName
                    )
                }
            }
            await MainActor.run {
                selectedItems.removeAll()
            }
        }
    }
}
