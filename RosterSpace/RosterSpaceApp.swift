//
//  RosterSpaceApp.swift
//  RosterSpace
//
//  Created by mengfs on 10/22/25.
//

import SwiftData
import SwiftUI

@main
struct RosterSpaceApp: App {
    @StateObject private var appViewModel = AppViewModel(dataStore: RosterDataStore())
    @State private var modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Item.self, AIChatRecord.self)
        } catch {
            fatalError("无法创建 SwiftData 容器：\(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
                .environmentObject(appViewModel.dataStore)
                .modelContainer(modelContainer)
        }
    }
}
