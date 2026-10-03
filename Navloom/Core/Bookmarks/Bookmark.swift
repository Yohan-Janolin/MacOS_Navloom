import Foundation

/// Un favori "aplati" : on ne garde que ce dont les outils ont besoin.
nonisolated struct Bookmark: Hashable, Sendable {
    let name: String
    let url: String
    /// Chemin du dossier parent, ex. "Barre de favoris / Dev / Outils" (vide si inconnu).
    var folder: String = ""
    /// Identifiant du nœud dans le fichier Bookmarks (sert à retrouver le favori pour le modifier).
    var nodeID: String = ""
}
