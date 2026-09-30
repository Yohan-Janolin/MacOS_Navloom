//
//  SettingsKey.swift
//  Navloom
//
//  Created by Yohan Janolin on 02/10/2026.
//


import Foundation

/// Clés des réglages dans UserDefaults (partagées avec @AppStorage dans l'écran Paramètres).
nonisolated enum SettingsKey {
    static let backupDirectory = "backupDirectoryPath"
    static let autoPrune = "autoPruneBackups"
    static let keepBeforeWrite = "keepBackupsBeforeWrite"
    static let keepBeforeRestore = "keepBackupsBeforeRestore"
}

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