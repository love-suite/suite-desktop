import CoreGraphics
import Foundation
import Testing
@testable import DesktopCore
import DesktopSettings

@Suite struct FinderDesktopTests {
    private func view(arrangeBy: String, groupBy: String = "None", iconSize: Double = 64,
                      spacing: Double = 54) -> [String: Any] {
        ["GroupBy": groupBy,
         "IconViewSettings": ["arrangeBy": arrangeBy, "iconSize": iconSize, "gridSpacing": spacing]]
    }

    @Test func takesFindersIconSizeSpacingAndStacks() {
        let finder = FinderDesktop(view: view(arrangeBy: "dateAdded", groupBy: "Kind", iconSize: 72, spacing: 40),
                                   centres: [:], topInset: 25)
        #expect(finder.settings.iconSide == 72)
        #expect(finder.settings.gridSpacing == 40)
        #expect(finder.settings.stacks)
        #expect(finder.settings.keepArranged)
        #expect(finder.sortKey == .added)
        #expect(!finder.ascending)
    }

    @Test func iconsPlacedByHandStayWhereFinderHadThem() {
        let finder = FinderDesktop(view: view(arrangeBy: "none"),
                                   centres: ["Notes.txt": CGPoint(x: 200, y: 125)], topInset: 25)
        let cell = finder.settings.cellSize
        #expect(!finder.settings.keepArranged)
        #expect(!finder.settings.snapToGrid)
        #expect(finder.settings.positions[DesktopEntry.itemKey(forName: "Notes.txt")]
                == CGPoint(x: 200 - cell.width / 2, y: 125 - 25 - 4 - 32))
    }

    @Test func snapToGridKeepsPositionsOnTheGrid() {
        let finder = FinderDesktop(view: view(arrangeBy: "grid"), centres: ["a": CGPoint(x: 90, y: 90)], topInset: 0)
        #expect(finder.settings.snapToGrid)
        #expect(!finder.settings.keepArranged)
        #expect(finder.settings.positions.count == 1)
    }

    @Test func arrangedDesktopsIgnoreFindersPositions() {
        let finder = FinderDesktop(view: view(arrangeBy: "name"), centres: ["a": CGPoint(x: 90, y: 90)], topInset: 0)
        #expect(finder.settings.keepArranged)
        #expect(finder.settings.positions.isEmpty)
        #expect(finder.sortKey == .name)
        #expect(finder.ascending)
    }

    @Test func withoutFindersSettingsTheDesktopIsFindersDefault() {
        let finder = FinderDesktop(view: nil, centres: [:], topInset: 0)
        #expect(finder.settings.iconSide == 64)
        #expect(!finder.settings.stacks)
        #expect(!finder.settings.keepArranged)
        #expect(!finder.settings.snapToGrid)
    }
}
