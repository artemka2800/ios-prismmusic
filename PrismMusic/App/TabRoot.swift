//
//  TabRoot.swift
//  PrismMusic
//
//  Bottom tab navigation: Home / Search / Library / Settings.
//  Uses SwiftUI's `TabView` with `.sidebarAdaptable` style so it'll do the
//  right thing on iPad too.
//

import SwiftUI

struct TabRoot: View {
    @State private var selection: Tab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Главная", systemImage: "house.fill") }
                .tag(Tab.home)
            SearchView()
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                .tag(Tab.search)
            LibraryView()
                .tabItem { Label("Медиатека", systemImage: "rectangle.stack.fill") }
                .tag(Tab.library)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .tint(.white)
    }

    enum Tab: Hashable { case home, search, library, settings }
}
