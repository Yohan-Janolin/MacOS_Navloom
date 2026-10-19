import Foundation

/// Un dossier de favoris, identifié par sa racine et son chemin (sans le nom de la racine).
/// On compare par la clé de racine (« bookmark_bar »…) et non par son nom, qui change d'un navigateur à l'autre.
nonisolated struct EchoFolder: Hashable, Sendable {
    let rootKey: String
    let path: [String]
}

/// Un favori tel qu'Echo le compare.
nonisolated struct EchoBookmark: Hashable, Sendable {
    let rootKey: String
    /// Dossiers traversés sous la racine (vide = directement à la racine).
    let folderPath: [String]
    let name: String
    let url: String

    /// Emplacement lisible : « Barre de favoris / Dev ».
    var locationLabel: String {
        let root: String
        switch rootKey {
        case "bookmark_bar": root = "Barre de favoris"
        case "other": root = "Autres favoris"
        case "synced": root = "Favoris mobiles"
        default: root = rootKey
        }
        return ([root] + folderPath).joined(separator: " / ")
    }
}

/// Le contenu comparable d'un fichier Bookmarks.
nonisolated struct EchoSnapshot: Sendable {
    let bookmarks: [EchoBookmark]
    let folders: Set<EchoFolder>
    /// Favoris non web (vivaldi://, opera://, file://…) : on ne les copie pas d'un navigateur à l'autre.
    let ignoredCount: Int
    /// Racines présentes dans le fichier (une racine absente de la cible reçoit ses favoris dans « Autres favoris »).
    var rootKeys: Set<String> = ["bookmark_bar", "other", "synced"]
    /// Dossiers et favoris web dans l'ordre de l'arbre : sert à savoir si deux profils sont déjà identiques.
    var layout: [String] = []
}

/// Fusion (on ajoute ce qui manque, on ne supprime rien) ou copie complète (la cible devient la copie de la source).
nonisolated enum EchoSyncMode: String, CaseIterable, Identifiable, Sendable {
    case merge
    case mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: "Ajouter les favoris manquants"
        case .mirror: "Copie complète (image parfaite)"
        }
    }

    /// Libellé court pour le sélecteur segmenté (un libellé long élargirait la fenêtre).
    var shortTitle: String {
        switch self {
        case .merge: "Ajouter les manquants"
        case .mirror: "Copie complète"
        }
    }

    var hint: String {
        switch self {
        case .merge:
            "La cible garde tous ses favoris ; seuls ceux qui lui manquent sont ajoutés."
        case .mirror:
            "La cible devient identique à la source : dossiers, ordre et noms. Les favoris de la cible qui ne sont pas dans la source sont supprimés (une sauvegarde est faite avant)."
        }
    }
}

/// Comment décider qu'un favori de la source est déjà présent dans la destination.
nonisolated enum EchoMatchMode: String, CaseIterable, Identifiable, Sendable {
    case anywhere
    case sameFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anywhere: "URL absente de la cible"
        case .sameFolder: "URL absente du même dossier"
        }
    }

    var hint: String {
        switch self {
        case .anywhere:
            "Un favori est ignoré si son URL existe déjà n'importe où dans la cible : c'est le plus prudent, aucun doublon n'est créé."
        case .sameFolder:
            "Un favori est ignoré seulement si son URL existe déjà dans le même dossier de la cible : si tu ranges autrement, cela peut créer des doublons."
        }
    }
}

/// Variantes d'URL à considérer comme identiques. Le « / » final et la casse du nom de domaine sont
/// toujours ignorés ; le reste est à activer au cas par cas, car deux URL qui n'en diffèrent que par là
/// peuvent désigner des pages différentes.
nonisolated struct EchoURLOptions: Hashable, Sendable {
    /// http://a.fr et https://a.fr
    var ignoreScheme = false
    /// www.a.fr et a.fr
    var ignoreWWW = false
    /// a.fr/page?x=1 et a.fr/page (attention : la page d'une vidéo, d'un article… tient parfois à son paramètre)
    var ignoreQuery = false
}

