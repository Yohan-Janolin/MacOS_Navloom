import Foundation

/// D'où vient un favori : le fichier `Bookmarks` du profil, ou (Chrome connecté à un compte Google)
/// le fichier `AccountBookmarks`, qui contient les favoris enregistrés dans le compte.
nonisolated enum BookmarkSource: Hashable, Sendable {
    case local
    case account
}

/// Un favori "aplati" : on ne garde que ce dont les outils ont besoin.
nonisolated struct Bookmark: Hashable, Sendable {
    let name: String
    let url: String
    /// Chemin du dossier parent, ex. "Barre de favoris / Dev / Outils" (vide si inconnu).
    var folder: String = ""
    /// Identifiant du nœud dans le fichier Bookmarks (sert à retrouver le favori pour le modifier).
    /// Deux fichiers différents peuvent réutiliser le même identifiant : toujours le lire avec `source`.
    var nodeID: String = ""
    /// Les favoris du compte sont en lecture seule : Chrome les remettrait depuis le serveur.
    var source: BookmarkSource = .local
}
