import SwiftUI

@main
struct KMODroidSyncApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(TitleBarWindowStyle())
        .windowToolbarStyle(UnifiedWindowToolbarStyle())
        .commands {
            SidebarCommands()
        }
    }
}
