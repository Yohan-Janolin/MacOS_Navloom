//
//  FaviconBackup.swift
//  Navloom
//
//  Created by Yohan Janolin on 30/09/2026.
//


import Foundation

/// Copie de sécurité de la base Favicons avant toute écriture.
/// Stockée dans ~/Library/Application Support/Navloom/Backups/
nonisolated enum FaviconBackup {
    static func create(from source: URL, label: String) throws -> URL {
        let fm = FileManager.default
        let directory = URL.applicationSupportDirectory
            .appending(path: "Navloom/Backups", directoryHint: .isDirectory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safeLabel = label.replacingOccurrences(of: "/", with: "-")
        let destination = directory.appending(path: "\(safeLabel)-Favicons-\(stamp).sqlite")

        try fm.copyItem(at: source, to: destination)
        return destination
    }
}