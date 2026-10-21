import Foundation

/// Informations affichées dans « À propos ». Version et build viennent du projet Xcode
/// (réglages de la cible : Marketing Version et Build) ; le reste se modifie ici.
enum AppInfo {
    static let authorName = "Yohan Janolin"

    /// Nom du dépôt tel qu'affiché dans « À propos ».
    static let repositoryName = "Yohan-Janolin/MacOS_Navloom"
    static let repositoryURL = URL(string: "https://github.com/Yohan-Janolin/MacOS_Navloom")!
    static let newIssueURL = URL(string: "https://github.com/Yohan-Janolin/MacOS_Navloom/issues/new")!

    /// Date de la version courante : à mettre à jour à chaque release.
    static let releaseDate = DateComponents(calendar: .init(identifier: .gregorian),
                                            year: 2026, month: 10, day: 4).date!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}
