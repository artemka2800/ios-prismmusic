import SwiftUI

struct PlaylistEditView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let playlist: Album
    var onSave: (Album) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var coverUrl: String = ""
    @State private var isSaving = false
    @State private var isShowingDeleteAlert = false

    init(playlist: Album, onSave: @escaping (Album) -> Void, onDelete: (() -> Void)? = nil) {
        self.playlist = playlist
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: playlist.title)
        _description = State(initialValue: playlist.artist)
        _coverUrl = State(initialValue: playlist.cover?.absoluteString ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Редактировать плейлист")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Измените основные свойства плейлиста")
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                    VStack(spacing: 16) {
                        // Name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Название")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                            TextField("Название плейлиста", text: $name)
                                .padding(12)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                                .foregroundStyle(.white)
                                .tint(.white)
                        }

                        // Description
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Описание")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                            TextField("Добавьте описание", text: $description)
                                .padding(12)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                                .foregroundStyle(.white)
                                .tint(.white)
                        }

                        // Cover URL
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ссылка на обложку")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                            TextField("URL-ссылка на обложку (необязательно)", text: $coverUrl)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                                .foregroundStyle(.white)
                                .tint(.white)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()

                    VStack(spacing: 12) {
                        // Save Button
                        Button {
                            savePlaylist()
                        } label: {
                            HStack {
                                Spacer()
                                if isSaving {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text("Сохранить")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.black)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.3) : Color.white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

                        // Delete Button
                        if onDelete != nil {
                            Button {
                                isShowingDeleteAlert = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Удалить плейлист")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.red)
                                    Spacer()
                                }
                                .padding()
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .alert("Удаление плейлиста", isPresented: $isShowingDeleteAlert) {
                Button("Удалить", role: .destructive) {
                    deletePlaylist()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Вы действительно хотите удалить этот плейлист? Это действие невозможно отменить.")
            }
        }
    }

    private func savePlaylist() {
        isSaving = true
        Task {
            let updatedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let updatedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let updatedCover = coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let updated = await app.library.updatePlaylist(
                playlistId: playlist.id,
                name: updatedName,
                description: updatedDesc,
                coverUrl: updatedCover
            ) {
                onSave(updated)
                dismiss()
            }
            isSaving = false
        }
    }

    private func deletePlaylist() {
        guard let onDelete else { return }
        Task {
            await app.library.deletePlaylist(playlist)
            onDelete()
            dismiss()
        }
    }
}
