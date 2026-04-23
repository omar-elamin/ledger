import SwiftUI
import SwiftData

@main
struct LedgerApp: App {
    private let appEnvironment: LedgerAppEnvironment

    init() {
        let appEnvironment = LedgerAppEnvironment.bootstrap()
        if appEnvironment.shouldRegisterBackgroundTasks {
            appEnvironment.memoryMaintenanceScheduler.registerBackgroundTasks()
        }
        self.appEnvironment = appEnvironment
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appEnvironment: appEnvironment)
        }
        .modelContainer(appEnvironment.modelContainer)
    }
}
