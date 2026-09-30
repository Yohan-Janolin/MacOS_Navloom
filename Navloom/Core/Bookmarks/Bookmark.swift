//
//  Bookmark.swift
//  Navloom
//
//  Created by Yohan Janolin on 29/09/2026.
//


import Foundation

/// Un favori "aplati" : on ne garde que ce dont le moteur a besoin.
nonisolated struct Bookmark: Hashable, Sendable {
    let name: String
    let url: String
}