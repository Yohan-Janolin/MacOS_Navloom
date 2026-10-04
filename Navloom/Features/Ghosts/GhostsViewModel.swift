//
//  GhostsViewModel.swift
//  Navloom
//
//  Created by Yohan Janolin on 04/10/2026.
//


import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class GhostsViewModel {

    enum Phase: Equatable {
        case idle, scanning, done
    }

    enum Category: String, CaseIterable, Identifiable {
        case dead = "Morts"
        case uncertain = "À vérifier"
        case moved = "Redirigés"
        var id: String { rawValue }
    }

    struct Row: Identifiable {
        let id = UUID()
        let name: String
        let url: String
        let detail: String
    }

    // MARK: État observé par la vue

    private(set) var hasLoaded = false
    private(set) var browsers: [ChromiumBrowser] = []
    private(set) var profiles: [ChromiumProfile] = []
    var selectedBrowserID: String?
    var selectedProfileID: String?

    private(set) var phase: Phase = .idle
    private(set) var report: GhostsReport?
    private(set) var errorMessage: String?
    private(set) var rows: [Category: [Row]] = [:]
    var selectedCategory: Category = .dead

    private(set) var progressPass = 1
    private(set) var progressDone = 0
    private(set) var progressTotal = 0
    private(set) var currentURL = ""

    var selectedBrowser: ChromiumBrowser? { browsers.first { $0.id == selectedBrowserID } }
    var selectedProfile: ChromiumProfile? { profiles.first { $0.id == selectedProfileID } }
    var isBusy: Bool { phase == .scanning }

    // MARK: Sélection du navigateur et du profil

    func loadBrowsersIfNeeded() {
        guard !hasLoaded else { return }
        browsers = ChromiumBrowser.installed()
        if !browsers.contains(where: { $0.id == selectedBrowserID }) {
            selectedBrowserID = browsers.first(where: { $0.id == "vivaldi" })?.id ?? browsers.first?.id
        }
        browserChanged()
        hasLoaded = true
    }

    func browserChanged() {
        profiles = selectedBrowser?.profiles() ?? []
        if !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profiles.first?.id
        }
        reset()
    }

    func reset() {
        guard !isBusy else { return }
        phase = .idle
        report = nil
        errorMessage = nil
        rows = [:]
    }

    // MARK: Recherche

    func scan() {
        guard let profile = selectedProfile, !isBusy else { return }
        reset()
        progressPass = 1
        progressDone = 0
        progressTotal = 0
        currentURL = ""
        phase = .scanning

        let engine = GhostsEngine(profile: profile)
        let (stream, continuation) = AsyncStream.makeStream(of: GhostsEvent.self)

        Task {
            let listener = Task {
                for await event in stream { handle(event) }
            }
            do {
                let result = try await engine.scan { continuation.yield($0) }
                continuation.finish()
                await listener.value

                report = result
                buildRows(from: result)
                phase = .done
            } catch {
                continuation.finish()
                await listener.value
                errorMessage = error.localizedDescription
                phase = .idle
            }
        }
    }

    private func handle(_ event: GhostsEvent) {
        switch event {
        case .checked(let pass, let done, let total, let url):
            progressPass = pass
            progressDone = done
            progressTotal = total
            currentURL = url
        case .retrying(let count, _):
            progressPass = 2
            progressDone = 0
            progressTotal = count
            currentURL = "Pause avant le second passage…"
        }
    }

    private func buildRows(from report: GhostsReport) {
        func make(_ issues: [BookmarkIssue]) -> [Row] {
            issues.map { Row(name: $0.bookmark.name, url: $0.bookmark.url, detail: $0.reason) }
        }
        rows[.dead] = make(report.dead)
        rows[.uncertain] = make(report.uncertain)
        rows[.moved] = make(report.moved)

        if !report.dead.isEmpty { selectedCategory = .dead }
        else if !report.uncertain.isEmpty { selectedCategory = .uncertain }
        else { selectedCategory = .moved }
    }

    // MARK: Actions sur une ligne

    func open(_ row: Row) {
        guard let url = URL(string: row.url) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL(_ row: Row) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.url, forType: .string)
    }

    // MARK: Export

    func exportReport() {
        guard let report, let profile = selectedProfile else { return }
        let text = report.text(browserName: profile.browserName, profileName: profile.name)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "ghosts-rapport.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Impossible d'écrire le rapport : \(error.localizedDescription)"
        }
    }
}