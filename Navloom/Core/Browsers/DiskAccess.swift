import Foundation

/// Accès aux données des navigateurs : sous macOS 27, Chrome, Edge et Brave (versions stables)
/// refusent la lecture de leur dossier à une app qui n'a pas l'« Accès complet au disque ».
/// Dans ce cas le dossier existe, mais on ne peut pas le lister (erreur « Operation not permitted »).
nonisolated enum DiskAccess {

    /// Navigateurs dont macOS interdit la lecture au lancement de l'app. Calculé une seule fois :
    /// une autorisation accordée ensuite ne s'applique qu'après un redémarrage de l'app.
    static let blockedBrowsersAtLaunch: [ChromiumBrowser] = ChromiumBrowser.blockedByMacOS()

    /// Vrai si l'erreur est un refus de permission (protection de macOS ou droits Unix).
    static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError

        switch nsError.domain {
        case NSPOSIXErrorDomain:
            if nsError.code == Int(EPERM) || nsError.code == Int(EACCES) { return true }
        case NSCocoaErrorDomain:
            if nsError.code == CocoaError.fileReadNoPermission.rawValue { return true }
        default:
            break
        }

        // L'erreur de Foundation enveloppe souvent l'erreur POSIX d'origine.
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionDenied(underlying)
        }
        return false
    }

    /// Vrai si le dossier existe mais qu'on n'a pas le droit d'en lister le contenu.
    /// Un dossier absent, ou lisible, n'est pas « bloqué ».
    static func isBlocked(folder: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return false }
        do {
            _ = try fm.contentsOfDirectory(atPath: folder.path)
            return false
        } catch {
            return isPermissionDenied(error)
        }
    }

    /// « Chrome », « Chrome et Brave », « Chrome, Brave et Edge ».
    static func joinedNames(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " et " + last
    }
}

extension ChromiumBrowser {

    /// Dossier de données du navigateur, dans ~/Library/Application Support.
    nonisolated var dataFolder: URL {
        URL.applicationSupportDirectory.appending(path: supportFolder)
    }

    /// Vrai si le dossier de données existe mais que macOS en interdit la lecture à Navloom.
    nonisolated var isBlockedByMacOS: Bool {
        DiskAccess.isBlocked(folder: dataFolder)
    }

    /// Navigateurs connus dont macOS interdit la lecture.
    nonisolated static func blockedByMacOS() -> [ChromiumBrowser] {
        known.filter { $0.isBlockedByMacOS }
    }
}
