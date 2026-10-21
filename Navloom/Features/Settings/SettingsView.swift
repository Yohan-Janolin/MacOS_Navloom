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
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("General")
            } footer: {
                Text("“System” follows the macOS setting. The other two force the appearance, whatever that setting is.")
            }

            Section {
                LabeledContent("Backup location") {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(verbatim: (FaviconBackup.directory.path as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack {
                            Button("Choose…") { chooseFolder() }
                            Button("Default") { changeDirectory(to: "") }
                                .disabled(backupDirectoryPath.isEmpty)
                            Button("Show") { revealFolder() }
                        }
                    }
                }

                Toggle("Automatically delete old backups", isOn: $autoPrune)

                if autoPrune {
                    Stepper(value: $keepBeforeWrite, in: 1...100) {
                        Text("Keep \(keepBeforeWrite) backups “before write”")
                    }
                    Stepper(value: $keepBeforeRestore, in: 1...100) {
                        Text("Keep \(keepBeforeRestore) backups “before restore”")
                    }
                    Button("Clean Up Now") { cleanNow() }
                }
            } header: {
                Text("Backups")
            } footer: {
                Text("A backup is created automatically before every write (favicon database for FaviconSync, Bookmarks file for Twins and Ghosts, both for Echo) and before every restore. Backups are counted separately for each browser profile and each tool; extra backups are moved to the Trash, not deleted permanently.")
            }

            if let message {
                Section {
                    Label(message, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .confirmationDialog(
            "Move existing backups?",
            isPresented: Binding(
                get: { pendingMove != nil },
                set: { if !$0 { pendingMove = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingMove
        ) { move in
            Button("Move \(move.count) backups") { performMove(move) }
            Button("Leave Them in Place", role: .cancel) {}
        } message: { move in
            Text("The previous folder contains \(move.count) backups. If you leave them in place, they won't appear on the Backups screen anymore.")
        }
    }

    // MARK: - Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
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
            message = String(localized: "\(moved) backups moved.")
        } catch {
            message = String(localized: "Couldn't move them: \(error.localizedDescription)")
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
            ? String(localized: "Nothing to clean up.")
            : String(localized: "\(removed) backups moved to the Trash.")
    }
}

#Preview {
    SettingsView()
}
