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
                    Text("Подкрашивает фон приложения цветом текущей обложки.")
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
            .alert("Yandex.Music token", isPresented: $showTokenInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("1. Открой music.yandex.ru\n2. DevTools → Application → Cookies → Session_id\n3. Скопируй и вставь сюда. Также можно получить через oauth.yandex.com.")
            }
        }
        .onAppear {
            backendDraft = app.settings.backendURL
            tokenDraft = app.settings.yandexToken
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
