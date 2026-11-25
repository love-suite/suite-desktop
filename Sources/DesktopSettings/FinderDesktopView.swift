import Foundation
import SuiteFilesCore

/// The desktop settings Bureau and Finder both have, as Finder keeps them: its View Options for the desktop
/// (`com.apple.finder`'s `DesktopViewSettings`) and the items its General settings show on the desktop
/// (`com.apple.finder`'s `Show*OnDesktop` keys). They are one value, synced both ways. The suite may go
/// beyond what Finder allows (larger icons, for instance): Finder then gets the closest value it accepts, so
/// a user going back to Finder's desktop finds it as near as possible to theirs.
public struct FinderDesktopView: Codable, Equatable, Sendable {
    /// Icon Size, 16 to 128.
    public var iconSize: Double = 64
    /// Grid Spacing, 1 to 100.
    public var gridSpacing: Double = 54
    /// Text Size, 10 to 16.
    public var textSize: Double = 12
    /// Sort By: `none`, `grid` (Snap to Grid), `name`, `kind`, `dateLastOpened`, `dateAdded`, `dateModified`,
    /// `dateCreated`, `size`, `label` (Tags).
    public var arrangeBy = "none"
    /// Use Stacks: `None`, or what stacks group by (`Kind`, a date, `Label`).
    public var groupBy = "None"
    /// Label Position: Bottom (true) or Right.
    public var labelOnBottom = true
    /// Show Item Info.
    public var showItemInfo = false
    /// Show Icon Preview.
    public var showIconPreview = true
    /// Settings › General › Show these items on the desktop, with Finder's defaults.
    public var showHardDrives = false
    public var showExternalHardDrives = true
    public var showRemovableMedia = true
    public var showMountedServers = false

    public enum Field: String, CaseIterable, Sendable {
        case iconSize, gridSpacing, textSize, arrangeBy, groupBy, labelOnBottom, showItemInfo, showIconPreview
        case showHardDrives, showExternalHardDrives, showRemovableMedia, showMountedServers

        /// Finder's key for the fields kept outside `DesktopViewSettings`, at the top of its defaults.
        public var finderKey: String? {
            switch self {
            case .showHardDrives: "ShowHardDrivesOnDesktop"
            case .showExternalHardDrives: "ShowExternalHardDrivesOnDesktop"
            case .showRemovableMedia: "ShowRemovableMediaOnDesktop"
            case .showMountedServers: "ShowMountedServersOnDesktop"
            default: nil
            }
        }
    }

    /// Finder's keys for the items shown on the desktop.
    public static let itemKeys = Field.allCases.compactMap(\.finderKey)

    public static let iconSizes: ClosedRange<Double> = 16...128
    public static let gridSpacings: ClosedRange<Double> = 1...100
    public static let textSizes: ClosedRange<Double> = 10...16

    public init() {}

