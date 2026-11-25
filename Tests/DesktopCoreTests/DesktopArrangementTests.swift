import CoreGraphics
import Foundation
import Testing
@testable import DesktopCore
import SuiteFilesCore

private func file(_ name: String, kind: String, folder: Bool = false) -> FileItem {
    FileItem(url: URL(fileURLWithPath: "/d/\(name)"), name: name, isDirectory: folder, isPackage: false,
             size: nil, modified: nil, isHidden: false, kind: kind)
}

@Suite struct DesktopStackerTests {
    let items = [
        file("A", kind: "Folder", folder: true),
        file("a.png", kind: "PNG image"),
        file("b.txt", kind: "Text"),
        file("c.png", kind: "PNG image"),
        file("B", kind: "Folder", folder: true),
    ]

    @Test func withoutStacksEveryItemShows() {
        let entries = DesktopStacker.entries(for: items, byKind: false)
        #expect(entries.map(\.key) == ["item:A", "item:a.png", "item:b.txt", "item:c.png", "item:B"])
    }

    @Test func byKindStacksRepeatedFileTypesInFirstSeenOrderAndLeavesFoldersAlone() {
        let entries = DesktopStacker.entries(for: items, byKind: true)
        #expect(entries.map(\.key) == ["item:A", "stack:PNG image", "item:b.txt", "item:B"])
        #expect(entries[1].name == "PNG image")
        #expect(entries[1].items.map(\.name) == ["a.png", "c.png"])
    }
}

@Suite struct AliasAndFolderTests {
    @Test func foldersAndAliasesAreNeverStacked() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let target = try sandbox.make("Projects", directory: true)
        let note = try sandbox.make("note.txt")
        try sandbox.make("other.txt")
        try FileManager.default.createSymbolicLink(at: sandbox.root.appendingPathComponent("Projects link"),
                                                   withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: sandbox.root.appendingPathComponent("note link"),
                                                   withDestinationURL: note)

        let items = try DirectoryLoader.load(sandbox.root)
        #expect(items.filter(\.isAlias).map(\.name).sorted() == ["Projects link", "note link"])

        // As Finder: folders and aliases stay on their own; the two text files make a stack.
        let entries = DesktopStacker.entries(for: items, byKind: true)
        let alone = entries.compactMap { entry -> String? in if case .item(let item) = entry { item.name } else { nil } }
        #expect(alone.sorted() == ["Projects", "Projects link", "note link"])
        #expect(entries.filter { if case .stack = $0 { true } else { false } }.count == 1)
    }

    @Test func newFolderGetsAUniqueName() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.make("New Folder", directory: true)

        let created = try FileTemplate.folder.create(in: sandbox.root)

        #expect(created.lastPathComponent == "New Folder (2)")
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: created.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }
}

extension DesktopStackerTests {
    @Test func expandedStackIsFollowedByItsItems() {
        let entries = DesktopStacker.entries(for: items, byKind: true, expanded: ["stack:PNG image"])
        #expect(entries.map(\.key) == ["item:A", "stack:PNG image", "item:a.png", "item:c.png", "item:b.txt", "item:B"])
    }
}

@Suite struct DesktopGridTests {
    // 3 columns × 2 rows of 100×100.
    let grid = DesktopGrid(cell: CGSize(width: 100, height: 100), area: CGSize(width: 350, height: 250), fromRight: false)

    @Test func fillsColumnByColumnFromTopLeft() {
        #expect(grid.capacity == 6)
        #expect(grid.origin(ofCell: 0) == CGPoint(x: 0, y: 0))
        #expect(grid.origin(ofCell: 1) == CGPoint(x: 0, y: 100))
        #expect(grid.origin(ofCell: 2) == CGPoint(x: 100, y: 0))
    }

    @Test func snapsToNearestFreeCell() {
        #expect(grid.cellIndex(nearest: CGPoint(x: 140, y: 60)) == 3)
        #expect(grid.nearestFreeCell(to: CGPoint(x: 140, y: 60), taken: [3]) == 2)
    }

    @Test func clampKeepsItemsInside() {
        #expect(grid.clamp(CGPoint(x: -20, y: 400)) == CGPoint(x: 0, y: 150))
    }
}

@Suite struct DesktopArrangerTests {
    // 3 columns × 2 rows: 6 cells.
    let grid = DesktopGrid(cell: CGSize(width: 100, height: 100), area: CGSize(width: 300, height: 200), fromRight: false)

    private func layout(_ keys: [String], saved: [String: CGPoint] = [:], snap: Bool = true,
                        overflowStack: Bool = true) -> DesktopLayout {
        DesktopArranger.layout(for: keys, saved: saved, grid: grid, snapToGrid: snap, overflowStack: overflowStack)
    }

    @Test func newEntriesFillFreeCellsAroundSavedOnes() {
        let result = layout(["a", "b", "c"], saved: ["b": CGPoint(x: 0, y: 0)])
        #expect(result.positions["b"] == CGPoint(x: 0, y: 0))
        #expect(result.positions["a"] == CGPoint(x: 0, y: 100))
        #expect(result.positions["c"] == CGPoint(x: 100, y: 0))
        #expect(result.overflow.isEmpty && result.overflowPosition == nil)
    }

    @Test func gridMovesCollidingItemsToNearestFreeCell() {
        let result = layout(["a", "b"], saved: ["a": CGPoint(x: 210, y: 10), "b": CGPoint(x: 190, y: 0)])
        #expect(result.positions["a"] == CGPoint(x: 200, y: 0))
        // (100, 0) is 90 points away, (200, 100) about 100.
        #expect(result.positions["b"] == CGPoint(x: 100, y: 0))
    }

