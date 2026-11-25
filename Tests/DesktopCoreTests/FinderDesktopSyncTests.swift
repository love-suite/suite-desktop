import Foundation
import Testing
@testable import DesktopCore
import DesktopSettings
import SuiteFilesCore

@Suite struct FinderDesktopViewTests {
    @Test func beyondFindersRangeFinderGetsTheClosestValue() {
        var settings = DesktopSettings()
        settings.iconSide = 200
        settings.textSize = 9
        let view = FinderDesktopView(approximating: settings, sortKey: .name, ascending: true)
        #expect(view.iconSize == 128)
        #expect(view.textSize == 10)
        #expect(FinderDesktopView.approximated(settings, sortKey: .name) == [.iconSize, .textSize])
    }

    @Test func arrangementAndStacksBecomeFindersSortByAndUseStacks() {
        var settings = DesktopSettings()
        settings.keepArranged = true
        settings.stacks = true
        let view = FinderDesktopView(approximating: settings, sortKey: .modified, ascending: false)
        #expect(view.arrangeBy == "dateModified")
        #expect(view.groupBy == "Kind")
        settings.keepArranged = false
        settings.snapToGrid = true
        #expect(FinderDesktopView(approximating: settings, sortKey: .name, ascending: true).arrangeBy == "grid")
    }

    @Test func writingKeepsFindersOtherKeys() {
        let finder: [String: Any] = ["IconViewSettings": ["labelOnBottom": true, "iconSize": 64], "Other": 1]
        var view = FinderDesktopView(finder: finder)
        view.iconSize = 96
        let written = view.written(into: finder)
        let icons = written["IconViewSettings"] as? [String: Any]
        #expect(icons?["labelOnBottom"] as? Bool == true)
        #expect(icons?["iconSize"] as? Double == 96)
        #expect(written["Other"] as? Int == 1)
    }

    @Test func adoptingTakesOnlyTheGivenFields() {
        var settings = DesktopSettings()
        settings.iconSide = 200
        var view = FinderDesktopView()
        view.iconSize = 128
        view.gridSpacing = 80
        _ = view.adopt([.gridSpacing], into: &settings)
        #expect(settings.iconSide == 200)
        #expect(settings.gridSpacing == 80)
    }
}

@Suite struct FinderDesktopSyncTests {
    let t0 = Date(timeIntervalSince1970: 1000)

    private func view(icon: Double = 64, spacing: Double = 54) -> FinderDesktopView {
        var view = FinderDesktopView()
        view.iconSize = icon
        view.gridSpacing = spacing
        return view
    }

    /// Bureau wrote 96 over Finder's 64 at t0.
    private var record: FinderSyncRecord {
        FinderSyncRecord(finder: view(icon: 96), before: view(icon: 64), suite: view(icon: 96), written: t0)
    }

    @Test func nothingChangedNothingToDo() {
        let reading = FinderDesktopSync.read(view(icon: 96), record: record, finderLaunched: nil, finderRestarted: nil)
        #expect(reading.changedInFinder.isEmpty && reading.putBack.isEmpty)
    }

    @Test func aNewValueInFinderIsTheUsers() {
        let reading = FinderDesktopSync.read(view(icon: 96, spacing: 70), record: record,
                                             finderLaunched: t0.addingTimeInterval(-60), finderRestarted: nil)
        #expect(reading.changedInFinder == [.gridSpacing])
        #expect(reading.putBack.isEmpty)
    }

    @Test func theOldValueFromAFinderRunningBeforeTheWriteIsPutBack() {
        let reading = FinderDesktopSync.read(view(icon: 64), record: record,
                                             finderLaunched: t0.addingTimeInterval(-60), finderRestarted: nil)
        #expect(reading.putBack == [.iconSize])
        #expect(reading.finder.iconSize == 96)
    }

    @Test func theOldValueFromAFinderQuittingAfterTheWriteIsPutBack() {
        let reading = FinderDesktopSync.read(view(icon: 64), record: record,
                                             finderLaunched: t0.addingTimeInterval(120),
                                             finderRestarted: t0.addingTimeInterval(118))
        #expect(reading.putBack == [.iconSize])
    }

    @Test func theOldValueChosenInAFinderStartedAfterTheWriteIsTheUsers() {
        let reading = FinderDesktopSync.read(view(icon: 64), record: record,
                                             finderLaunched: t0.addingTimeInterval(120), finderRestarted: nil)
        #expect(reading.changedInFinder == [.iconSize])
        #expect(reading.putBack.isEmpty)
    }

    @Test func onlyWhatChangedInBureauIsWritten() {
        // Bureau has 200, which Finder holds as 128: unchanged in Bureau, it isn't written again.
        let synced = FinderSyncRecord(finder: view(icon: 128), before: view(icon: 128), suite: view(icon: 128), written: t0)
        let same = FinderDesktopSync.write(view(icon: 128), record: synced, finder: view(icon: 112))
        #expect(same.fields.isEmpty)
        let changed = FinderDesktopSync.write(view(icon: 128, spacing: 30), record: synced, finder: view(icon: 112))
        #expect(changed.fields == [.gridSpacing])
        #expect(changed.finder.iconSize == 112 && changed.finder.gridSpacing == 30)
    }
}
