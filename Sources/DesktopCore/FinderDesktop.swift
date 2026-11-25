import CoreGraphics
import Foundation
import DesktopSettings
import SuiteFilesCore

/// Finder's desktop as the user set it up, what Bureau starts from at its first launch (the suite starts
/// from macOS, then changes only what the user turns on): Finder's View Options for the desktop
/// (`com.apple.finder`'s `DesktopViewSettings`: icon size, grid spacing, text size, label position, item
/// info, icon preview, Sort By, Use Stacks and Group Stacks By), the disks and servers its General settings
/// show on the desktop, and where Finder placed each icon (`~/Desktop/.DS_Store`).
public struct FinderDesktop: Equatable, Sendable {
    public var settings: DesktopSettings
    public var sortKey: SortKey
    public var ascending: Bool

    /// `view`: Finder's `DesktopViewSettings`; `items`: its `Show*OnDesktop` keys; `centres`: each icon's centre as Finder placed it, from the
    /// top-left of the screen (`FinderIconPositions`); `topInset`: where Bureau's area starts below the top
    /// of the screen (the menu bar).
    public init(view: [String: Any]?, items: [String: Any]? = nil, centres: [String: CGPoint], topInset: CGFloat) {
        var settings = DesktopSettings()
        settings.startsAtRight = true
        let finder = FinderDesktopView(finder: view, items: items)
        let sort = finder.adopt(Set(FinderDesktopView.Field.allCases), into: &settings)
        sortKey = sort?.key ?? .name
        ascending = sort?.ascending ?? true

        // Placed by hand, the icons stay where Finder had them: centres become the cells' top-left corners.
        if !settings.keepArranged {
            let cell = settings.cellSize
            for (name, centre) in centres {
                settings.positions[DesktopEntry.itemKey(forName: name)] = CGPoint(
                    x: max(0, centre.x - cell.width / 2),
                    y: max(0, centre.y - topInset - 4 - settings.iconSide / 2))
            }
        }
        self.settings = settings
    }

    public static func == (a: FinderDesktop, b: FinderDesktop) -> Bool {
        a.settings == b.settings && a.sortKey == b.sortKey && a.ascending == b.ascending
    }

    /// Finder's desktop on this Mac (read only: Finder's files are never written).
    public static func onThisMac(topInset: CGFloat) -> FinderDesktop {
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        let view = CFPreferencesCopyAppValue("DesktopViewSettings" as CFString, "com.apple.finder" as CFString)
            as? [String: Any]
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        return FinderDesktop(view: view, items: finderItems(), centres: FinderIconPositions.positions(in: desktop),
                             topInset: topInset)
    }

    /// Finder's `Show*OnDesktop` keys as set on this Mac (read only).
    public static func finderItems() -> [String: Any] {
        var items: [String: Any] = [:]
        for key in FinderDesktopView.itemKeys {
            items[key] = CFPreferencesCopyAppValue(key as CFString, "com.apple.finder" as CFString)
        }
        return items
    }
}
