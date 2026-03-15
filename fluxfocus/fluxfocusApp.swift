// [IN]: SwiftUI, SwiftData, AppStore service, and FocusShieldController / SwiftUI、SwiftData、AppStore 服务与 FocusShieldController
// [OUT]: App entry scene with injected model container, resilient store recovery, shared services, and a test-safe bootstrap branch / 注入模型容器、弹性 store 恢复、共享服务与测试安全启动分支的应用入口场景
// [POS]: Runtime bootstrapper for the full app target that can quarantine incompatible SwiftData stores before relaunching cleanly / 完整 App target 的运行时启动器，并能在重新启动前隔离不兼容的 SwiftData store
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import SwiftUI
import SwiftData

@main
struct fluxfocusApp: App {
    @State private var appStore = AppStore()
    @StateObject private var focusShieldController: FocusShieldController
    private let isRunningTests: Bool
    private let container: ModelContainer

    init() {
        let isRunningTests = Self.isRunningTests
        self.isRunningTests = isRunningTests
        _focusShieldController = StateObject(wrappedValue: FocusShieldController(testing: isRunningTests))
        container = isRunningTests ? Self.makeTestingContainer() : Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                Color.clear
            } else {
                ContentView()
                    .environment(appStore)
                    .environmentObject(focusShieldController)
            }
        }
        .modelContainer(container)
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func makeContainer() -> ModelContainer {
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

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            let backupURL = quarantineStore(
                at: storeURL,
                fileManager: fileManager,
                rootDirectory: storeDirectory
            )

            NSLog(
                "FluxFocus: failed to load SwiftData store at %@. Backed up incompatible store to %@ and will recreate a fresh container. Error: %@",
                storeURL.path,
                backupURL?.path ?? "<backup failed>",
                String(describing: error)
            )

            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Failed to recreate SwiftData container after quarantining incompatible store: \(error)")
            }
        }
    }

    private static func makeTestingContainer() -> ModelContainer {
        let schema = Schema([AppConfiguration.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }

    @discardableResult
    private static func quarantineStore(
        at storeURL: URL,
        fileManager: FileManager,
        rootDirectory: URL
    ) -> URL? {
        let existingURLs = storeArtifactURLs(for: storeURL, fileManager: fileManager)
        guard existingURLs.isEmpty == false else { return nil }

        let backupsDirectory = rootDirectory.appendingPathComponent("StoreBackups", isDirectory: true)
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backupDirectory = backupsDirectory.appendingPathComponent(timestamp, isDirectory: true)
        try? fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        for sourceURL in existingURLs {
            let destinationURL = backupDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                try? fileManager.removeItem(at: sourceURL)
            }
        }

        return backupDirectory
    }

    private static func storeArtifactURLs(
        for storeURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        let candidatePaths = [
            storeURL.path,
            "\(storeURL.path)-shm",
            "\(storeURL.path)-wal",
            "\(storeURL.path)-journal"
        ]

        return candidatePaths
            .map { URL(fileURLWithPath: $0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }
}
