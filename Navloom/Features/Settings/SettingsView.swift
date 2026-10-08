import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage(SettingsKey.backupDirectory) private var backupDirectoryPath = ""
    @AppStorage(SettingsKey.autoPrune) private var autoPrune = false
    @AppStorage(SettingsKey.keepBeforeWrite) private var keepBeforeWrite = BackupRetention.defaultKeepBeforeWrite
    @AppStorage(SettingsKey.keepBeforeRestore) private var keepBeforeRestore = BackupRetention.defaultKeepBeforeRestore
    @AppStorage(SettingsKey.appearance) private var appearance = AppAppearance.system

    private struct PendingMove {
        let from: URL
        let to: URL
        let count: Int
    }

    @State private var pendingMove: PendingMove?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Picker("Apparence", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Général")
            } footer: {
                Text("« Système » suit le réglage de macOS. Les deux autres forcent l'apparence, quel que soit ce réglage.")
            }

            Section {
                LabeledContent("Emplacement des sauvegardes") {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text((FaviconBackup.directory.path as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack {
                            Button("Choisir…") { chooseFolder() }
                            Button("Par défaut") { changeDirectory(to: "") }
                                .disabled(backupDirectoryPath.isEmpty)
                            Button("Afficher") { revealFolder() }
                        }
                    }
                }

                Toggle("Supprimer automatiquement les anciennes sauvegardes", isOn: $autoPrune)

                if autoPrune {
                    Stepper(value: $keepBeforeWrite, in: 1...100) {
                        Text("Conserver \(keepBeforeWrite) sauvegarde\(keepBeforeWrite > 1 ? "s" : "") « avant écriture »")
                    }
                    Stepper(value: $keepBeforeRestore, in: 1...100) {
                        Text("Conserver \(keepBeforeRestore) sauvegarde\(keepBeforeRestore > 1 ? "s" : "") « avant restauration »")
                    }
                    Button("Nettoyer maintenant") { cleanNow() }
                }
            } header: {
                Text("Sauvegardes")
            } footer: {
                Text("Une sauvegarde est créée automatiquement avant chaque écriture (base de favicons pour FaviconSync, fichier Bookmarks pour Twins et Ghosts, les deux pour Echo) et avant chaque restauration. Le décompte se fait séparément pour chaque profil de navigateur et chaque outil ; les sauvegardes en trop sont mises à la corbeille, pas supprimées définitivement.")
            }

            if let message {
                Section {
                    Label(message, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Paramètres")
        .confirmationDialog(
            "Déplacer les sauvegardes existantes ?",
            isPresented: Binding(
                get: { pendingMove != nil },
                set: { if !$0 { pendingMove = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingMove
        ) { move in
            Button("Déplacer \(move.count) sauvegarde\(move.count > 1 ? "s" : "")") { performMove(move) }
            Button("Laisser sur place", role: .cancel) {}
        } message: { move in
            Text("Le dossier précédent contient \(move.count) sauvegarde\(move.count > 1 ? "s" : ""). Si tu les laisses sur place, elles n'apparaîtront plus dans l'écran Sauvegardes.")
        }
    }

    // MARK: - Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.directoryURL = FaviconBackup.directory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        changeDirectory(to: url.path)
    }

    /// Change le dossier ; propose de déplacer les sauvegardes existantes.
    private func changeDirectory(to newPath: String) {
        let oldURL = FaviconBackup.directory
        backupDirectoryPath = newPath
        let newURL = FaviconBackup.directory

        guard oldURL.standardizedFileURL != newURL.standardizedFileURL else { return }
        let count = FaviconBackup.list(in: oldURL).count
        if count > 0 {
            pendingMove = PendingMove(from: oldURL, to: newURL, count: count)
        }
    }

    private func performMove(_ move: PendingMove) {
        do {
            let moved = try FaviconBackup.moveAll(from: move.from, to: move.to)
            message = "\(moved) sauvegarde\(moved > 1 ? "s" : "") déplacée\(moved > 1 ? "s" : "")."
        } catch {
            message = "Déplacement impossible : \(error.localizedDescription)"
        }
    }

    private func revealFolder() {
        try? FileManager.default.createDirectory(at: FaviconBackup.directory,
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.open(FaviconBackup.directory)
    }

    private func cleanNow() {
        let retention = BackupRetention(keepBeforeWrite: keepBeforeWrite,
                                        keepBeforeRestore: keepBeforeRestore)
        let removed = FaviconBackup.pruneAll(retention: retention)
        message = removed == 0
            ? "Rien à nettoyer."
            : "\(removed) sauvegarde\(removed > 1 ? "s" : "") mise\(removed > 1 ? "s" : "") à la corbeille."
    }
}

#Preview {
    SettingsView()
}
