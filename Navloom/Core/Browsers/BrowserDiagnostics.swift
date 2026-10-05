//
//  BrowserDiagnostics.swift
//  Navloom
//
//  Created by Yohan Janolin on 05/10/2026.
//


#if DEBUG
import Foundation

/// Diagnostic TEMPORAIRE (build Debug uniquement, absent des versions finales) :
/// explique pourquoi un navigateur n'apparaît pas dans la liste. Ne lit que des noms de dossiers et des codes d'erreur.
nonisolated enum BrowserDiagnostics {

    /// Affiche le rapport une seule fois par lancement, dans la console d'Xcode.
    static let printOnce: Void = {
        print(report())
    }()

    static func report() -> String {
        let fm = FileManager.default
        var lines = [
            "[Navloom diag] macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "[Navloom diag] Application Support = \(URL.applicationSupportDirectory.path)",
        ]

        for browser in ChromiumBrowser.known {
            let root = URL.applicationSupportDirectory.appending(path: browser.supportFolder)
            let exists = fm.fileExists(atPath: root.path)
            let header = "[Navloom diag] \(browser.name) : dossier \(exists ? "présent" : "absent")"
            guard exists else {
                lines.append(header)
                continue
            }

            let names: [String]
            do {
                names = try fm.contentsOfDirectory(atPath: root.path)
            } catch {
                lines.append("\(header), liste ÉCHEC : \(describe(error))")
                continue
            }

            let profiles = names.filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted()
            let profileText = profiles.isEmpty ? "aucun" : profiles.joined(separator: ", ")
            lines.append("\(header), liste OK (\(names.count) éléments, profils : \(profileText))")

            for profile in profiles {
                for file in ["Bookmarks", "AccountBookmarks"] {
                    let url = root.appending(path: profile).appending(path: file)
                    let present = fm.fileExists(atPath: url.path)
                    var detail = "[Navloom diag]     \(profile)/\(file) : fileExists=\(present)"
                    if present {
                        do {
                            _ = try Data(contentsOf: url)
                            detail += ", lecture OK"
                        } catch {
                            detail += ", lecture ÉCHEC : \(describe(error))"
                        }
                    }
                    lines.append(detail)
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var text = "\(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)"
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " (sous-jacent : \(underlying.domain) \(underlying.code))"
        }
        return text
    }
}
#endif