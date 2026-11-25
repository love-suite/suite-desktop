import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DesktopCore
import DesktopSettings
import SuiteFilesCore

/// Finder's View Options and General settings beyond icon size and Sort By: label position, item info,
/// icon preview, Group Stacks By, the items shown on the desktop.
@Suite struct FinderDesktopOptionsTests {
    @Test func readsFindersViewOptionsAndItemsWithFindersDefaults() {
        let missing = FinderDesktopView(finder: nil)
        #expect(missing.labelOnBottom && !missing.showItemInfo && missing.showIconPreview)
        #expect(!missing.showHardDrives && missing.showExternalHardDrives && missing.showRemovableMedia
                && !missing.showMountedServers)

        let view: [String: Any] = ["GroupBy": "Date Added",
                                   "IconViewSettings": ["labelOnBottom": false, "showItemInfo": true,
                                                        "showIconPreview": false]]
        let items: [String: Any] = ["ShowHardDrivesOnDesktop": true, "ShowMountedServersOnDesktop": true,
                                    "ShowRemovableMediaOnDesktop": false]
        let read = FinderDesktopView(finder: view, items: items)
        #expect(!read.labelOnBottom && read.showItemInfo && !read.showIconPreview)
        #expect(read.showHardDrives && read.showExternalHardDrives && !read.showRemovableMedia && read.showMountedServers)
        #expect(read.items == ["ShowHardDrivesOnDesktop": true, "ShowExternalHardDrivesOnDesktop": true,
                               "ShowRemovableMediaOnDesktop": false, "ShowMountedServersOnDesktop": true])
    }

    @Test func bureausSettingsBecomeFindersValues() {
        var settings = DesktopSettings()
        settings.labelPosition = .right
        settings.showsItemInfo = true
        settings.showsIconPreview = false
        settings.stacks = true
        settings.stackGrouping = .tags
        settings.showsHardDisks = true
        let view = FinderDesktopView(approximating: settings, sortKey: .name, ascending: true)
        #expect(!view.labelOnBottom && view.showItemInfo && !view.showIconPreview)
        #expect(view.groupBy == "Label")
        #expect(view.showHardDrives)
        let icons = view.written(into: nil)["IconViewSettings"] as? [String: Any]
        #expect(icons?["labelOnBottom"] as? Bool == false)
        #expect(icons?["showItemInfo"] as? Bool == true)
        #expect(icons?["showIconPreview"] as? Bool == false)
        // Stacks off: Finder's None, whatever they group by.
        settings.stacks = false
        #expect(FinderDesktopView(approximating: settings, sortKey: .name, ascending: true).groupBy == "None")
    }

    @Test func findersGroupStacksByIsTaken() {
        var settings = DesktopSettings()
        var view = FinderDesktopView()
        view.groupBy = "Date Last Opened"
        _ = view.adopt([.groupBy], into: &settings)
        #expect(settings.stacks && settings.stackGrouping == .dateLastOpened)
        // Use Stacks off keeps the grouping for when they come back.
        view.groupBy = "None"
        _ = view.adopt([.groupBy], into: &settings)
        #expect(!settings.stacks && settings.stackGrouping == .dateLastOpened)
        // A grouping stacks don't offer: by kind.
        view.groupBy = "Application"
        _ = view.adopt([.groupBy], into: &settings)
        #expect(settings.stacks && settings.stackGrouping == .kind)
    }

    @Test func adoptingEveryFieldThenApproximatingGivesFindersValuesBack() {
        var finder = FinderDesktopView()
        finder.labelOnBottom = false
        finder.showItemInfo = true
        finder.showIconPreview = false
        finder.groupBy = "Date Created"
        finder.arrangeBy = "grid"
        finder.showHardDrives = true
        finder.showExternalHardDrives = false
        finder.showRemovableMedia = false
        finder.showMountedServers = true
        var settings = DesktopSettings()
        _ = finder.adopt(Set(FinderDesktopView.Field.allCases), into: &settings)
        let back = FinderDesktopView(approximating: settings, sortKey: .name, ascending: true)
        for field in FinderDesktopView.Field.allCases {
            #expect(back.value(field) == finder.value(field), "\(field)")
        }
    }

    @Test func aRecordSavedBeforeTheNewFieldsStillDecodes() throws {
        let old = #"{"iconSize":96,"gridSpacing":54,"textSize":12,"arrangeBy":"grid","groupBy":"None"}"#
        let view = try JSONDecoder().decode(FinderDesktopView.self, from: Data(old.utf8))
        #expect(view.iconSize == 96)
        #expect(view.labelOnBottom && view.showIconPreview && view.showExternalHardDrives)
        let settings = try JSONDecoder().decode(DesktopSettings.self, from: Data(#"{"iconSide":40}"#.utf8))
        #expect(settings.iconSide == 40 && settings.labelPosition == .bottom && settings.stackGrouping == .kind)
        #expect(settings.showsIconPreview && !settings.showsItemInfo && settings.springLoading)
        #expect(!settings.showsHardDisks && settings.showsExternalDisks && settings.showsRemovableMedia
                && !settings.showsConnectedServers)
    }

    @Test func aChangeOfFindersItemsIsTheUsers() {
        let synced = FinderSyncRecord(finder: FinderDesktopView(), before: FinderDesktopView(),
                                      suite: FinderDesktopView(), written: Date(timeIntervalSince1970: 0))
        var finder = FinderDesktopView()
        finder.showHardDrives = true
        finder.labelOnBottom = false
        let reading = FinderDesktopSync.read(finder, record: synced, finderLaunched: nil, finderRestarted: nil)
        #expect(reading.changedInFinder == [.showHardDrives, .labelOnBottom])
        let write = FinderDesktopSync.write(finder, record: synced, finder: FinderDesktopView())
        #expect(write.fields == [.showHardDrives, .labelOnBottom])
        #expect(FinderDesktopView.Field.showHardDrives.finderKey == "ShowHardDrivesOnDesktop")
        #expect(FinderDesktopView.Field.labelOnBottom.finderKey == nil)
    }

    @Test func theFirstLaunchTakesFindersItemsAndOptions() {
        let view: [String: Any] = ["GroupBy": "Label", "IconViewSettings": ["labelOnBottom": false]]
        let finder = FinderDesktop(view: view, items: ["ShowHardDrivesOnDesktop": true], centres: [:], topInset: 0)
        #expect(finder.settings.showsHardDisks)
        #expect(finder.settings.labelPosition == .right)
        #expect(finder.settings.stacks && finder.settings.stackGrouping == .tags)
    }

    @Test func cellsMakeRoomForNamesOnTheRightAndTheItemInfo() {
        var settings = DesktopSettings()
        let bottom = settings.cellSize
        settings.showsItemInfo = true
        #expect(settings.cellSize.height > bottom.height)
        #expect(settings.cellSize.width == bottom.width)
        settings.labelPosition = .right
        #expect(settings.cellSize.width > bottom.width + settings.iconSide)
    }
}

