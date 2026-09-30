//
//  MainView.swift
//  Navloom
//
//  Created by Yohan Janolin on 29/09/2026.
//


import SwiftUI

struct MainView: View {
    @State private var selection: Feature? = .faviconSync

    var body: some View {
        NavigationSplitView {
            List(Feature.allCases, selection: $selection) { feature in
                Label(feature.title, systemImage: feature.systemImage)
                    .tag(feature)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            switch selection {
            case .faviconSync:
                FaviconSyncView()
            case nil:
                ContentUnavailableView("Choisis un outil", systemImage: "sidebar.left")
            }
        }
        .frame(minWidth: 720, minHeight: 460)
    }
}

#Preview {
    MainView()
}