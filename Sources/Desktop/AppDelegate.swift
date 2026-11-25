import AppKit
import DesktopCore
import DesktopSettings
import FinderGuard
import ServiceManagement
import SuiteCore
import SuiteFilesCore
import SuiteFilesUI

/// Desktop: our desktop in place of Finder's while it runs. At launch it hides Finder's desktop (Finder keeps
/// its windows), loads Suite Guard, which puts Finder's desktop back should Desktop vanish, and shows the
/// desktop window; quitting puts Finder's desktop back as the user had it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktopWindow: DesktopWindow?
    private var signalSources: [DispatchSourceSignal] = []
    private let finder = FinderManager()
    /// Desktop keeps itself up to date from its own releases, without asking: the desktop comes back by
    /// itself within a second.
    private let updater = SuiteUpdater(appName: "Desktop", isBusy: { false })

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileRoles.useHolders()
        // One Undo history with Explorer's windows and the other apps: theirs changes show in our menus.
        FileUndo.recordTrashingInOtherApps()
        restoreFinderOnSignals()
        FirstLaunch.startFromFinder()
        FinderSync.shared.start()
        finder.hide()
        GuardAgent.update()
        if let screen = NSScreen.main {
            desktopWindow = DesktopWindow(screen: screen)
            desktopWindow?.orderFront(nil)
        }
        listenToSettings()
        LoginItem.registerOnce()
        updater.start()

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
            [weak self] _ in self?.updateActivationPolicy()
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) {
            [weak self] _ in self?.updateActivationPolicy()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            EmptySpace.takeIfEmpty()
        }
        // An app quitting with its last window (System Settings, for instance) makes macOS pick another app
        // in front, and switch to a Space where it has windows. With Finder's desktop, Finder is picked
        // and nothing moves; Bureau takes its place at once.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { _ in
            EmptySpace.takeIfEmpty()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Reopening itself (an update, --relaunch), the new copy takes over at once: Finder's desktop
        // stays hidden, Finder isn't restarted twice.
        guard !AppRelauncher.isRelaunching else { return }
        FinderSync.shared.finderWillRestart()
        finder.restore()
        GuardAgent.update()
    }

    /// Ctrl+C, closing the terminal or `kill` would otherwise leave the user without Finder's desktop.
    private func restoreFinderOnSignals() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Suite Settings or a profile wrote the desktop's settings (Desktop's defaults) or the display settings
    /// it shares with Explorer's windows (Explorer's defaults).
    private func listenToSettings() {
        DesktopMessage.applySettings.observe { _ in DesktopSettings.reloadFromDefaults() }
        DesktopMessage.relaunch.observe { _ in AppRelauncher.relaunch() }
        DistributedNotificationCenter.default().addObserver(
            forName: ExplorerLink.commandNotification, object: nil, queue: .main) { note in
            guard (note.object as? String) == ExplorerLink.Command.applySettings.rawValue else { return }
            CFPreferencesAppSynchronize(SuiteDefaults.explorerDomain as CFString)
            NotificationCenter.default.post(name: DisplaySettings.didChange, object: nil)
        }
    }

    // MARK: Dock icon and menu bar

    /// Bureau is an ordinary app, always, as Finder is: macOS then picks it, as it picks Finder, when an
    /// app quits with its last window on a Space Bureau's window covers, instead of switching to another
    /// Space. Being one, it also has the menu bar when the desktop is clicked.
    private func updateActivationPolicy() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }
}

/// Where folders open and items are shown from the desktop: Explorer while it manages files (it is
/// installed and its Explorer/Finder switch is on Explorer), Finder otherwise.
enum FileRoles {
    static var explorerManagesFiles: Bool {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: SuiteDefaults.explorerDomain) != nil
        else { return false }
        CFPreferencesAppSynchronize(SuiteDefaults.explorerDomain as CFString)
        // Explorer writes its switch once it is turned; until then Explorer manages files.
        return SuiteDefaults.explorer.object(forKey: "UseExplorer") as? Bool ?? true
    }

    static func useHolders() {
        FileViewer.openFolder = { url in
            if explorerManagesFiles { ExplorerLink.open([url]) } else { NSWorkspace.shared.open(url) }
        }
        FileViewer.reveal = { urls in
            if explorerManagesFiles { ExplorerLink.reveal(urls) } else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
    }
}

/// Desktop starts at login, as Finder's desktop is there at login: registered once, at the first launch;
/// the user can turn it off in System Settings › General › Login Items.
enum LoginItem {
    private static let offeredKey = "LoginItemRegistered"

    static func registerOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: offeredKey) else { return }
        defaults.set(true, forKey: offeredKey)
        try? SMAppService.mainApp.register()
    }
}

/// Arriving on a Space with no window of its own, macOS makes another app active, one whose windows are on
/// another Space, then switches back there ("When switching to an application, switch to a Space with open
/// windows for the application", on by default): changing Space twice quickly lands back where you were.
/// With Finder's desktop, Finder takes the empty Space; with ours hidden, Desktop takes it, as Finder would.
enum EmptySpace {
    static func takeIfEmpty() {
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        let me = ProcessInfo.processInfo.processIdentifier
        let others = windows.contains { window in
            (window[kCGWindowLayer as String] as? Int ?? 0) == 0
                && (window[kCGWindowOwnerPID as String] as? Int32 ?? me) != me
                && (window[kCGWindowAlpha as String] as? Double ?? 1) > 0
        }
        guard !others else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The first launch shows Finder's desktop as the user set it up (its View Options for the desktop, its
/// icons where Finder placed them), before anything is changed in Suite Settings.
enum FirstLaunch {
    static func startFromFinder() {
        guard !DesktopSettings.isSaved else { return }
        // Finder's positions are from the top of the screen; Bureau's from below the menu bar.
        let topInset = NSScreen.main.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 25
        let finder = FinderDesktop.onThisMac(topInset: topInset)
        DesktopSettings.current = finder.settings
        let desktopFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        var options = FolderViewStore.shared.options(for: desktopFolder)
        options.sortKey = finder.sortKey
        options.ascending = finder.ascending
        FolderViewStore.shared.save(options, for: desktopFolder)
    }
}
