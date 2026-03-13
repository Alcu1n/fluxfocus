// [IN]: SwiftUI, SwiftData, AppStore service, and FocusShieldController / SwiftUI、SwiftData、AppStore 服务与 FocusShieldController
// [OUT]: App entry scene with injected model container and shared services / 注入模型容器与共享服务的应用入口场景
// [POS]: Runtime bootstrapper for the full app target / 完整 App target 的运行时启动器
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import SwiftUI
import SwiftData

@main
struct fluxfocusApp: App {
    @State private var appStore = AppStore()
    @StateObject private var focusShieldController = FocusShieldController()
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
                .environmentObject(focusShieldController)
        }
        .modelContainer(container)
    }
}
