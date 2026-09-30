//
//  Feature.swift
//  Navloom
//
//  Created by Yohan Janolin on 29/09/2026.
//


import Foundation

/// Une fonctionnalité de Navloom, affichée dans la barre latérale.
/// Ajouter un outil = ajouter un case ici + une vue dans Features/.
enum Feature: String, CaseIterable, Identifiable {
    case faviconSync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faviconSync: "FaviconSync"
        }
    }

    /// Nom d'un symbole SF Symbols (l'icône système d'Apple)
    var systemImage: String {
        switch self {
        case .faviconSync: "star.square"
        }
    }
}