/// Ce qu'une fusion ajouterait à la destination.
nonisolated struct EchoPlan: Sendable {
    let toAdd: [EchoBookmark]
    /// Favoris de la source déjà présents dans la destination.
    let alreadyPresent: Int
    /// Favoris de la source qui en répètent un autre (une seule copie est ajoutée).
    let skippedSourceDuplicates: Int
    /// Dossiers qu'il faudrait créer dans la destination.
    let newFolders: Int
}

/// Ce qu'une copie complète changerait dans la cible. Les favoris sont comparés tels quels
/// (racine, dossiers, nom, URL exacte) : une copie parfaite ne tolère aucune variante.
nonisolated struct EchoMirrorPlan: Sendable, Equatable {
    /// Favoris de la source qui manquent dans la cible.
    let toAdd: [EchoBookmark]
    /// Favoris web de la cible qui ne sont pas dans la source : ils seront supprimés.
    let toRemove: [EchoBookmark]
    /// Favoris non web de la cible (opera://…) : supprimés aussi, car la source n'en copie aucun.
    let nonWebToRemove: Int
    let unchanged: Int
    let foldersToAdd: Int
    let foldersToRemove: Int
    /// Tous les favoris web de la source (ceux de la cible après la copie) : pour les icônes et la vérification.
    let expected: [EchoBookmark]
    /// La cible a déjà exactement la structure de la source.
    let isIdentical: Bool

    var removalCount: Int { toRemove.count + nonWebToRemove }
}

nonisolated struct EchoReport: Sendable {
    let source: ChromiumProfile
    let destination: ChromiumProfile
    let sourceCount: Int
    let ignoredCount: Int
    let plan: EchoPlan
    let mirror: EchoMirrorPlan
}

/// Ce qu'une écriture a fait dans la destination.
nonisolated struct EchoApplySummary: Sendable {
    let mode: EchoSyncMode
    let added: Int
    let createdFolders: Int
    /// Copie complète : favoris (web ou non) et dossiers supprimés de la cible.
    let removed: Int
    let removedFolders: Int
    /// Favoris ajoutés qui ont maintenant leur icône.
    let faviconsCopied: Int
    /// Favoris ajoutés dont la source n'avait pas d'icône (FaviconSync pourra les chercher).
    let faviconsMissing: Int
    /// Icônes trouvées dans la source mais qui n'ont pas pu être écrites.
    let faviconsFailed: Int
    let bookmarksBackupURL: URL
    let faviconsBackupURL: URL?
    /// Explication quand les icônes n'ont pas été (toutes) copiées ; les favoris, eux, sont bien ajoutés.
    let faviconNote: String?
}

nonisolated enum EchoWriteError: LocalizedError {
    case nothingToAdd
    case nothingToChange
    case sourceEmpty
    case browserRunning(String)
    case syncEnabled(String)
    case destinationChanged
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .nothingToAdd:
            "Aucun favori à ajouter."
        case .nothingToChange:
            "La cible est déjà identique à la source."
        case .sourceEmpty:
            "La source ne contient aucun favori web : une copie complète viderait la cible. Rien n'a été modifié."
        case .browserRunning(let browser):
            "\(browser) est ouvert. Ferme-le complètement (Cmd + Q) avant d'écrire dans ses favoris : rien n'a été modifié."
        case .syncEnabled(let browser):
            "La synchro des favoris est activée dans \(browser) : elle mélangerait les favoris écrits avec ceux du compte. Rien n'a été modifié."
        case .destinationChanged:
            "Les favoris de la source ou de la cible ont changé depuis la comparaison. Relance la comparaison : rien n'a été modifié dans le fichier Bookmarks."
        case .verificationFailed:
            "La vérification du résultat a échoué : rien n'a été modifié."
        }
    }
}

nonisolated enum EchoError: LocalizedError {
    case invalidFormat
    case noLocalBookmarks(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            "Le fichier Bookmarks n'a pas le format attendu."
        case .noLocalBookmarks(let browser):
            "Ce profil de \(browser) n'a pas de fichier Bookmarks local (favoris enregistrés uniquement dans le compte ?)."
        }
    }
}
