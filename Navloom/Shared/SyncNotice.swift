import SwiftUI

/// Bandeau partagé par Twins, Ghosts, Echo et Sauvegardes : ce qui bloque (navigateur ouvert, synchro des
/// favoris active) ou, sinon, le rappel qu'une sauvegarde est créée avant l'écriture.
struct SyncNotice: View {
    enum Operation {
        /// `items` : ce qu'on supprime, avec son article, déjà traduit (« les doublons » / "the duplicates").
        case removal(items: String)
        case restoration
        /// Echo : ajout de favoris dans le navigateur de destination.
        case addition
        /// Echo : copie complète (ajouts et suppressions) dans le navigateur de destination.
        case mirror
    }

    let browserName: String
    let isBrowserRunning: Bool
    let syncStatus: BookmarkSyncStatus
    let operation: Operation

    var body: some View {
        let content = message
        Label(content.text, systemImage: content.systemImage)
            .foregroundStyle(content.tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(content.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var message: (text: String, systemImage: String, tint: Color) {
        let name = browserName

        if isBrowserRunning {
            let text: String
            switch operation {
            case .removal: text = String(localized: "\(name) is open. Quit it completely (Cmd + Q) to be able to delete.")
            case .restoration: text = String(localized: "\(name) is open. Quit it completely (Cmd + Q) to be able to restore.")
            case .addition: text = String(localized: "\(name) is open. Quit it completely (Cmd + Q) to be able to add.")
            case .mirror: text = String(localized: "\(name) is open. Quit it completely (Cmd + Q) to be able to copy.")
            }
            return (text, "exclamationmark.triangle.fill", .orange)
        }

        switch (syncStatus, operation) {
        case (.enabled, .removal(let items)):
            return (String(localized: "Bookmark sync is on in \(name): the next time it starts, it would bring back the deleted bookmarks. Turn it off in the browser's sync settings (the steps are on the Home screen), or delete \(items) directly in its bookmark manager."),
                    "arrow.triangle.2.circlepath", .orange)
        case (.enabled, .restoration):
            return (String(localized: "Bookmark sync is on in \(name): the next time it starts, it may replace the restored bookmarks with the ones in your account. Turn it off in the browser's sync settings (the steps are on the Home screen) before restoring."),
                    "arrow.triangle.2.circlepath", .orange)
        case (.enabled, .addition):
            return (String(localized: "Bookmark sync is on in \(name): the next time it starts, it may mix the added bookmarks with the ones in your account (duplicates, or a return to the account's state). Turn it off in the browser's sync settings (the steps are on the Home screen) before adding."),
                    "arrow.triangle.2.circlepath", .orange)
        case (.enabled, .mirror):
            return (String(localized: "Bookmark sync is on in \(name): the next time it starts, it would bring back the deleted bookmarks and mix the copy with the ones in your account. Turn it off in the browser's sync settings (the steps are on the Home screen) before the full copy."),
                    "arrow.triangle.2.circlepath", .orange)
        case (.unknown, .mirror):
            return (String(localized: "Navloom can't read the sync status of \(name). If sync is on, it may undo the copy. Backups are created automatically before writing."),
                    "info.circle", .secondary)
        case (.disabled, .mirror):
            return (String(localized: "Backups of the Bookmarks file (and of the Favicons database, if icons are copied) will be created automatically before the copy: you'll be able to roll back from the Backups screen."),
                    "externaldrive", .secondary)
        case (.unknown, .removal):
            return (String(localized: "Navloom can't read the sync status of \(name). If sync is on, it may bring back the deleted bookmarks. A backup of the Bookmarks file will be created before deleting."),
                    "info.circle", .secondary)
        case (.unknown, .restoration):
            return (String(localized: "Navloom can't read the sync status of \(name). If sync is on, it may undo the restore. The current state is backed up automatically beforehand."),
                    "info.circle", .secondary)
        case (.unknown, .addition):
            return (String(localized: "Navloom can't read the sync status of \(name). If sync is on, it may undo the addition. A backup is created automatically before writing."),
                    "info.circle", .secondary)
        case (.disabled, .removal):
            return (String(localized: "A backup of the Bookmarks file will be created automatically before deleting."),
                    "externaldrive", .secondary)
        case (.disabled, .restoration):
            return (String(localized: "The current state is backed up automatically before restoring."),
                    "externaldrive", .secondary)
        case (.disabled, .addition):
            return (String(localized: "A backup of the Bookmarks file (and of the Favicons database, if icons are copied) will be created automatically before adding."),
                    "externaldrive", .secondary)
        }
    }
}
