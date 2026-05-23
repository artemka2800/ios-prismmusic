//
//  SettingsView.swift
//  PrismMusic
//
//  Backend URL + Yandex token + immersive toggle. Persisted via
//  `SettingsStore`. The Yandex token field is secure (masked).
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var backendDraft: String = ""
    @State private var tokenDraft: String = ""
    @State private var showTokenInfo = false
    @State private var savedFlash = false
    @State private var showDebugLogs = false
    @State private var logsContent = ""
    @State private var isImporting = false
    @State private var showImportAlert = false
    @State private var importAlertMessage = ""

    enum AuthMode {
        case login, register
    }
    @State private var authMode: AuthMode = .login
    @State private var usernameDraft: String = ""
    @State private var passwordDraft: String = ""
    @State private var isAuthenticating = false
    @State private var authError: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                ImmersiveBackground()
                    .ignoresSafeArea()

                Form {
                    Section {
                        TextField("https://prism.example.com", text: $backendDraft)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .tint(.white)
                    } header: {
                        Text("Сервер PrismMusic")
                    } footer: {
                        Text("URL Next.js-бэкенда. Должен быть доступен с устройства. Для локальной разработки используй IP-адрес твоего Mac в LAN, не localhost.")
                    }

                    Section {
                        if app.settings.isLoggedIn {
                            HStack {
                                Label("Вы вошли как", systemImage: "person.circle.fill")
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(app.settings.username)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                            
                            Button(role: .destructive) {
                                withAnimation {
                                    app.settings.logout()
                                    usernameDraft = ""
                                    passwordDraft = ""
                                }
                            } label: {
                                Label("Выйти из аккаунта", systemImage: "arrow.left.circle")
                                    .foregroundStyle(.red)
                            }
                        } else {
                            Picker("Режим", selection: $authMode) {
                                Text("Вход").tag(AuthMode.login)
                                Text("Регистрация").tag(AuthMode.register)
                            }
                            .pickerStyle(.segmented)
                            .padding(.vertical, 4)
                            
                            TextField("Имя пользователя", text: $usernameDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(.white)
                                .tint(.white)
                            
                            SecureField("Пароль", text: $passwordDraft)
                                .foregroundStyle(.white)
                                .tint(.white)
                            
                            if !authError.isEmpty {
                                Text(authError)
                                    .font(Theme.Typography.secondary)
                                    .foregroundStyle(.red)
                            }
                            
                            Button {
                                performAuth()
                            } label: {
                                HStack {
                                    Spacer()
                                    if isAuthenticating {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text(authMode == .login ? "Войти" : "Зарегистрироваться")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.white)
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(usernameDraft.isEmpty || passwordDraft.isEmpty || isAuthenticating)
                        }
                    } header: {
                        Text("Аккаунт PrismMusic")
                    }


                    Section {
                        SecureField("Введи Yandex.Music token", text: $tokenDraft)
                            .foregroundStyle(.white)
                            .tint(.white)

                        Button {
                            showTokenInfo = true
                        } label: {
                            Label("Как получить токен?", systemImage: "questionmark.circle")
                                .foregroundStyle(.white)
                        }

                        if !app.settings.yandexToken.isEmpty {
                            Button {
                                importYandexLikes()
                            } label: {
                                HStack {
                                    Label("Импортировать любимые треки", systemImage: "arrow.down.circle")
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if isImporting {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                }
                            }
                            .disabled(isImporting)
                        }
                    } header: {
                        Text("Yandex.Music")
                    } footer: {
                        Text("Без токена доступен только SoundCloud. Токен хранится в Keychain устройства, бэкенд получает его одноразово в каждом запросе стрима.")
                    }

                    Section {
                        Toggle(isOn: Binding(
                            get: { app.settings.immersiveMode },
                            set: { app.settings.immersiveMode = $0 }
                        )) {
                            Label("Immersive фон", systemImage: "sparkles")
                                .foregroundStyle(.white)
                        }
                        .tint(.white)
                    } header: {
                        Text("Внешний вид")
                    } footer: {
                        Text("Immersive фон подкрашивает фон приложения цветом текущей обложки.")
                    }

                    Section {
                        Button {
                            logsContent = DebugLogger.shared.readLogs()
                            showDebugLogs = true
                        } label: {
                            Label("Посмотреть логи (Debug)", systemImage: "ladybug")
                                .foregroundStyle(.white)
                        }
                        Button {
                            DebugLogger.shared.clearLogs()
                        } label: {
                            Label("Очистить логи", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Отладка")
                    }

                    Section {
                        Button {
                            save()
                        } label: {
                            HStack {
                                Spacer()
                                if savedFlash {
                                    Label("Сохранено", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Text("Сохранить")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                }
                                Spacer()
                            }
                        }
                        .disabled(savedFlash)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaPadding(.bottom, app.audio.currentTrack != nil ? 100 : 0)
            .alert("Yandex.Music token", isPresented: $showTokenInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("1. Открой music.yandex.ru\n2. DevTools → Application → Cookies → Session_id\n3. Скопируй и вставь сюда. Также можно получить через oauth.yandex.com.")
            }
            .alert("Импорт любимых треков", isPresented: $showImportAlert) {
                Button("OK", role: roleCancelForAlert) {}
            } message: {
                Text(importAlertMessage)
            }
            .sheet(isPresented: $showDebugLogs) {
                NavigationStack {
                    ScrollView {
                        Text(logsContent)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("Логи")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Закрыть") { showDebugLogs = false }
                        }
                    }
                }
            }
        }
        .onAppear {
            backendDraft = app.settings.backendURL
            tokenDraft = app.settings.yandexToken
        }
    }

    private var roleCancelForAlert: ButtonRole? {
        #if os(macOS)
        return nil
        #else
        return .cancel
        #endif
    }

    private func importYandexLikes() {
        isImporting = true
        Task {
            do {
                let response = try await app.api.importYandexLikes()
                let importedTracksCount = app.library.importYandexTracks(response.importedLikes)
                importAlertMessage = "Успешно импортировано \(importedTracksCount) новых треков из Яндекс.Музыки!"
                showImportAlert = true
            } catch {
                importAlertMessage = "Ошибка импорта: \(error.localizedDescription)"
                showImportAlert = true
            }
            isImporting = false
        }
    }

    private func save() {
        app.settings.backendURL = backendDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        app.settings.yandexToken = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(Theme.Motion.snap) {
            savedFlash = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation { savedFlash = false }
        }
    }

    private func performAuth() {
        isAuthenticating = true
        authError = ""
        
        Task {
            do {
                let response: UserResponse
                if authMode == .login {
                    response = try await app.api.login(
                        username: usernameDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: passwordDraft
                    )
                } else {
                    response = try await app.api.register(
                        username: usernameDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: passwordDraft
                    )
                }
                
                // Success! Save details
                app.settings.userId = response.id
                app.settings.username = response.username
                if let serverYandexToken = response.token, !serverYandexToken.isEmpty {
                    app.settings.yandexToken = serverYandexToken
                    tokenDraft = serverYandexToken
                }
                
                // Clear draft inputs
                usernameDraft = ""
                passwordDraft = ""
                authError = ""
                
                // Sync library likes
                await app.library.syncWithServer()
                
            } catch {
                if case APIError.httpStatus(let code, let preview) = error {
                    if let preview = preview,
                       let previewData = preview.data(using: .utf8),
                       let errObj = try? JSONSerialization.jsonObject(with: previewData) as? [String: Any],
                       let errMsg = errObj["error"] as? String {
                        authError = errMsg
                    } else {
                        authError = "Неверный логин или пароль (код \(code))"
                    }
                } else {
                    authError = error.localizedDescription
                }
            }
            isAuthenticating = false
        }
    }
}
