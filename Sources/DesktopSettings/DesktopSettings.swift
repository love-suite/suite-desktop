import CoreGraphics
import Foundation
import SuiteFilesCore

/// How the desktop is arranged. Positions are kept by entry key, from the top-left of the usable area.
/// The desktop's settings, in Desktop.app's defaults, shared by the desktop and its settings tab in Suite
/// Settings. `DesktopSettings.current` loads and saves them; setting it tells the desktop (`didChange`).
public struct DesktopSettings: Codable, Equatable, Sendable {
    /// Stacks group items by type, as Finder's Use Stacks does; inside, items follow the sort order.
    public var stacks = false
    public var snapToGrid = true
    /// The desktop kept arranged in sort order (Finder's Sort By other than None or Snap to Grid): icons
    /// can't be placed by hand, saved positions don't apply.
    public var keepArranged = false
    /// The icons' side, in points: 16 to 128 as Finder's Icon Size slider, up to 256 beyond Finder's.
    public var iconSide: Double = 64
    /// Finder's Grid Spacing, 1 to 100: the room between icons.
    public var gridSpacing: Double = 54
    /// The icons' names, in points: 10 to 16 as Finder's Text Size, from 9 to 24 beyond Finder's.
    public var textSize: Double = 12
    /// Icons fill the desktop from the top-right, as Finder does; off, from the top-left, as Windows does.
    public var startsAtRight = true
    /// Folders (and aliases to them) first: as Finder's Keep folders on top for the desktop, always, never.
    public var foldersFirst: FoldersFirst = .asFinder
    /// Folders and aliases gathered in a stack of their own; off, they stay on their own, as Finder leaves them.
    public var stacksFolders = false
    /// Stacks only while the desktop is sorted by type; off, whatever the sort order, as Finder's.
    public var stacksOnlyWhenSortedByType = false
    /// Names in bold, as Finder's desktop writes them; off, regular.
    public var boldNames = true
    /// When the desktop is full, the items that don't fit go into one stack; otherwise they are hidden.
    public var overflowStack = true
    /// While dragging, highlight where the icons will land.
    public var showDropTarget = true
    /// While dragging, the icons follow the cursor; otherwise they stay put until dropped.
    public var iconsFollowCursor = true
    /// What stacks group by, as Finder's Group Stacks By.
    public var stackGrouping: StackGrouping = .kind
    /// Names under the icons or on their right, as Finder's Label Position.
    public var labelPosition: LabelPosition = .bottom
    /// A second line under the name, as Finder's Show Item Info: a picture's size, a folder's item count, a
    /// disk's capacity and free space.
    public var showsItemInfo = false
    /// Thumbnails of the files' contents instead of their icons, as Finder's Show Icon Preview.
    public var showsIconPreview = true
    /// Finder's Settings › General › Show these items on the desktop, with Finder's defaults: hard disks
    /// (the Mac's own), external disks (disk images included), CDs, DVDs and iPods (removable media), and
    /// connected servers.
    public var showsHardDisks = false
    public var showsExternalDisks = true
    public var showsRemovableMedia = true
    public var showsConnectedServers = false
    /// While dragging, folders and stacks open when the pointer rests on them, after macOS's delay
    /// (`com.apple.springing.enabled` and `.delay`, System Settings › Accessibility › Pointer Control);
    /// never when macOS has spring-loading off.
    public var springLoading = true
    public var positions: [String: CGPoint] = [:]

    public init() {}

    // Options saved before one of them existed still decode, with its default.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stacks = try values.decodeIfPresent(Bool.self, forKey: .stacks) ?? false
        snapToGrid = try values.decodeIfPresent(Bool.self, forKey: .snapToGrid) ?? true
        keepArranged = try values.decodeIfPresent(Bool.self, forKey: .keepArranged) ?? false
        iconSide = try values.decodeIfPresent(Double.self, forKey: .iconSide) ?? 64
        gridSpacing = try values.decodeIfPresent(Double.self, forKey: .gridSpacing) ?? 54
        textSize = try values.decodeIfPresent(Double.self, forKey: .textSize) ?? 12
        startsAtRight = try values.decodeIfPresent(Bool.self, forKey: .startsAtRight) ?? true
        foldersFirst = try values.decodeIfPresent(FoldersFirst.self, forKey: .foldersFirst) ?? .asFinder
        stacksFolders = try values.decodeIfPresent(Bool.self, forKey: .stacksFolders) ?? false
        stacksOnlyWhenSortedByType = try values.decodeIfPresent(Bool.self, forKey: .stacksOnlyWhenSortedByType) ?? false
        boldNames = try values.decodeIfPresent(Bool.self, forKey: .boldNames) ?? true
        overflowStack = try values.decodeIfPresent(Bool.self, forKey: .overflowStack) ?? true
        showDropTarget = try values.decodeIfPresent(Bool.self, forKey: .showDropTarget) ?? true
        iconsFollowCursor = try values.decodeIfPresent(Bool.self, forKey: .iconsFollowCursor) ?? true
        stackGrouping = try values.decodeIfPresent(StackGrouping.self, forKey: .stackGrouping) ?? .kind
        labelPosition = try values.decodeIfPresent(LabelPosition.self, forKey: .labelPosition) ?? .bottom
        showsItemInfo = try values.decodeIfPresent(Bool.self, forKey: .showsItemInfo) ?? false
        showsIconPreview = try values.decodeIfPresent(Bool.self, forKey: .showsIconPreview) ?? true
        showsHardDisks = try values.decodeIfPresent(Bool.self, forKey: .showsHardDisks) ?? false
        showsExternalDisks = try values.decodeIfPresent(Bool.self, forKey: .showsExternalDisks) ?? true
        showsRemovableMedia = try values.decodeIfPresent(Bool.self, forKey: .showsRemovableMedia) ?? true
        showsConnectedServers = try values.decodeIfPresent(Bool.self, forKey: .showsConnectedServers) ?? false
        springLoading = try values.decodeIfPresent(Bool.self, forKey: .springLoading) ?? true
        positions = try values.decodeIfPresent([String: CGPoint].self, forKey: .positions) ?? [:]
    }
}