@Suite struct DesktopVolumeTests {
    private func volume(_ name: String, _ kind: DesktopVolume.Kind, startup: Bool = false) -> DesktopVolume {
        let item = FileItem(url: URL(fileURLWithPath: startup ? "/" : "/Volumes/\(name)"), name: name,
                            isDirectory: true, isPackage: false, size: nil, modified: nil, isHidden: false, kind: nil)
        return DesktopVolume(item: item, kind: kind, isStartup: startup)
    }

    @Test func kindsAreToldApartAsFindersAre() {
        typealias Kind = DesktopVolume.Kind
        #expect(Kind.of(isLocal: false, isInternal: nil, isRemovable: nil, isEjectable: true) == .server)
        #expect(Kind.of(isLocal: true, isInternal: false, isRemovable: true, isEjectable: true) == .removableMedia)
        #expect(Kind.of(isLocal: true, isInternal: false, isRemovable: false, isEjectable: true) == .externalDisk)
        #expect(Kind.of(isLocal: true, isInternal: true, isRemovable: false, isEjectable: false) == .hardDisk)
        // A disk image: macOS doesn't say whether it is internal, but it can be ejected.
        #expect(Kind.of(isLocal: true, isInternal: nil, isRemovable: false, isEjectable: true) == .externalDisk)
    }