    @Test func freePlacementKeepsExactPositions() {
        let result = layout(["a"], saved: ["a": CGPoint(x: 37, y: 52)], snap: false)
        #expect(result.positions["a"] == CGPoint(x: 37, y: 52))
    }

    @Test func exactlyFullNeedsNoOverflow() {
        let result = layout(["1", "2", "3", "4", "5", "6"])
        #expect(result.positions.count == 6 && result.overflow.isEmpty && result.overflowPosition == nil)
    }

    @Test func overflowStackTakesTheLastCellAndCollectsTheRest() {
        let result = layout(["1", "2", "3", "4", "5", "6", "7", "8"])
        #expect(result.positions.count == 5)
        #expect(result.overflow == ["6", "7", "8"])
        #expect(result.overflowPosition == CGPoint(x: 200, y: 100))
        #expect(!result.positions.values.contains(CGPoint(x: 200, y: 100)))
    }

    @Test func dropOnTheGridAvoidsOccupiedCells() {
        let positions = ["a": CGPoint(x: 0, y: 0), "b": CGPoint(x: 100, y: 0)]
        // Drag "a" right by 110: b's cell (100, 0) is taken; of the free ones (200, 0) is 90 points away.
        let result = DesktopArranger.drop(["a": CGPoint(x: 0, y: 0)], by: CGSize(width: 110, height: 0),
                                          among: positions, grid: grid, snapToGrid: true)
        #expect(result["b"] == CGPoint(x: 100, y: 0))
        #expect(result["a"] == CGPoint(x: 200, y: 0))
    }

    @Test func dropWithoutGridLandsExactlyAndMayOverlap() {
        let positions = ["a": CGPoint(x: 0, y: 0), "b": CGPoint(x: 100, y: 0)]
        let result = DesktopArranger.drop(["a": CGPoint(x: 0, y: 0)], by: CGSize(width: 95, height: 7),
                                          among: positions, grid: grid, snapToGrid: false)
        #expect(result["a"] == CGPoint(x: 95, y: 7))
        #expect(result["b"] == CGPoint(x: 100, y: 0))
    }

    @Test func withoutOverflowStackTheRestIsHidden() {
        let result = layout(["1", "2", "3", "4", "5", "6", "7", "8"], overflowStack: false)
        #expect(result.positions.count == 6)
        #expect(result.overflow == ["7", "8"])
        #expect(result.overflowPosition == nil)
    }
}

@Suite struct DesktopGridFromRightTests {
    let grid = DesktopGrid(cell: CGSize(width: 100, height: 100), area: CGSize(width: 350, height: 250))

    @Test func fillsColumnsFromTheTopRightAsFinder() {
        #expect(grid.origin(ofCell: 0) == CGPoint(x: 250, y: 0))
        #expect(grid.origin(ofCell: 1) == CGPoint(x: 250, y: 100))
        #expect(grid.origin(ofCell: 2) == CGPoint(x: 150, y: 0))
    }

    @Test func findsTheCellUnderAPoint() {
        for index in 0..<grid.capacity {
            #expect(grid.cellIndex(nearest: grid.origin(ofCell: index)) == index)
        }
    }
}

extension DesktopStackerTests {
    /// The setting that brings back the earlier stacks: folders and aliases in a stack of their own.
    @Test func foldersCanShareAStackWhenChosen() {
        let entries = DesktopStacker.entries(for: items, byKind: true, stacksFolders: true)
        #expect(entries.map(\.key) == ["stack:Folders", "stack:PNG image", "item:b.txt"])
    }
}

@Suite struct DesktopWidgetTests {
    /// 3 columns × 2 rows of 100×100, from the left; a widget over the top-left cell.
    let grid = DesktopGrid(cell: CGSize(width: 100, height: 100), area: CGSize(width: 300, height: 200),
                           fromRight: false, blocked: [CGRect(x: 0, y: 0, width: 100, height: 100)])

    @Test func cellsUnderAWidgetAreBlocked() {
        #expect(grid.blockedCells == [0])
        #expect(grid.freeCapacity == 5)
    }

    @Test func iconsKeepClearOfWidgets() {
        let layout = DesktopArranger.layout(for: ["a", "b"], saved: ["a": CGPoint(x: 0, y: 0)], grid: grid,
                                            snapToGrid: true, overflowStack: true)
        #expect(!layout.positions.values.contains(CGPoint(x: 0, y: 0)))
        #expect(layout.positions.count == 2)
    }

    @Test func iconsPlacedFreelyMoveOutFromUnderAWidget() {
        let layout = DesktopArranger.layout(for: ["a"], saved: ["a": CGPoint(x: 10, y: 10)], grid: grid,
                                            snapToGrid: false, overflowStack: true)
        #expect(layout.positions["a"] == CGPoint(x: 0, y: 100))
    }

    @Test func droppingOnAWidgetLandsNextToIt() {
        let result = DesktopArranger.drop(["a": CGPoint(x: 200, y: 0)], by: CGSize(width: -195, height: 5),
                                          among: ["a": CGPoint(x: 200, y: 0)], grid: grid, snapToGrid: false)
        #expect(result["a"] != CGPoint(x: 5, y: 5))
        #expect(!grid.blockedCells.contains(grid.cellIndex(nearest: result["a"]!)))
    }

    @Test func aBarelyTouchedCellStaysFree() {
        let touched = DesktopGrid(cell: CGSize(width: 100, height: 100), area: CGSize(width: 300, height: 200),
                                  fromRight: false, blocked: [CGRect(x: 0, y: 0, width: 110, height: 100)])
        #expect(touched.blockedCells == [0])
    }
}
