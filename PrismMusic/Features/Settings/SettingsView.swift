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

    var body: some View {
        NavigationStack {
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
            .background(Color.clear)
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
}
