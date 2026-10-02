import Foundation

/// Combien de sauvegardes garder, par profil de navigateur et par type.
nonisolated struct BackupRetention: Sendable {
    static let defaultKeepBeforeWrite = 10
    static let defaultKeepBeforeRestore = 5

    let keepBeforeWrite: Int
    let keepBeforeRestore: Int

    /// Les réglages actuels, ou nil si le nettoyage automatique est désactivé.
    static var current: BackupRetention? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.autoPrune) else { return nil }
        return BackupRetention(
            keepBeforeWrite: defaults.object(forKey: SettingsKey.keepBeforeWrite) as? Int ?? defaultKeepBeforeWrite,
            keepBeforeRestore: defaults.object(forKey: SettingsKey.keepBeforeRestore) as? Int ?? defaultKeepBeforeRestore
        )
    }
}
