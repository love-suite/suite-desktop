import AppKit
import DesktopSettings
import FinderGuard
import SuiteCore

// The display settings Desktop shares with Explorer's windows are in Explorer's defaults.
SuiteDefaults.useExplorerDomain()

// Escape hatch if Desktop was force-killed or crashed while Finder's desktop was hidden: Finder's desktop
// back as the user had it.
if CommandLine.arguments.contains("--restore-finder") {
    FinderManager(memory: DesktopSettings.defaults).restore()
    GuardAgent.update()
    exit(0)
}

// Reopened by the previous copy (an update, --relaunch): once it is gone, this copy carries on.
_ = AppRelauncher.waitForPreviousCopy()

// One desktop at a time: a second copy leaves at once. Started with `--relaunch` (make-app.sh after a
// build), it asks the running copy to reopen itself, as for an update.
let me = ProcessInfo.processInfo.processIdentifier
let previous = AppRelauncher.previousCopy
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
       .contains(where: { $0.processIdentifier != me && $0.processIdentifier != previous && !$0.isTerminated }) {
    if CommandLine.arguments.contains("--relaunch") {
        DesktopMessage.relaunch.post()
        // Long enough for the message to leave before this copy does.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    exit(0)
}

let app = NSApplication.shared
// An ordinary app, as Finder: see AppDelegate.updateActivationPolicy().
app.setActivationPolicy(.regular)
app.mainMenu = DesktopMenu.make()
let delegate = AppDelegate()
app.delegate = delegate
app.run()
