//
//  RosterSpaceApp.swift
//  RosterSpace
//
//  Created by mengfs on 10/22/25.
//

import SwiftUI

@main
struct RosterSpaceApp: App {
    @StateObject private var appViewModel = AppViewModel(dataStore: RosterDataStore())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
                .environmentObject(appViewModel.dataStore)
        }
    }
}