    @Test func finderSettingsChooseWhatShowsStartupDiskFirst() {
        let all = [volume("Server", .server), volume("USB", .externalDisk), volume("Data", .hardDisk),
                   volume("Macintosh HD", .hardDisk, startup: true), volume("DVD", .removableMedia),
                   volume("Backup", .externalDisk)]
        var settings = DesktopSettings()
        #expect(DesktopVolume.shown(all, settings: settings).map(\.item.name) == ["Backup", "USB", "DVD"])
        settings.showsHardDisks = true
        settings.showsConnectedServers = true
        #expect(DesktopVolume.shown(all, settings: settings).map(\.item.name)
                == ["Macintosh HD", "Data", "Backup", "USB", "DVD", "Server"])
        #expect(!all[3].canEject && all[1].canEject)
    }

    @Test func disksHaveKeysOfTheirOwnAndTakeTheFirstCells() {
        let entry = DesktopEntry.volume(volume("USB", .externalDisk))
        #expect(entry.key == "volume:/Volumes/USB")
        #expect(entry.name == "USB" && entry.volume != nil)
        let grid = DesktopGrid(cell: CGSize(width: 100, height: 100), area: CGSize(width: 500, height: 300))
        let layout = DesktopArranger.layout(for: [entry.key, "item:a"], saved: [:], grid: grid, snapToGrid: true,
                                            overflowStack: true)
        #expect(layout.positions[entry.key] == CGPoint(x: 400, y: 0))
    }
}

@Suite struct StackGroupingTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 25 November 2026, noon.
    let now = Date(timeIntervalSince1970: 1_795_608_000)

    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    @Test func datesFallInFindersPeriods() {
        func period(_ date: Date?) -> StackGroup { .period(of: date, now: now, calendar: calendar) }
        #expect(period(now) == .today)
        #expect(period(daysAgo(1)) == .yesterday)
        #expect(period(daysAgo(4)) == .previousDays(7))
        #expect(period(daysAgo(20)) == .previousDays(30))
        #expect(period(daysAgo(120)) == .month(7))
        #expect(period(daysAgo(400)) == .year(2025))
        #expect(period(nil) == .noDate)
        #expect(period(now.addingTimeInterval(86_400 * 3)) == .noDate)
    }

    @Test func groupIdsComeBack() {
        let groups: [StackGroup] = [.kind("PNG image"), .folders, .today, .yesterday, .previousDays(7),
                                    .previousDays(30), .month(3), .year(2020), .noDate, .tag("Red: urgent"), .noTags]
        for group in groups { #expect(StackGroup(id: group.id) == group) }
    }

    private func file(_ name: String, modified: Date?, folder: Bool = false) -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/d/\(name)"), name: name, isDirectory: folder, isPackage: false,
                 size: nil, modified: modified, isHidden: false, kind: "Text")
    }

    @Test func stacksGroupByDateAndByTag() {
        let items = [file("a", modified: now), file("b", modified: daysAgo(3)), file("c", modified: now),
                     file("F", modified: now, folder: true), file("d", modified: daysAgo(5))]
        let facts = StackFacts(now: now, calendar: calendar)
        let byDate = DesktopStacker.entries(for: items, grouping: .dateModified, facts: facts)
        #expect(byDate.map(\.key) == ["stack:date:today", "stack:date:previous:7", "item:F"])
        #expect(byDate[0].items.map(\.name) == ["a", "c"])

        var tagged = facts
        tagged.tags = [items[0].url: ["Red", "Blue"], items[1].url: ["Red"]]
        let byTag = DesktopStacker.entries(for: items, grouping: .tags, facts: tagged)
        #expect(byTag.map(\.key) == ["stack:tag:Red", "stack:tag:", "item:F"])
        #expect(byTag[1].items.map(\.name) == ["c", "d"])
        // By kind, as before.
        #expect(DesktopStacker.entries(for: items, grouping: .kind) == DesktopStacker.entries(for: items, byKind: true))
    }
}

