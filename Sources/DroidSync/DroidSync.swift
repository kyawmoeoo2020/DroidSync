import SwiftUI
import AppKit

@main
struct DroidSyncApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        // In bundled apps, macOS loads CFBundleIconFile from Info.plist natively.
        // For unbundled development runs, set applicationIconImage as fallback.
        if Bundle.main.infoDictionary?["CFBundleIconFile"] == nil {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ??
                         Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = icon
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(TitleBarWindowStyle())
        .windowToolbarStyle(UnifiedWindowToolbarStyle())
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About DroidSync") {
                    showAboutPanel()
                }
            }
        }
    }

    private func showAboutPanel() {
        let appDockIcon: NSImage? = {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ??
                         Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
               let img = NSImage(contentsOf: url) {
                return img
            }
            return NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage
        }()

        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "DroidSync",
            .version: "1.0.0",
            .credits: NSAttributedString(
                string: "Developed by Kyaw Moe Oo\n\nHigh-performance native Android sync tool for macOS",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
        ]
        if let icon = appDockIcon {
            options[.applicationIcon] = icon
        }

        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }
}
