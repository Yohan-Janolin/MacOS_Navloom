import SwiftUI

/// Bandeau partagé par Twins, Ghosts, Echo et Sauvegardes : ce qui bloque (navigateur ouvert, synchro des
/// favoris active) ou, sinon, le rappel qu'une sauvegarde est créée avant l'écriture.
struct SyncNotice: View {
    enum Operation {
        /// `items` : ce qu'on supprime, avec son article (« les doublons », « les liens morts »).
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
        let verb: String
        switch operation {
        case .removal: verb = "supprimer"
        case .restoration: verb = "restaurer"
        case .addition: verb = "ajouter"
        case .mirror: verb = "copier"
        }

        if isBrowserRunning {
            return ("\(browserName) est ouvert. Ferme-le complètement (Cmd + Q) pour pouvoir \(verb).",
                    "exclamationmark.triangle.fill", .orange)
        }

        switch (syncStatus, operation) {
        case (.enabled, .removal(let items)):
            return ("La synchro des favoris est activée dans \(browserName) : à son prochain lancement, elle remettrait les favoris supprimés. Désactive-la dans les réglages de synchronisation du navigateur (la marche à suivre est dans l'écran Accueil), ou supprime \(items) directement dans son gestionnaire de favoris.",
                    "arrow.triangle.2.circlepath", .orange)
        case (.enabled, .restoration):
            return ("La synchro des favoris est activée dans \(browserName) : à son prochain lancement, elle peut remplacer les favoris restaurés par ceux de ton compte. Désactive-la dans les réglages de synchronisation du navigateur (la marche à suivre est dans l'écran Accueil) avant de restaurer.",
                    "arrow.triangle.2.circlepath", .orange)
        case (.enabled, .addition):
            return ("La synchro des favoris est activée dans \(browserName) : à son prochain lancement, elle peut mélanger les favoris ajoutés avec ceux de ton compte (doublons, ou retour à l'état du compte). Désactive-la dans les réglages de synchronisation du navigateur (la marche à suivre est dans l'écran Accueil) avant d'ajouter.",
                    "arrow.triangle.2.circlepath", .orange)
        case (.enabled, .mirror):
            return ("La synchro des favoris est activée dans \(browserName) : à son prochain lancement, elle remettrait les favoris supprimés et mélangerait la copie avec ceux de ton compte. Désactive-la dans les réglages de synchronisation du navigateur (la marche à suivre est dans l'écran Accueil) avant la copie complète.",
                    "arrow.triangle.2.circlepath", .orange)
        case (.unknown, .mirror):
            return ("Navloom ne sait pas lire l'état de la synchro de \(browserName). Si elle est activée, elle peut défaire la copie. Des sauvegardes sont créées automatiquement avant l'écriture.",
                    "info.circle", .secondary)
        case (.disabled, .mirror):
            return ("Des sauvegardes du fichier Bookmarks (et de la base Favicons, si les icônes sont copiées) seront créées automatiquement avant la copie : tu pourras revenir en arrière depuis l'écran Sauvegardes.",
                    "externaldrive", .secondary)
        case (.unknown, .removal):
            return ("Navloom ne sait pas lire l'état de la synchro de \(browserName). Si elle est activée, elle peut remettre les favoris supprimés. Une sauvegarde du fichier Bookmarks sera créée avant la suppression.",
                    "info.circle", .secondary)
        case (.unknown, .restoration):
            return ("Navloom ne sait pas lire l'état de la synchro de \(browserName). Si elle est activée, elle peut défaire la restauration. L'état actuel est sauvegardé automatiquement avant.",
                    "info.circle", .secondary)
        case (.unknown, .addition):
            return ("Navloom ne sait pas lire l'état de la synchro de \(browserName). Si elle est activée, elle peut défaire l'ajout. Une sauvegarde est créée automatiquement avant l'écriture.",
                    "info.circle", .secondary)
        case (.disabled, .removal):
            return ("Une sauvegarde du fichier Bookmarks sera créée automatiquement avant la suppression.",
                    "externaldrive", .secondary)
        case (.disabled, .restoration):
            return ("L'état actuel est sauvegardé automatiquement avant la restauration.",
                    "externaldrive", .secondary)
        case (.disabled, .addition):
            return ("Une sauvegarde du fichier Bookmarks (et de la base Favicons, si les icônes sont copiées) sera créée automatiquement avant l'ajout.",
                    "externaldrive", .secondary)
        }
    }
}
