import Foundation

nonisolated enum EchoEngine {

    // MARK: Comparaison (lecture seule)

    /// Compare les favoris d'un profil source à ceux d'un profil de destination.
    /// Ne touche à aucun fichier ; les navigateurs peuvent rester ouverts.
    static func compare(source: ChromiumProfile,
                        destination: ChromiumProfile,
                        mode: EchoMatchMode,
                        options: EchoURLOptions = EchoURLOptions()) throws -> EchoReport {
        let sourceSnapshot = try snapshot(of: source)
        let destinationSnapshot = try snapshot(of: destination)
        let plan = EchoPlanner.plan(source: sourceSnapshot, destination: destinationSnapshot,
                                    mode: mode, options: options)

        return EchoReport(source: source,
                          destination: destination,
                          sourceCount: sourceSnapshot.bookmarks.count,
                          ignoredCount: sourceSnapshot.ignoredCount,
                          plan: plan,
                          mirror: EchoPlanner.mirrorPlan(source: sourceSnapshot, destination: destinationSnapshot))
    }

    /// Seul le fichier Bookmarks local compte : les favoris du compte Google (Chrome) ne sont pas gérés.
    private static func snapshot(of profile: ChromiumProfile) throws -> EchoSnapshot {
        guard FileManager.default.fileExists(atPath: profile.bookmarksURL.path) else {
            throw EchoError.noLocalBookmarks(profile.browserName)
        }
        return try EchoReader.read(from: profile.bookmarksURL)
    }

    // MARK: Écriture (navigateur de destination fermé, synchro inactive, sauvegardes automatiques)

    /// Écrit dans la destination, puis (si `copyFavicons`) copie les icônes.
    /// - `.merge` : ajoute les favoris du plan.
    /// - `.mirror` : fait de la destination l'image de la source (supprime ce qui n'y est pas).
    ///
    /// Tout est vérifié AVANT la moindre écriture : navigateur fermé, synchro inactive, fichiers
    /// inchangés depuis la comparaison, résultat relu en mémoire. Les sauvegardes sont faites juste avant.
    /// Les icônes passent avant les favoris : si leur écriture échoue, le fichier Bookmarks n'est pas
    /// touché par cet échec (les favoris sont alors écrits sans icône, et l'explication est dans le résumé).
    static func apply(_ report: EchoReport,
                      syncMode: EchoSyncMode = .merge,
                      mode: EchoMatchMode,
                      options: EchoURLOptions = EchoURLOptions(),
                      copyFavicons: Bool,
                      backupDirectory: URL = FaviconBackup.directory) async throws -> EchoApplySummary {
        let source = report.source
        let destination = report.destination
        let fm = FileManager.default

        switch syncMode {
        case .merge: guard !report.plan.toAdd.isEmpty else { throw EchoWriteError.nothingToAdd }
        case .mirror: guard !report.mirror.isIdentical else { throw EchoWriteError.nothingToChange }
        }
        guard !destination.isBrowserRunning else { throw EchoWriteError.browserRunning(destination.browserName) }
        guard BookmarkSyncStatus.detect(for: destination) != .enabled else {
            throw EchoWriteError.syncEnabled(destination.browserName)
        }

        // 1. Relire les deux fichiers : le plan doit être exactement celui que l'utilisateur a vu.
        guard fm.fileExists(atPath: source.bookmarksURL.path) else {
            throw EchoError.noLocalBookmarks(source.browserName)
        }
        guard fm.fileExists(atPath: destination.bookmarksURL.path) else {
            throw EchoError.noLocalBookmarks(destination.browserName)
        }
        let sourceData = try Data(contentsOf: source.bookmarksURL)
        let sourceSnapshot = try EchoReader.parse(sourceData)
        let original = try Data(contentsOf: destination.bookmarksURL)
        let destinationSnapshot = try EchoReader.parse(original)

        // 2. Écriture en mémoire, puis relecture : le résultat doit se relire (par Echo et par Navloom)
        //    et correspondre exactement à ce qui était annoncé.
        let newData: Data
        let iconBookmarks: [EchoBookmark]
        let addedCount: Int
        let createdFolders: Int
        let removedCount: Int
        let removedFolders: Int

        switch syncMode {
        case .merge:
            let current = EchoPlanner.plan(source: sourceSnapshot, destination: destinationSnapshot,
                                           mode: mode, options: options)
            guard current.toAdd == report.plan.toAdd else { throw EchoWriteError.destinationChanged }

            let merged = try EchoWriter.merging(current.toAdd, into: original)
            let after = try EchoReader.parse(merged.data)
            let presentAnywhere = EchoPlanner.plan(source: sourceSnapshot, destination: after,
                                                   mode: .anywhere, options: options)
            guard merged.added == current.toAdd.count,
                  after.bookmarks.count == destinationSnapshot.bookmarks.count + current.toAdd.count,
                  (try? BookmarksReader.parse(merged.data)) != nil,
                  presentAnywhere.toAdd.isEmpty else {
                throw EchoWriteError.verificationFailed
            }
            newData = merged.data
            iconBookmarks = current.toAdd
            addedCount = merged.added
            createdFolders = merged.createdFolders
            removedCount = 0
            removedFolders = 0

        case .mirror:
            guard !sourceSnapshot.bookmarks.isEmpty else { throw EchoWriteError.sourceEmpty }
            let current = EchoPlanner.mirrorPlan(source: sourceSnapshot, destination: destinationSnapshot)
            guard current == report.mirror else { throw EchoWriteError.destinationChanged }

            let written = try EchoWriter.mirroring(source: sourceData, into: original)
            let after = try EchoReader.parse(written)
            let expectedKeys = current.expected.map(EchoReader.exactKey)
            let sameRoots = Set(sourceSnapshot.bookmarks.map(\.rootKey))
                .union(sourceSnapshot.folders.map(\.rootKey)).isSubset(of: destinationSnapshot.rootKeys)
            // Même favoris (et, quand les racines sont les mêmes, même arbre dans le même ordre),
            // plus rien de non web, et les dossiers de la source sont tous là.
            guard after.bookmarks.map(EchoReader.exactKey).sorted() == expectedKeys.sorted(),
                  !sameRoots || after.layout == sourceSnapshot.layout,
                  after.ignoredCount == 0,
                  (try? BookmarksReader.parse(written)) != nil else {
                throw EchoWriteError.verificationFailed
            }
            newData = written
            iconBookmarks = current.expected
            addedCount = current.toAdd.count
            createdFolders = current.foldersToAdd
            removedCount = current.removalCount
            removedFolders = current.foldersToRemove
        }

        // 3. Lire les icônes de la source (lecture seule : le navigateur source peut rester ouvert).
        var icons: [String: StoredFavicon] = [:]
        var iconsRead = false
        var note: String?
        if copyFavicons {
            if fm.fileExists(atPath: source.faviconsURL.path), fm.fileExists(atPath: destination.faviconsURL.path) {
                do {
                    let database = try FaviconDatabase(url: source.faviconsURL, writable: false)
                    icons = try await database.favicons(forPages: iconBookmarks.map(\.url))
                    iconsRead = true
                } catch {
                    note = "Les icônes de la source n'ont pas pu être lues (\(error.localizedDescription)). Les favoris sont ajoutés sans icône."
                }
            } else {
                note = "La source ou la cible n'a pas de base Favicons : les favoris sont ajoutés sans icône."
            }
        }

        // 4. Sauvegardes, avant toute écriture.
        let bookmarksBackup = try FaviconBackup.create(from: destination.bookmarksURL, label: destination.id,
                                                       category: .bookmarks, tool: .echo, in: backupDirectory)
        var faviconsBackup: URL?
        if !icons.isEmpty {
            faviconsBackup = try FaviconBackup.create(from: destination.faviconsURL, label: destination.id,
                                                      category: .favicons, tool: .echo, in: backupDirectory)
        }

        // 5. Icônes (dans une transaction : tout ou rien).
        var copied = 0
        var failed = 0
        var targetMapped = Set<String>()
        if !icons.isEmpty {
            var database: FaviconDatabase?
            do {
                let db = try FaviconDatabase(url: destination.faviconsURL, writable: true)
                database = db
                var mapped = try await db.urlsWithFavicon()
                targetMapped = mapped
                try await db.begin()

                var iconIDs: [String: Int64] = [:]
                for bookmark in iconBookmarks {
                    // Une page qui a déjà une icône dans la destination (historique…) n'est pas touchée.
                    guard let stored = icons[bookmark.url], !mapped.contains(bookmark.url) else { continue }
                    do {
                        let iconID: Int64
                        if let known = iconIDs[stored.iconURL] {
                            iconID = known
                        } else if let existing = try await db.iconID(forIconURL: stored.iconURL) {
                            iconID = existing
                            iconIDs[stored.iconURL] = existing
                        } else {
                            let bitmaps = pngBitmaps(from: stored.bitmaps)
                            guard !bitmaps.isEmpty else { throw FaviconDatabaseError.query("image illisible") }
                            iconID = try await db.insertIcon(sourceURL: stored.iconURL, bitmaps: bitmaps)
                            iconIDs[stored.iconURL] = iconID
                        }
                        try await db.insertMapping(pageURL: bookmark.url, iconID: iconID)
                        mapped.insert(bookmark.url)
                        copied += 1
                    } catch {
                        failed += 1
                    }
                }
                try await db.commit()
            } catch {
                await database?.rollback()
                copied = 0
                failed = 0
                note = "Les icônes n'ont pas pu être écrites (\(error.localizedDescription)) : la base Favicons n'a pas été modifiée. Les favoris sont ajoutés sans icône."
            }
        }

        // 6. Favoris : le fichier ne doit pas avoir bougé depuis la lecture.
        guard try Data(contentsOf: destination.bookmarksURL) == original else {
            throw EchoWriteError.destinationChanged
        }
        let permissions = (try? fm.attributesOfItem(atPath: destination.bookmarksURL.path))?[.posixPermissions]
        try newData.write(to: destination.bookmarksURL, options: .atomic)
        if let permissions {
            try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination.bookmarksURL.path)
        }

        let missing = iconsRead ? iconBookmarks.filter { icons[$0.url] == nil && !targetMapped.contains($0.url) }.count : 0
        if failed > 0 && note == nil {
            note = "\(failed) icône\(failed > 1 ? "s" : "") n'ont pas pu être écrites."
        }

        return EchoApplySummary(mode: syncMode,
                                added: addedCount,
                                createdFolders: createdFolders,
                                removed: removedCount,
                                removedFolders: removedFolders,
                                faviconsCopied: copied,
                                faviconsMissing: missing,
                                faviconsFailed: failed,
                                bookmarksBackupURL: bookmarksBackup,
                                faviconsBackupURL: faviconsBackup,
                                faviconNote: note)
    }

    // MARK: Images

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47])

    /// Les bitmaps à écrire : du PNG, comme Vivaldi le fait lui-même (des images brutes .ico ou .gif
    /// n'étaient pas affichées). Un PNG déjà valide est gardé tel quel ; le reste est converti.
    static func pngBitmaps(from stored: [FaviconBitmap]) -> [FaviconBitmap] {
        stored.compactMap { bitmap in
            if bitmap.size > 0, bitmap.png.starts(with: pngSignature) { return bitmap }
            let size = bitmap.size > 0 ? bitmap.size : 16
            return FaviconImage.squarePNG(from: bitmap.png, pixelSize: size)
                .map { FaviconBitmap(size: size, png: $0) }
        }
    }
}
