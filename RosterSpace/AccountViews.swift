//
//  AccountViews.swift
//  RosterSpace
//
//  Created by Codex on 10/23/25.
//

import Supabase
import SwiftUI

struct AccountEntryRow: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        HStack(spacing: 16) {
            avatar
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var avatar: some View {
        switch appViewModel.authStatus {
        case .signedIn(let user):
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                Text(initials(for: user))
                    .font(.title2.bold())
                    .foregroundStyle(Color.accentColor)
            }
        case .loading:
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                ProgressView()
            }
        case .signedOut:
            ZStack {
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                Image(systemName: "person.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var title: String {
        switch appViewModel.authStatus {
        case .signedIn:
            if let username = appViewModel.profile?.username, !username.isEmpty {
                return username
            }
            return "欢迎回来"
        case .signedOut:
            return "欢迎注册"
        case .loading:
            return "正在加载账户"
        }
    }

    private var subtitle: String {
        switch appViewModel.authStatus {
        case .signedIn(let user):
            return appViewModel.profile?.email ?? user.email ?? "未绑定邮箱"
        case .signedOut:
            return "登录后即可同步排班、同事与统计数据"
        case .loading:
            return "请稍候..."
        }
    }

    private func initials(for user: User) -> String {
        if let username = appViewModel.profile?.username, let initial = username.first {
            return String(initial).uppercased()
        }
        if let email = user.email, let initial = email.first {
            return String(initial).uppercased()
        }
        return "你"
    }
}

struct AccountManagementView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        Group {
            switch appViewModel.authStatus {
            case .loading:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在连接 Supabase...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())

            case .signedOut:
                AuthFlowView()
                    .navigationTitle("登录 / 注册")

            case .signedIn(let user):
                ProfileDetailView(user: user)
                    .navigationTitle("账号设置")
            }
        }
    }
}

private enum AuthMode: String, CaseIterable, Identifiable {
    case signIn = "登录"
    case signUp = "注册"

    var id: String { rawValue }

    var buttonTitle: String {
        switch self {
        case .signIn: return "登录"
        case .signUp: return "创建账号"
        }
    }
}

private struct AuthFlowView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var localError: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
        case username
    }

    var body: some View {
        Form {
            Section {
                Picker("模式", selection: $mode) {
                    ForEach(AuthMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(header: Text("邮箱")) {
                TextField("name@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
            }

            Section(header: Text("密码")) {
                SecureField("至少 6 位密码", text: $password)
                    .focused($focusedField, equals: .password)
            }

            if mode == .signUp {
                Section(header: Text("用户名（可选）")) {
                    TextField("展示名称", text: $username)
                        .focused($focusedField, equals: .username)
                }
            }

            if let error = localError {
                Section {
                    Text(error)
                        .foregroundStyle(Color.red)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                }
            }

            Section {
                Button {
                    handlePrimaryAction()
                } label: {
                    HStack {
                        Spacer()
                        if appViewModel.isAuthBusy {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text(mode.buttonTitle)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .tint(.accentColor)
                .disabled(appViewModel.isAuthBusy || !isFormValid)
            } footer: {
                Text("使用 Supabase 认证服务安全存储账号。登录后即可跨设备同步排班与同事信息。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .autocorrectionDisabled(true)
        .scrollDismissesKeyboard(.interactively)
    }

    private var isFormValid: Bool {
        guard email.contains("@"), password.count >= 6 else { return false }
        return true
    }

    private func handlePrimaryAction() {
        localError = nil
        Task {
            do {
                switch mode {
                case .signIn:
                    try await appViewModel.signIn(email: email, password: password)
                case .signUp:
                    try await appViewModel.signUp(
                        email: email,
                        password: password,
                        username: username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : username
                    )
                }
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    localError = error.localizedDescription
                }
            }
        }
    }
}

private struct ProfileDetailView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let user: User
    @State private var usernameText: String = ""
    @State private var isSaving = false
    @State private var statusMessage: StatusMessage?

    private enum StatusMessage {
        case success(String)
        case error(String)

        var text: String {
            switch self {
            case .success(let text), .error(let text):
                return text
            }
        }

        var color: Color {
            switch self {
            case .success:
                return Color.green
            case .error:
                return Color.red
            }
        }
    }

    var body: some View {
        Form {
            Section(header: Text("登录邮箱")) {
                HStack {
                    Text(appViewModel.profile?.email ?? user.email ?? "未绑定邮箱")
                    Spacer()
                }
            }

            Section(header: Text("用户名")) {
                TextField("展示名称", text: $usernameText)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)

                if let statusMessage {
                    Text(statusMessage.text)
                        .font(.footnote)
                        .foregroundStyle(statusMessage.color)
                }

                Button {
                    Task {
                        await saveUsername()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存修改")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving || usernameText == (appViewModel.profile?.username ?? ""))
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        do {
                            try await appViewModel.signOut()
                            await MainActor.run {
                                dismiss()
                            }
                        } catch {
                            statusMessage = .error(error.localizedDescription)
                        }
                    }
                } label: {
                    Text("退出登录")
                }
            }
        }
        .onAppear {
            usernameText = appViewModel.profile?.username ?? ""
        }
    }

    private func saveUsername() async {
        guard usernameText != appViewModel.profile?.username ?? "" else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await appViewModel.updateUsername(usernameText.trimmingCharacters(in: .whitespacesAndNewlines))
            statusMessage = .success("用户名已更新")
        } catch {
            statusMessage = .error(error.localizedDescription)
        }
    }
}
