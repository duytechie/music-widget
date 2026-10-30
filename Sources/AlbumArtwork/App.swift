import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: ArtworkStore!
    private var tile: DesktopTile!
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var visibilityItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var retryItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An accessory app has a menu bar presence without a Dock icon or activation.
        NSApp.setActivationPolicy(.accessory)
        store = ArtworkStore()
        tile = DesktopTile(store: store)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: "Album Artwork")
        statusItem.button?.toolTip = "Album Artwork"
        let menu = NSMenu()
        menu.delegate = self
        let heading = NSMenuItem(title: "Album Artwork", action: nil, keyEquivalent: "")
        menu.addItem(heading)
        statusLine = NSMenuItem(title: store.status, action: nil, keyEquivalent: "")
        menu.addItem(statusLine)
        menu.addItem(.separator())
        visibilityItem = item("Hide Artwork", action: #selector(toggleArtwork), menu: menu)
        item("Reset Position", action: #selector(resetPosition), menu: menu)
        menu.addItem(.separator())
        permissionItem = item("Open Automation Settings…", action: #selector(openPermissionSettings), menu: menu)
        retryItem = item("Retry Music Access", action: #selector(retryMusic), menu: menu)
        menu.addItem(.separator())
        item("Quit Album Artwork", action: #selector(quit), menu: menu, key: "q")
        statusItem.menu = menu
        // Standard context-menu access is useful when menu bar items are crowded.
        tile.window.contentView?.menu = menu
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) { store?.stop() }

    func menuWillOpen(_ menu: NSMenu) {
        statusLine.title = store.status
        visibilityItem.title = tile.isVisible ? "Hide Artwork" : "Show Artwork"
        permissionItem.isHidden = !store.permissionDenied
        retryItem.isHidden = !store.permissionDenied
    }

    @discardableResult
    private func item(_ title: String, action: Selector, menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func toggleArtwork() { tile.toggle() }
    @objc private func resetPosition() { tile.resetPosition() }
    @objc private func retryMusic() { store.retryPermission() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

@main
enum AlbumArtworkApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
