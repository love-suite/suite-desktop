import AppKit
import DesktopCore
import DesktopSettings
import SuiteFilesCore

/// Bureau's settings and Finder's desktop settings kept as one, both ways, while Bureau runs: a change in
/// Suite Settings reaches Finder (as the closest value Finder accepts), a change in Finder reaches Bureau.
/// Finder reads them when its desktop comes back, which Bureau does by restarting Finder as it quits: no
/// other restart is needed. Bureau keeps a timestamped copy of what it wrote (`FinderSyncRecord`), so an old
/// value a running Finder writes back from memory is put right again instead of being taken as the user's.
@MainActor
final class FinderSync {
    static let shared = FinderSync()

    private static let finderDomain = "com.apple.finder" as CFString
    private static let viewKey = "DesktopViewSettings" as CFString
    private static let recordKey = "FinderSyncRecord"
    private static let restartedKey = "FinderRestartedByDesktop"

    private var watcher: DirectoryWatcher?
    private var pending: DispatchWorkItem?
    /// Set while Bureau takes Finder's values, so taking them isn't written back.
    private var adopting = false

    private var desktopFolder: URL { FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0] }

    func start() {
        if record == nil {
            // First sync on this Mac: a field where Finder's value brings Bureau to what it has (Bureau's first
            // launch took it from Finder, or Finder can't do closer) is in sync; any other field Bureau has
            // goes to Finder.
            let finder = readFinder()
            let suite = suiteView()
            let options = FolderViewStore.shared.options(for: desktopFolder)
            var inSync = finder
            for field in FinderDesktopView.Field.allCases {
                var settings = DesktopSettings.current
                let sort = finder.adopt([field], into: &settings)
                let back = FinderDesktopView(approximating: settings, sortKey: sort?.key ?? options.sortKey,
                                             ascending: sort?.ascending ?? options.ascending)
                if back.value(field) == suite.value(field) { inSync.take(field, from: suite) }
            }
            record = FinderSyncRecord(finder: finder, before: finder, suite: inSync, written: .distantPast)
        }
        readFinderChanges()
        suiteChanged()

        let center = NotificationCenter.default
        for name in [DesktopSettings.didChange, FolderViewStore.didChange] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { FinderSync.shared.suiteChanged() }
            }
        }
        let preferences = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences")
        watcher = DirectoryWatcher(url: preferences) {
            DispatchQueue.main.async { MainActor.assumeIsolated { FinderSync.shared.scheduleRead() } }
        }
        watcher?.start()
    }

    /// Bureau is about to restart Finder to give its desktop back: the Finder that quits may write what it
    /// held in memory.
    func finderWillRestart() {
        UserDefaults.standard.set(Date(), forKey: Self.restartedKey)
    }

    // MARK: Both ways

    /// Preferences change often, for every app: Finder's are read once things settle.
    private func scheduleRead() {
        pending?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { FinderSync.shared.readFinderChanges() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func readFinderChanges() {
        guard var record else { return }
        let finder = readFinder()
        guard finder != record.finder else { return }
        let reading = FinderDesktopSync.read(
            finder, record: record,
            finderLaunched: Self.finderLaunched(),
            finderRestarted: UserDefaults.standard.object(forKey: Self.restartedKey) as? Date)

        if !reading.changedInFinder.isEmpty {
            adopting = true
            var settings = DesktopSettings.current
            if let sort = reading.finder.adopt(reading.changedInFinder, into: &settings) {
                var options = FolderViewStore.shared.options(for: desktopFolder)
                options.sortKey = sort.key
                options.ascending = sort.ascending
                FolderViewStore.shared.save(options, for: desktopFolder)
            }
            DesktopSettings.current = settings
            adopting = false
            // The running Finder now holds these values.
            for field in reading.changedInFinder { record.before.take(field, from: finder) }
        }
        if !reading.putBack.isEmpty {
            writeFinder(reading.finder, fields: reading.putBack)
        }
        record.finder = reading.finder
        record.suite = suiteView()
        self.record = record
    }

    private func suiteChanged() {
        guard !adopting, var record else { return }
        let suite = suiteView()
        let finder = readFinder()
        let change = FinderDesktopSync.write(suite, record: record, finder: finder)
        if !change.fields.isEmpty {
            writeFinder(change.finder, fields: change.fields)
            record.before = finder
            record.finder = change.finder
            record.written = Date()
        }
        record.suite = suite
        self.record = record
    }

    private func suiteView() -> FinderDesktopView {
        let options = FolderViewStore.shared.options(for: desktopFolder)
        return FinderDesktopView(approximating: DesktopSettings.current, sortKey: options.sortKey,
                                 ascending: options.ascending)
    }

    /// When the running Finder started. launchd starts Finder, so `NSRunningApplication.launchDate` is
    /// nil: the process's own start time is read instead.
    private static func finderLaunched() -> Date? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first?.processIdentifier else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    // MARK: Finder's settings and the record

    private func readFinder() -> FinderDesktopView {
        CFPreferencesAppSynchronize(Self.finderDomain)
        return FinderDesktopView(finder: CFPreferencesCopyAppValue(Self.viewKey, Self.finderDomain) as? [String: Any],
                                 items: FinderDesktop.finderItems())
    }

    /// Writes the View Options when one of them is among `fields`, and the `Show*OnDesktop` keys among them
    /// (only those: a key Finder never wrote keeps meaning its default).
    private func writeFinder(_ view: FinderDesktopView, fields: Set<FinderDesktopView.Field>) {
        CFPreferencesAppSynchronize(Self.finderDomain)
        if fields.contains(where: { $0.finderKey == nil }) {
            let current = CFPreferencesCopyAppValue(Self.viewKey, Self.finderDomain) as? [String: Any]
            CFPreferencesSetAppValue(Self.viewKey, view.written(into: current) as CFDictionary, Self.finderDomain)
        }
        let items = view.items
        for field in fields {
            guard let key = field.finderKey, let value = items[key] else { continue }
            CFPreferencesSetAppValue(key as CFString, NSNumber(value: value), Self.finderDomain)
        }
        CFPreferencesAppSynchronize(Self.finderDomain)
    }

    private var record: FinderSyncRecord? {
        get {
            UserDefaults.standard.data(forKey: Self.recordKey)
                .flatMap { try? JSONDecoder().decode(FinderSyncRecord.self, from: $0) }
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.recordKey) }
    }
}
