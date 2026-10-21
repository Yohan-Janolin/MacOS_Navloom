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
        case "bookmark_bar": root = String(localized: "Bookmarks bar")
        case "other": root = String(localized: "Other bookmarks")
        case "synced": root = String(localized: "Mobile bookmarks")
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
        case .merge: String(localized: "Add the missing bookmarks")
        case .mirror: String(localized: "Full copy (perfect image)")
        }
    }

    /// Libellé court pour le sélecteur segmenté (un libellé long élargirait la fenêtre).
    var shortTitle: String {
        switch self {
        case .merge: String(localized: "Add missing")
        case .mirror: String(localized: "Full copy")
        }
    }

    var hint: String {
        switch self {
        case .merge:
            String(localized: "The target keeps all its bookmarks; only the ones it's missing are added.")
        case .mirror:
            String(localized: "The target becomes identical to the source: folders, order and names. Target bookmarks that aren't in the source are deleted (a backup is made beforehand).")
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
        case .anywhere: String(localized: "URL missing from the target")
        case .sameFolder: String(localized: "URL missing from the same folder")
        }
    }

    var hint: String {
        switch self {
        case .anywhere:
            String(localized: "A bookmark is skipped if its URL already exists anywhere in the target: the safest option, no duplicate is created.")
        case .sameFolder:
            String(localized: "A bookmark is skipped only if its URL already exists in the same folder of the target: if you organize differently, this can create duplicates.")
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
            String(localized: "No bookmarks to add.")
        case .nothingToChange:
            String(localized: "The target is already identical to the source.")
        case .sourceEmpty:
            String(localized: "The source contains no web bookmarks: a full copy would empty the target. Nothing was changed.")
        case .browserRunning(let browser):
            String(localized: "\(browser) is open. Quit it completely (Cmd + Q) before writing to its bookmarks: nothing was changed.")
        case .syncEnabled(let browser):
            String(localized: "Bookmark sync is on in \(browser): it would mix the written bookmarks with those of the account. Nothing was changed.")
        case .destinationChanged:
            String(localized: "The source or target bookmarks changed since the comparison. Run the comparison again: nothing was changed in the Bookmarks file.")
        case .verificationFailed:
            String(localized: "Checking the result failed: nothing was changed.")
        }
    }
}

nonisolated enum EchoError: LocalizedError {
    case invalidFormat
    case noLocalBookmarks(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            String(localized: "The Bookmarks file doesn't have the expected format.")
        case .noLocalBookmarks(let browser):
            String(localized: "This \(browser) profile has no local Bookmarks file (bookmarks saved only in the account?).")
        }
    }
}