/// What desktop stacks group by: Finder's Group Stacks By.
public enum StackGrouping: String, Codable, CaseIterable, Sendable {
    case kind, dateLastOpened, dateAdded, dateModified, dateCreated, tags

    /// Finder's value for it (`DesktopViewSettings`' `GroupBy`).
    public var finderValue: String {
        switch self {
        case .kind: "Kind"
        case .dateLastOpened: "Date Last Opened"
        case .dateAdded: "Date Added"
        case .dateModified: "Date Modified"
        case .dateCreated: "Date Created"
        case .tags: "Label"
        }
    }

    /// From Finder's `GroupBy`; nil for `None` or a grouping the desktop doesn't offer.
    public init?(finderValue: String) {
        guard let grouping = Self.allCases.first(where: { $0.finderValue == finderValue }) else { return nil }
        self = grouping
    }
}

/// Where icons' names go: Finder's Label Position.
public enum LabelPosition: String, Codable, CaseIterable, Sendable {
    case bottom, right
}

extension DesktopSettings {
    /// Wider than Finder's ranges (`FinderDesktopView`): Finder gets the closest value it accepts.
    public static let iconSides: ClosedRange<Double> = 16...256
    public static let gridSpacings: ClosedRange<Double> = 1...100
    public static let textSizes: ClosedRange<Double> = 9...24

    /// One grid cell: the icon, two lines of name (and the item info's line), and the grid spacing around
    /// them. Finder's own measure isn't published: names under the icons were matched on 2026-11-24 to
    /// Finder's desktop at 64 points and spacing 54 (about 112 points from one row to the next); names on
    /// the right take about ten characters of the text size beside the icon.
    public var cellSize: CGSize {
        let side = min(max(iconSide, Self.iconSides.lowerBound), Self.iconSides.upperBound)
        let spacing = min(max(gridSpacing, Self.gridSpacings.lowerBound), Self.gridSpacings.upperBound)
        let text = min(max(textSize, Self.textSizes.lowerBound), Self.textSizes.upperBound)
        let info = showsItemInfo ? (text * 1.25).rounded(.up) : 0
        switch labelPosition {
        case .bottom:
            return CGSize(width: max(side + spacing, side + 24, 72), height: side + 28 + info + spacing * 0.37)
        case .right:
            let label = max(text * 10, 96)
            let lines = (text * 1.25).rounded(.up) * 2 + info
            return CGSize(width: side + 12 + label + spacing * 0.5,
                          height: max(side + 8, lines + 8) + spacing * 0.37)
        }
    }
}

extension DesktopSettings {
    /// Desktop.app's defaults domain.
    public static let domain = "local.suite.desktop"
    public static let didChange = Notification.Name("DesktopSettingsDidChange")
    /// The key they are saved under.
    private static let key = "DesktopSettings"

    /// Whether the desktop's settings were ever saved: not before Bureau's first launch.
    public static var isSaved: Bool { defaults.object(forKey: key) != nil }

    /// Desktop.app's defaults, read and written from whichever app (Suite Settings writes them).
    public static var defaults: UserDefaults {
        Bundle.main.bundleIdentifier == domain ? .standard : UserDefaults(suiteName: domain) ?? .standard
    }
    /// Read once, then kept: the desktop reads them at every redraw.
    nonisolated(unsafe) private static var cached: DesktopSettings?

    /// The settings as saved; setting them saves them and posts `didChange`.
    public static var current: DesktopSettings {
        get {
            if let cached { return cached }
            let saved = defaults.data(forKey: key)
                .flatMap { try? JSONDecoder().decode(DesktopSettings.self, from: $0) } ?? DesktopSettings()
            cached = saved
            return saved
        }
        set {
            guard newValue != current else { return }
            cached = newValue
            defaults.set(try? JSONEncoder().encode(newValue), forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Takes the settings written in the defaults (a profile loaded, Suite Settings), applying them as a
    /// change would.
    public static func reloadFromDefaults() {
        CFPreferencesAppSynchronize(domain as CFString)
        let before = current
        cached = nil
        if current != before { NotificationCenter.default.post(name: didChange, object: nil) }
    }
}
