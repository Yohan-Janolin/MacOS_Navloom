//
//  DiskAccessTests.swift
//  Navloom
//
//  Created by Yohan Janolin on 06/10/2026.
//


//
//  DiskAccessTests.swift
//  NavloomTests
//

import Testing
import Foundation
@testable import Navloom

/// Aucun de ces tests ne touche aux vrais dossiers des navigateurs : tout se passe dans des
/// dossiers temporaires, pour rester rapide et indépendant des autorisations de macOS.
struct DiskAccessTests {

    // MARK: Reconnaissance d'un refus de permission

    @Test func unRefusDePermissionEstReconnu() {
        #expect(DiskAccess.isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))))
        #expect(DiskAccess.isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
        #expect(DiskAccess.isPermissionDenied(CocoaError(.fileReadNoPermission)))
    }

    @Test func lErreurObserveeSurMacOS27EstReconnue() {
        // Relevé réel : NSCocoaErrorDomain 257, avec NSPOSIXErrorDomain 1 en erreur sous-jacente.
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: 1)
        let error = NSError(domain: NSCocoaErrorDomain, code: 257,
                            userInfo: [NSUnderlyingErrorKey: underlying])
        #expect(DiskAccess.isPermissionDenied(error))
    }

    @Test func uneErreurSousJacenteDePermissionSuffit() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        let error = NSError(domain: "AutreDomaine", code: 42, userInfo: [NSUnderlyingErrorKey: underlying])
        #expect(DiskAccess.isPermissionDenied(error))
    }

    @Test func lesAutresErreursNeSontPasDesRefus() {
        #expect(!DiskAccess.isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))))
        #expect(!DiskAccess.isPermissionDenied(CocoaError(.fileReadNoSuchFile)))
        #expect(!DiskAccess.isPermissionDenied(NSError(domain: "AutreDomaine", code: 1)))
    }

    // MARK: Dossier bloqué ou non

    private func makeTemporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func unDossierLisibleNEstPasBloque() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(!DiskAccess.isBlocked(folder: folder))
    }

    @Test func unDossierAbsentNEstPasBloque() {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(!DiskAccess.isBlocked(folder: folder))
    }

    // Un administrateur (root) lit tout : le test n'a de sens que pour un utilisateur ordinaire.
    @Test(.enabled(if: getuid() != 0))
    func unDossierSansDroitDeLectureEstBloque() throws {
        let fm = FileManager.default
        let folder = try makeTemporaryFolder()
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer {
            // Les droits sont rétablis avant de supprimer, sinon le dossier temporaire resterait.
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? fm.removeItem(at: folder)
        }

        #expect(DiskAccess.isBlocked(folder: folder))
    }

    // MARK: Texte du bandeau

    @Test func laListeDeNomsSeFormuleEnFrancais() {
        let fr = Locale(identifier: "fr_FR")
        #expect(DiskAccess.joinedNames([], locale: fr) == "")
        #expect(DiskAccess.joinedNames(["Chrome"], locale: fr) == "Chrome")
        #expect(DiskAccess.joinedNames(["Chrome", "Brave"], locale: fr) == "Chrome et Brave")
        #expect(DiskAccess.joinedNames(["Chrome", "Brave", "Edge"], locale: fr) == "Chrome, Brave et Edge")
        let en = Locale(identifier: "en_US")
        #expect(DiskAccess.joinedNames(["Chrome", "Brave", "Edge"], locale: en) == "Chrome, Brave, and Edge")
    }
}