@Suite struct CleanUpTests {
    private func file(_ name: String, size: Int64? = nil, modified: Double? = nil, folder: Bool = false,
                      kind: String = "Text") -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/d/\(name)"), name: name, isDirectory: folder, isPackage: false,
                 size: size, modified: modified.map { Date(timeIntervalSince1970: $0) }, isHidden: false, kind: kind)
    }

    @Test func linesUpAsFindersCleanUpBy() {
        let items = [file("b", size: 10, modified: 1), file("a10", size: 30, modified: 3),
                     file("a2", modified: 2, kind: "Image"), file("Z", folder: true)]
        #expect(DesktopCleanUp.ordered(items, by: .name).map(\.name) == ["a2", "a10", "b", "Z"])
        #expect(DesktopCleanUp.ordered(items, by: .name, foldersFirst: true).map(\.name) == ["Z", "a2", "a10", "b"])
        #expect(DesktopCleanUp.ordered(items, by: .size).map(\.name) == ["a10", "b", "a2", "Z"])
        #expect(DesktopCleanUp.ordered(items, by: .dateModified).map(\.name) == ["a10", "a2", "b", "Z"])
        #expect(DesktopCleanUp.ordered(items, by: .kind).map(\.name) == ["a2", "a10", "b", "Z"])
        let facts = StackFacts(tags: [items[1].url: ["Work"], items[0].url: ["Home"]])
        #expect(DesktopCleanUp.ordered(items, by: .tags, facts: facts).map(\.name) == ["b", "a10", "a2", "Z"])
    }

    @Test func cleanUpPutsEveryIconOnTheNearestFreeCell() {
        let grid = DesktopGrid(cell: CGSize(width: 100, height: 100), area: CGSize(width: 500, height: 300),
                               fromRight: false)
        let layout = DesktopArranger.layout(for: ["a", "b"], saved: ["a": CGPoint(x: 130, y: 40),
                                                                     "b": CGPoint(x: 140, y: 60)],
                                            grid: grid, snapToGrid: true, overflowStack: false)
        #expect(layout.positions["a"] == CGPoint(x: 100, y: 0))
        #expect(layout.positions["b"] != layout.positions["a"])
    }
}

@Suite struct SpringLoadingTests {
    @Test func followsMacOSSettingsWithItsDefaults() {
        #expect(SpringLoading(global: [:]) == SpringLoading(enabled: true, delay: 0.5))
        let set = SpringLoading(global: ["com.apple.springing.enabled": false, "com.apple.springing.delay": 1.2])
        #expect(!set.enabled && set.delay == 1.2)
    }

    @Test func aFolderSpringsOpenOnceThePointerRestedOnItForTheDelay() {
        var loader = SpringLoader()
        let t0 = Date(timeIntervalSince1970: 100)
        let entered = loader.hover("item:Folder", at: t0)
        let stayed = loader.hover("item:Folder", at: t0.addingTimeInterval(0.2))
        #expect(entered && !stayed)
        let early = loader.fire(at: t0.addingTimeInterval(0.3), delay: 0.5)
        let due = loader.fire(at: t0.addingTimeInterval(0.5), delay: 0.5)
        // Opened once per drag.
        let again = loader.fire(at: t0.addingTimeInterval(2), delay: 0.5)
        #expect(early == nil && due == "item:Folder" && again == nil)
        // Moving off it: nothing springs.
        let left = loader.hover(nil, at: t0.addingTimeInterval(3))
        let nothing = loader.fire(at: t0.addingTimeInterval(9), delay: 0.5)
        #expect(left && nothing == nil)
        loader.reset()
        loader.hover("item:Folder", at: t0)
        let nextDrag = loader.fire(at: t0.addingTimeInterval(1), delay: 0.5)
        #expect(nextDrag == "item:Folder")
    }
}

@Suite struct ItemInfoTests {
    @Test func foldersCountTheirItemsAndPicturesGiveTheirSize() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let folder = try sandbox.make("Folder", directory: true)
        try sandbox.make("Folder/a.txt")
        try sandbox.make("Folder/b.txt")
        try sandbox.make("Folder/.hidden")
        #expect(ItemInfo.read(for: DirectoryLoader.item(at: folder)) == .items(2))
        #expect(ItemInfo.read(for: DirectoryLoader.item(at: folder), countingHidden: true) == .items(3))

        let picture = sandbox.root.appendingPathComponent("p.png")
        let context = try #require(CGContext(data: nil, width: 30, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(picture as CFURL, UTType.png.identifier as CFString,
                                                                       1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        #expect(ItemInfo.read(for: DirectoryLoader.item(at: picture)) == .pixels(width: 30, height: 20))
        #expect(ItemInfo.read(for: DirectoryLoader.item(at: sandbox.root.appendingPathComponent("Folder/a.txt"))) == nil)
    }

    @Test func lengthsAreWrittenAsFindersAre() {
        #expect(ItemInfo.durationText(65) == "01:05")
        #expect(ItemInfo.durationText(3723) == "1:02:03")
    }

    @Test func tagsAreRead() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let url = try sandbox.make("tagged.txt")
        try (url as NSURL).setResourceValue(["Work"], forKey: .tagNamesKey)
        let item = DirectoryLoader.item(at: url)
        #expect(FileFacts.read(for: [item], lastOpened: false, tags: true).tags[item.url] == ["Work"])
    }
}
