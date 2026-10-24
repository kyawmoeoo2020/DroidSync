import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
                return true
            }
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.clickCount == 2, let window = event.window else {
                return event
            }

            let loc = event.locationInWindow
            let windowHeight = max(window.frame.size.height, window.contentView?.frame.size.height ?? 0)
            let titleBarHeight: CGFloat = 56.0

            if loc.y >= windowHeight - titleBarHeight {
                if let hitView = window.contentView?.hitTest(loc) {
                    var current: NSView? = hitView
                    var isInteractiveControl = false
                    while let v = current {
                        if v is NSControl {
                            isInteractiveControl = true
                            break
                        }
                        current = v.superview
                    }
                    if !isInteractiveControl {
                        window.performZoom(nil)
                        return nil
                    }
                } else {
                    window.performZoom(nil)
                    return nil
                }
            }

            return event
        }
    }
}

@main
struct DroidSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
    }

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
            .version: Self.appVersion,
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
