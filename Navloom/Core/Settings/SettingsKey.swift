import Foundation

/// Clés des réglages dans UserDefaults (partagées avec @AppStorage dans l'écran Paramètres).
nonisolated enum SettingsKey {
    static let backupDirectory = "backupDirectoryPath"
    static let autoPrune = "autoPruneBackups"
    static let keepBeforeWrite = "keepBackupsBeforeWrite"
    static let keepBeforeRestore = "keepBackupsBeforeRestore"
    static let appearance = "appearanceMode"
}


