//
//  TwinsView.swift
//  Navloom
//

import SwiftUI

struct TwinsView: View {
    @Bindable var model: TwinsViewModel

    var body: some View {
        Group {
            if !model.hasLoaded {
                ProgressView()
            } else if model.browsers.isEmpty {
                ContentUnavailableView(
                    "Aucun navigateur détecté",
                    systemImage: "globe",
                    description: Text("Navloom cherche Vivaldi, Chrome, Brave et Edge dans ~/Library/Application Support.")
                )
            } else {
                content
            }
        }
        .navigationTitle("Navloom")
        .task { model.loadBrowsersIfNeeded() }
        .onChange(of: model.selectedBrowserID) { model.browserChanged() }
        .onChange(of: model.selectedProfileID) { model.reset() }
        // Tant qu'on peut supprimer, on surveille si le navigateur est fermé.
        .task(id: model.phase) {
            guard model.phase == .done else { return }
            while !Task.isCancelled {
                model.refreshBrowserRunning()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .confirmationDialog(
            "Supprimer \(model.selection.count) favori\(model.selection.count > 1 ? "s" : "") ?",
            isPresented: $model.showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) { model.removeSelected() }
        } message: {
            Text("Les favoris cochés seront retirés de \(model.selectedBrowser?.name ?? "ce navigateur"). Une sauvegarde du fichier Bookmarks est créée avant.")
        }
    }

    // MARK: - Structure

    private var content: some View {
        VStack(spacing: 16) {
            titleHeader
            BrowserProfileBanner(browsers: model.browsers,
                                 profiles: model.profiles,
                                 browserID: $model.selectedBrowserID,
                                 profileID: $model.selectedProfileID,
                                 colors: Self.gradient)
                .disabled(model.isBusy)

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.phase == .done || model.phase == .removing {
                stats
            }

            middle
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            actionBar
        }
        .padding(20)
    }

    private var titleHeader: some View {
        VStack(spacing: 4) {
            Text("Twins")
                .font(.largeTitle.bold())
                .foregroundStyle(
                    LinearGradient(colors: Self.gradient,
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Retrouve les favoris qui pointent sur la même URL")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Dégradé propre à Twins (FaviconSync utilise corail → violet).
    private static let gradient = [Brand.sky, Brand.teal]

    private var stats: some View {
        HStack(spacing: 12) {
            TwinsStat(title: "Favoris", value: model.totalBookmarks, systemImage: "bookmark")
            TwinsStat(title: "URLs en double", value: model.groups.count,
                      systemImage: "square.on.square", tint: Brand.sky)
            TwinsStat(title: "Favoris en trop", value: model.extraCopies,
                      systemImage: "minus.circle", tint: .orange)
        }
    }

    // MARK: - Zone centrale

    @ViewBuilder
    private var middle: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "Prêt à chercher les doublons",
                systemImage: "square.on.square",
                description: Text("Navloom regroupe les favoris qui pointent exactement sur la même URL. L'analyse ne modifie rien.")
            )
        case .analyzing:
            ProgressView("Lecture des favoris…")
        case .done:
            if model.groups.isEmpty {
                ContentUnavailableView("Aucun doublon", systemImage: "checkmark.seal",
                                       description: Text("Aucune URL n'apparaît deux fois dans tes favoris."))
            } else {
                VStack(spacing: 12) {
                    removalNotice
                    groupsList
                }
            }
        case .removing:
            ProgressView("Suppression des doublons…")
        case .removed:
            removedView
        }
    }

    /// Bandeau au-dessus de la liste : ce qui bloque la suppression, sinon rappel de la sauvegarde.
    @ViewBuilder
    private var removalNotice: some View {
        if model.isBrowserRunning {
            notice("\(model.selectedBrowser?.name ?? "Le navigateur") est ouvert. Ferme-le complètement (Cmd + Q) pour pouvoir supprimer.",
                   systemImage: "exclamationmark.triangle.fill", tint: .orange)
        } else if model.fullySelectedGroupCount > 0 {
            let count = model.fullySelectedGroupCount
            notice("Dans \(count) groupe\(count > 1 ? "s" : ""), toutes les copies sont cochées. Décoches-en au moins une pour la garder.",
                   systemImage: "exclamationmark.triangle.fill", tint: .orange)
        } else {
            notice("Une sauvegarde du fichier Bookmarks sera créée automatiquement avant la suppression.",
                   systemImage: "externaldrive", tint: .secondary)
        }
    }

    private func notice(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var removedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            if let summary = model.summary {
                Text("\(summary.removed) favori\(summary.removed > 1 ? "s" : "") supprimé\(summary.removed > 1 ? "s" : "")")
                    .font(.title2.bold())
                Button("Afficher la sauvegarde dans le Finder") { model.revealBackup() }
            }
            Text("Relance \(model.selectedBrowser?.name ?? "le navigateur") pour voir le résultat.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var groupsList: some View {
        List {
            ForEach(model.groups) { group in
                Section {
                    ForEach(group.bookmarks, id: \.self) { bookmark in
                        TwinRow(
                            bookmark: bookmark,
                            isChecked: Binding(
                                get: { model.isSelected(bookmark) },
                                set: { _ in model.toggle(bookmark) }
                            )
                        )
                    }
                } header: {
                    HStack {
                        Text(group.url)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(group.bookmarks.count) favoris")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Barre d'action

    private var actionBar: some View {
        HStack {
            if model.phase == .done {
                Button("Annuler") { model.reset() }

                if !model.groups.isEmpty {
                    Button("Garder le premier de chaque groupe") { model.selectAllButFirst() }
                    Button("Tout décocher") { model.clearSelection() }
                        .disabled(model.selection.isEmpty)

                    Text("\(model.selection.count) coché\(model.selection.count > 1 ? "s" : "")")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer()

            primaryActions
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        switch model.phase {
        case .done where !model.groups.isEmpty:
            Button("Nouvelle analyse") { model.analyze() }
                .controlSize(.large)
            Button("Supprimer \(model.selection.count) favori\(model.selection.count > 1 ? "s" : "")") {
                model.showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!model.canRemove)
        case .done, .removed:
            Button("Nouvelle analyse") { model.analyze() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .removing:
            Button("Suppression en cours…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        case .idle, .analyzing:
            Button("Chercher les doublons") { model.analyze() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedProfile == nil || model.isBusy)
        }
    }
}

// MARK: - Sous-vues

private struct TwinsStat: View {
    let title: String
    let value: Int
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.title2.bold().monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TwinRow: View {
    let bookmark: Bookmark
    @Binding var isChecked: Bool

    var body: some View {
        Toggle(isOn: $isChecked) {
            VStack(alignment: .leading, spacing: 1) {
                Text(bookmark.name).lineLimit(1)
                Label(bookmark.folder.isEmpty ? "Racine" : bookmark.folder, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 2)
    }
}

#Preview {
    TwinsView(model: TwinsViewModel())
}
