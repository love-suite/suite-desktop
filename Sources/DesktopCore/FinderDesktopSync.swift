import Foundation
import DesktopSettings

/// What Bureau last wrote to Finder's desktop settings, and when: its timestamped copy. With it, a change
/// the user made in Finder is told apart from Finder writing back an old value it kept in memory.
public struct FinderSyncRecord: Codable, Equatable, Sendable {
    /// Finder's values as Bureau last wrote or saw them.
    public var finder: FinderDesktopView
    /// Finder's values before Bureau's last write: what a Finder running at that time may still hold in
    /// memory and write back.
    public var before: FinderDesktopView
    /// Bureau's settings as Finder saw them at the last sync (`FinderDesktopView(approximating:)`): only what
    /// changes on Bureau's side since then is written to Finder, so a value Finder can't hold exactly isn't
    /// written again and again.
    public var suite: FinderDesktopView
    /// When Bureau last wrote to Finder.
    public var written: Date

    public init(finder: FinderDesktopView, before: FinderDesktopView, suite: FinderDesktopView, written: Date) {
        self.finder = finder
        self.before = before
        self.suite = suite
        self.written = written
    }
}

/// The two ways of the sync between Bureau's settings and Finder's, without reading or writing anything:
/// Bureau's `FinderSync` does that.
public enum FinderDesktopSync {
    /// What Finder's settings, as read now, mean against the record.
    public struct Reading: Equatable, Sendable {
        /// Fields the user changed in Finder: Bureau takes them.
        public var changedInFinder: Set<FinderDesktopView.Field> = []
        /// Fields Finder put back from memory: Bureau writes its value again.
        public var putBack: Set<FinderDesktopView.Field> = []
        /// Finder's values once the fields put back are written again.
        public var finder: FinderDesktopView
    }

    /// `finderLaunched`: when the running Finder started; `finderRestarted`: when Bureau last restarted
    /// Finder (giving its desktop back), which lets the old Finder write what it held in memory as it quits.
    public static func read(_ finder: FinderDesktopView, record: FinderSyncRecord,
                            finderLaunched: Date?, finderRestarted: Date?) -> Reading {
        var reading = Reading(finder: finder)
        // A Finder that was running when Bureau wrote may still hold the values from before.
        let oldFinderRunning = finderLaunched.map { $0 < record.written } ?? false
        let oldFinderQuit = finderRestarted.map { $0 > record.written } ?? false
        let mayWriteFromMemory = oldFinderRunning || oldFinderQuit
        for field in FinderDesktopView.Field.allCases where finder.value(field) != record.finder.value(field) {
            if mayWriteFromMemory && finder.value(field) == record.before.value(field) {
                reading.putBack.insert(field)
                reading.finder.take(field, from: record.finder)
            } else {
                reading.changedInFinder.insert(field)
            }
        }
        return reading
    }

    /// The fields to write to Finder after a change on Bureau's side, and Finder's values once written.
    public static func write(_ suite: FinderDesktopView, record: FinderSyncRecord,
                             finder: FinderDesktopView) -> (fields: Set<FinderDesktopView.Field>, finder: FinderDesktopView) {
        var result = finder
        var fields: Set<FinderDesktopView.Field> = []
        for field in FinderDesktopView.Field.allCases
        where suite.value(field) != record.suite.value(field) && suite.value(field) != finder.value(field) {
            fields.insert(field)
            result.take(field, from: suite)
        }
        return (fields, result)
    }
}
