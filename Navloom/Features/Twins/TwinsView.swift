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

            if model.phase == .done {
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
                groupsList
            }
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
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(group.bookmarks.count) favoris")
                    }
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

            Button(model.phase == .done ? "Nouvelle analyse" : "Chercher les doublons") {
                model.analyze()
            }
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
