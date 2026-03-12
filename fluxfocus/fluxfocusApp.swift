//
//  fluxfocusApp.swift
//  fluxfocus
//
//  Created by 张慕坤 on 2026/3/12.
//

import SwiftUI
import SwiftData

@main
struct fluxfocusApp: App {
    @State private var appStore = AppStore()
    private let container: ModelContainer = {
        let schema = Schema([
            Tag.self,
            FocusSession.self,
            Appointment.self,
            ChainNode.self,
            ViolationEvent.self,
            PrecedentRule.self,
            ShieldPolicy.self,
            AppConfiguration.self
        ])

        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDirectory = supportDirectory.appendingPathComponent("FluxFocus", isDirectory: true)
        try? fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let storeURL = storeDirectory.appendingPathComponent("default.store")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appStore)
        }
        .modelContainer(container)
    }
}
