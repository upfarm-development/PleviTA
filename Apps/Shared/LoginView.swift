
import SwiftUI
import PleviCore

struct LoginView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        // API Token first: it is the default, and the leading segment is the one people expect to
        // be selected.
        case token = "API Token"
        case password = "Username & Password"
        var id: String { rawValue }
    }

    @Environment(AuthStore.self) private var authStore

    @State private var mode: Mode = .token
    @State private var serverURLText = ""
    @State private var username = ""
    @State private var password = ""
    @State private var tokenText = ""
    @FocusState private var focusedField: Field?
    #if os(iOS)
    @State private var showSSOSheet = false
    #endif

    private enum Field {
        case serverURL, username, password, token
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(alignment: .leading, spacing: 8) {
                    Text("Server")
                        .font(.headline)
                    TextField("http://192.168.1.50:8000", text: $serverURLText)
                        .loginFieldStyle()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .serverURL)
                }

                modeSelector

                switch mode {
                case .password:
                    passwordFields
                case .token:
                    tokenField
                }

                if let errorMessage = authStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: submit) {
                    if authStore.isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(authStore.isBusy || !canSubmit)

                #if os(iOS)
                ssoButton
                #endif
            }
            .padding(32)
            .frame(maxWidth: loginColumnMaxWidth)
        }
        .scrollBounceBehavior(.basedOnSize)
        #if os(iOS)
        .sheet(isPresented: $showSSOSheet) {
            if let url = AuthStore.normalizedURL(from: serverURLText) {
                SSOLoginSheet(serverURL: url, probe: { await APIGateProbe()($0) }) {
                    authStore.errorMessage = nil
                }
            }
        }
        #endif
        .onAppear {
            if serverURLText.isEmpty, let devServerURL = DevServerConfig.serverURL {
                serverURLText = devServerURL
            }
            if tokenText.isEmpty, let devToken = DevServerConfig.token {
                tokenText = devToken
                mode = .token
            }
        }
    }

    #if os(iOS)
    private var ssoButton: some View {
        VStack(spacing: 8) {
            Text("Server behind an SSO or login page?")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                focusedField = nil
                showSSOSheet = true
            } label: {
                Label("Sign in via browser", systemImage: "globe")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    // A label alone is a ~17pt-tall tap target, well under the 44pt minimum — found live, where the button rendered correctly but swallowed taps.
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .disabled(AuthStore.normalizedURL(from: serverURLText) == nil)
        }
        .padding(.top, 8)
    }
    #endif

    private var loginColumnMaxWidth: CGFloat {
        #if os(tvOS)
        900
        #else
        480
        #endif
    }

    #if os(tvOS)
    private var modeSelector: some View {
        HStack(spacing: 16) {
            ForEach(Mode.allCases) { candidate in
                Button {
                    mode = candidate
                } label: {
                    Text(candidate.rawValue)
                        .font(.headline)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(mode == candidate ? Color.white : Color.white.opacity(0.15))
                        )
                        .foregroundStyle(mode == candidate ? Color.black : Color.white)
                        // Inside the label, and `pleviSelectableStyle` below.
                        .tvFocusRing(cornerRadius: 24)
                }
                .pleviSelectableStyle()
            }
        }
    }
    #else
    private var modeSelector: some View {
        Picker("Sign-in method", selection: $mode) {
            ForEach(Mode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
    #endif

    private var header: some View {
        VStack(spacing: 8) {
            // The app icon's own artwork (its middle and foreground layers, on a transparent
            // background), not a stand-in symbol.
            Image("LoginLogo")
                .resizable()
                .scaledToFit()
                #if os(tvOS)
                .frame(height: 160)
                #else
                .frame(height: 96)
                #endif
                .accessibilityHidden(true)
            Text("Plevi TA")
                .font(.largeTitle.bold())
            Text("Connect to your Tube Archivist server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var passwordFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Username", text: $username)
                .loginFieldStyle()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .focused($focusedField, equals: .username)
                .submitLabel(.next)
            SecureField("Password", text: $password)
                .loginFieldStyle()
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)
        }
    }

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("API token", text: $tokenText)
                .loginFieldStyle()
                .autocorrectionDisabled()
                .focused($focusedField, equals: .token)
                .submitLabel(.go)
                .onSubmit(submit)
            Text("On your Tube Archivist server: Settings → Application → Integrations.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var canSubmit: Bool {
        guard !serverURLText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch mode {
        case .password:
            return !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        case .token:
            return !tokenText.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func submit() {
        focusedField = nil
        guard canSubmit else { return }
        Task {
            switch mode {
            case .password:
                await authStore.loginWithPassword(serverURLText: serverURLText, username: username, password: password)
            case .token:
                await authStore.loginWithToken(serverURLText: serverURLText, token: tokenText)
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthStore(appSettings: AppSettings(), credentialStore: InMemoryCredentialStore()))
}

private extension View {
    @ViewBuilder
    func loginFieldStyle() -> some View {
        #if os(tvOS)
        self.frame(maxWidth: .infinity)
        #else
        self.textFieldStyle(.roundedBorder)
        #endif
    }
}