    // A record saved before a field existed still decodes, with Finder's default.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FinderDesktopView()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try values.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        iconSize = try value(.iconSize, defaults.iconSize)
        gridSpacing = try value(.gridSpacing, defaults.gridSpacing)
        textSize = try value(.textSize, defaults.textSize)
        arrangeBy = try value(.arrangeBy, defaults.arrangeBy)
        groupBy = try value(.groupBy, defaults.groupBy)
        labelOnBottom = try value(.labelOnBottom, defaults.labelOnBottom)
        showItemInfo = try value(.showItemInfo, defaults.showItemInfo)
        showIconPreview = try value(.showIconPreview, defaults.showIconPreview)
        showHardDrives = try value(.showHardDrives, defaults.showHardDrives)
        showExternalHardDrives = try value(.showExternalHardDrives, defaults.showExternalHardDrives)
        showRemovableMedia = try value(.showRemovableMedia, defaults.showRemovableMedia)
        showMountedServers = try value(.showMountedServers, defaults.showMountedServers)
    }

    // MARK: Finder's dictionary

    /// Read from Finder's `DesktopViewSettings` and, in `items`, its `Show*OnDesktop` keys; what is missing
    /// keeps Finder's default.
    public init(finder view: [String: Any]?, items: [String: Any]? = nil) {
        let icons = view?["IconViewSettings"] as? [String: Any] ?? [:]
        if let value = (icons["iconSize"] as? NSNumber)?.doubleValue { iconSize = value }
        if let value = (icons["gridSpacing"] as? NSNumber)?.doubleValue { gridSpacing = value }
        if let value = (icons["textSize"] as? NSNumber)?.doubleValue { textSize = value }
        if let value = icons["arrangeBy"] as? String { arrangeBy = value }
        if let value = view?["GroupBy"] as? String { groupBy = value }
        if let value = (icons["labelOnBottom"] as? NSNumber)?.boolValue { labelOnBottom = value }
        if let value = (icons["showItemInfo"] as? NSNumber)?.boolValue { showItemInfo = value }
        if let value = (icons["showIconPreview"] as? NSNumber)?.boolValue { showIconPreview = value }
        for field in Field.allCases {
            guard let key = field.finderKey, let value = (items?[key] as? NSNumber)?.boolValue else { continue }
            setItem(field, value)
        }
    }

    /// The `Show*OnDesktop` keys with these values.
    public var items: [String: Bool] {
        Dictionary(uniqueKeysWithValues: Field.allCases.compactMap { field in
            field.finderKey.map { ($0, item(field)) }
        })
    }

    private func item(_ field: Field) -> Bool {
        switch field {
        case .showHardDrives: showHardDrives
        case .showExternalHardDrives: showExternalHardDrives
        case .showRemovableMedia: showRemovableMedia
        case .showMountedServers: showMountedServers
        default: false
        }
    }

    private mutating func setItem(_ field: Field, _ value: Bool) {
        switch field {
        case .showHardDrives: showHardDrives = value
        case .showExternalHardDrives: showExternalHardDrives = value
        case .showRemovableMedia: showRemovableMedia = value
        case .showMountedServers: showMountedServers = value
        default: break
        }
    }

    /// Finder's `DesktopViewSettings` with these values, every other key it holds kept as it was.
    public func written(into view: [String: Any]?) -> [String: Any] {
        var view = view ?? [:]
        var icons = view["IconViewSettings"] as? [String: Any] ?? [:]
        icons["iconSize"] = iconSize
        icons["gridSpacing"] = gridSpacing
        icons["textSize"] = textSize
        icons["arrangeBy"] = arrangeBy
        icons["labelOnBottom"] = labelOnBottom
        icons["showItemInfo"] = showItemInfo
        icons["showIconPreview"] = showIconPreview
        view["IconViewSettings"] = icons
        view["GroupBy"] = groupBy
        return view
    }

    // MARK: Bureau's settings

    /// The closest Finder can come to Bureau's settings and the desktop's sort order.
    public init(approximating settings: DesktopSettings, sortKey: SortKey, ascending: Bool) {
        iconSize = Self.clamp(settings.iconSide, to: Self.iconSizes).rounded()
        gridSpacing = Self.clamp(settings.gridSpacing, to: Self.gridSpacings).rounded()
        textSize = Self.clamp(settings.textSize, to: Self.textSizes).rounded()
        if settings.keepArranged {
            arrangeBy = Self.arrangeBy[sortKey] ?? "name"
        } else {
            arrangeBy = settings.snapToGrid ? "grid" : "none"
        }
        groupBy = settings.stacks ? settings.stackGrouping.finderValue : "None"
        labelOnBottom = settings.labelPosition == .bottom
        showItemInfo = settings.showsItemInfo
        showIconPreview = settings.showsIconPreview
        showHardDrives = settings.showsHardDisks
        showExternalHardDrives = settings.showsExternalDisks
        showRemovableMedia = settings.showsRemovableMedia
        showMountedServers = settings.showsConnectedServers
    }

    /// The fields where Finder can't hold Bureau's value exactly: what the banner over Finder's settings
    /// shows.
    public static func approximated(_ settings: DesktopSettings, sortKey: SortKey) -> [Field] {
        var fields: [Field] = []
        if !iconSizes.contains(settings.iconSide) || settings.iconSide != settings.iconSide.rounded() { fields.append(.iconSize) }
        if !gridSpacings.contains(settings.gridSpacing) || settings.gridSpacing != settings.gridSpacing.rounded() { fields.append(.gridSpacing) }
        if !textSizes.contains(settings.textSize) || settings.textSize != settings.textSize.rounded() { fields.append(.textSize) }
        if settings.keepArranged && arrangeBy[sortKey] == nil { fields.append(.arrangeBy) }
        return fields
    }

    /// Bureau's settings with the given fields taken from Finder; the others stay as they were. Returns the
    /// sort order too when Sort By was taken.
    public func adopt(_ fields: Set<Field>, into settings: inout DesktopSettings) -> (key: SortKey, ascending: Bool)? {
        var sort: (key: SortKey, ascending: Bool)?
        for field in fields {
            switch field {
            case .iconSize: settings.iconSide = iconSize
            case .gridSpacing: settings.gridSpacing = gridSpacing
            case .textSize: settings.textSize = textSize
            case .groupBy:
                // Finder's other groupings (Application, Size, Name) aren't offered for stacks: by kind.
                settings.stacks = groupBy != "None"
                if settings.stacks { settings.stackGrouping = StackGrouping(finderValue: groupBy) ?? .kind }
            case .labelOnBottom: settings.labelPosition = labelOnBottom ? .bottom : .right
            case .showItemInfo: settings.showsItemInfo = showItemInfo
            case .showIconPreview: settings.showsIconPreview = showIconPreview
            case .showHardDrives: settings.showsHardDisks = showHardDrives
            case .showExternalHardDrives: settings.showsExternalDisks = showExternalHardDrives
            case .showRemovableMedia: settings.showsRemovableMedia = showRemovableMedia
            case .showMountedServers: settings.showsConnectedServers = showMountedServers
            case .arrangeBy:
                let arrangement = Self.arrangement(arrangeBy)
                settings.snapToGrid = arrangement.snap
                settings.keepArranged = arrangement.sort != nil
                sort = arrangement.sort
            }
        }
        return sort
    }

    /// Finder's Sort By: None (placed by hand), Snap to Grid, or a sort order kept on the desktop; dates and
    /// sizes put the newest and largest first, as Finder does. Date Last Opened and Tags, which Bureau
    /// doesn't sort by yet, fall back to Date Added and Name.
    public static func arrangement(_ arrangeBy: String) -> (snap: Bool, sort: (key: SortKey, ascending: Bool)?) {
        switch arrangeBy {
        case "grid": return (true, nil)
        case "name", "label": return (true, (.name, true))
        case "kind": return (true, (.kind, true))
        case "size": return (true, (.size, false))
        case "dateModified": return (true, (.modified, false))
        case "dateCreated": return (true, (.created, false))
        case "dateAdded", "dateLastOpened": return (true, (.added, false))
        default: return (false, nil)
        }
    }

    private static let arrangeBy: [SortKey: String] = [
        .name: "name", .kind: "kind", .size: "size", .modified: "dateModified", .created: "dateCreated",
        .added: "dateAdded",
    ]

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: Fields

    public func value(_ field: Field) -> String {
        switch field {
        case .iconSize: String(iconSize)
        case .gridSpacing: String(gridSpacing)
        case .textSize: String(textSize)
        case .arrangeBy: arrangeBy
        case .groupBy: groupBy
        case .labelOnBottom: String(labelOnBottom)
        case .showItemInfo: String(showItemInfo)
        case .showIconPreview: String(showIconPreview)
        case .showHardDrives, .showExternalHardDrives, .showRemovableMedia, .showMountedServers: String(item(field))
        }
    }

    public mutating func take(_ field: Field, from other: FinderDesktopView) {
        switch field {
        case .iconSize: iconSize = other.iconSize
        case .gridSpacing: gridSpacing = other.gridSpacing
        case .textSize: textSize = other.textSize
        case .arrangeBy: arrangeBy = other.arrangeBy
        case .groupBy: groupBy = other.groupBy
        case .labelOnBottom: labelOnBottom = other.labelOnBottom
        case .showItemInfo: showItemInfo = other.showItemInfo
        case .showIconPreview: showIconPreview = other.showIconPreview
        case .showHardDrives, .showExternalHardDrives, .showRemovableMedia, .showMountedServers:
            setItem(field, other.item(field))
        }
    }
}
