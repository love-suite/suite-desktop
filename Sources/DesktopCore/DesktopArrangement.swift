import CoreGraphics
import Foundation
import DesktopSettings
import SuiteFilesCore

/// What the desktop shows: a file, a stack of files grouped together, the items that didn't fit, or a disk.
public enum DesktopEntry: Equatable, Sendable {
    case item(FileItem)
    /// `kind`: the stack's group (`StackGroup.id`): the files' type when grouped by kind.
    case stack(kind: String, items: [FileItem])
    case overflow(items: [FileItem])
    /// A disk or server, as Finder shows them on the desktop.
    case volume(DesktopVolume)

    public static let overflowKey = "overflow"

    /// The key of the plain item with this file name.
    public static func itemKey(forName name: String) -> String { "item:" + name }

    /// The key of a disk or server, by where it is mounted.
    public static func volumeKey(for url: URL) -> String { "volume:" + url.path }

    public var key: String {
        switch self {
        case .item(let item): return Self.itemKey(forName: item.name)
        case .stack(let kind, _): return "stack:" + kind
        case .overflow: return Self.overflowKey
        case .volume(let volume): return Self.volumeKey(for: volume.url)
        }
    }

    /// Stacks show their count as a badge, not in the name; their group's id stands for their name here
    /// (the app names it in the Mac's language, `StackGroup`).
    public var name: String {
        switch self {
        case .item(let item): return item.name
        case .stack(let kind, _): return kind
        case .overflow: return "More Items"
        case .volume(let volume): return volume.item.name
        }
    }

    public var items: [FileItem] {
        switch self {
        case .item(let item): return [item]
        case .stack(_, let items), .overflow(let items): return items
        case .volume(let volume): return [volume.item]
        }
    }

    public var volume: DesktopVolume? {
        if case .volume(let volume) = self { return volume }
        return nil
    }
}

/// What a stack gathers, as Finder's Group Stacks By makes them: a type of file, a period of time (Today,
/// Yesterday, the previous 7 and 30 days, a month of this year, an earlier year), a tag.
public enum StackGroup: Hashable, Sendable {
    case kind(String)
    case folders
    case today, yesterday
    /// The previous 7 or 30 days.
    case previousDays(Int)
    /// A month of this year, 1 to 12.
    case month(Int)
    case year(Int)
    /// No date, or one in the future (Finder's "No Date").
    case noDate
    case tag(String)
    case noTags

    /// Kept in the stack's key (`DesktopEntry.stack(kind:)`): a type stack's is its type, as always.
    public var id: String {
        switch self {
        case .kind(let kind): return kind
        case .folders: return "Folders"
        case .today: return "date:today"
        case .yesterday: return "date:yesterday"
        case .previousDays(let days): return "date:previous:\(days)"
        case .month(let month): return "date:month:\(month)"
        case .year(let year): return "date:year:\(year)"
        case .noDate: return "date:none"
        case .tag(let tag): return "tag:" + tag
        case .noTags: return "tag:"
        }
    }

    public init(id: String) {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch (parts.first, parts.count) {
        case ("Folders", 1): self = .folders
        case ("date", 2) where parts[1] == "today": self = .today
        case ("date", 2) where parts[1] == "yesterday": self = .yesterday
        case ("date", 2) where parts[1] == "none": self = .noDate
        case ("date", 3) where parts[1] == "previous" && Int(parts[2]) != nil: self = .previousDays(Int(parts[2])!)
        case ("date", 3) where parts[1] == "month" && Int(parts[2]) != nil: self = .month(Int(parts[2])!)
        case ("date", 3) where parts[1] == "year" && Int(parts[2]) != nil: self = .year(Int(parts[2])!)
        case ("tag", _) where id == "tag:": self = .noTags
        case ("tag", _): self = .tag(String(id.dropFirst(4)))
        default: self = .kind(id)
        }
    }

    /// The period a date falls in, as Finder's date groups: Today, Yesterday, the previous 7 days, the
    /// previous 30 days, a month of this year, then a year.
    public static func period(of date: Date?, now: Date, calendar: Calendar = .current) -> StackGroup {
        guard let date, date <= now else { return .noDate }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return .today
        case 1: return .yesterday
        case ..<7: return .previousDays(7)
        case ..<30: return .previousDays(30)
        default:
            let year = calendar.component(.year, from: date)
            guard year == calendar.component(.year, from: now) else { return .year(year) }
            return .month(calendar.component(.month, from: date))
        }
    }
}

/// What grouping by date or tag reads that items don't carry: when each was last opened, its tags.
public struct StackFacts: Sendable {
    public var lastOpened: [URL: Date]
    public var tags: [URL: [String]]
    public var now: Date
    public var calendar: Calendar

    public init(lastOpened: [URL: Date] = [:], tags: [URL: [String]] = [:], now: Date = Date(),
                calendar: Calendar = .current) {
        self.lastOpened = lastOpened
        self.tags = tags
        self.now = now
        self.calendar = calendar
    }
}

public enum DesktopStacker {
    /// With `byKind`, every type of file present more than once becomes a stack; folders and aliases stay on
    /// their own, as Finder leaves them. Stacks come
    /// in the order of their first item, so they follow the sort order. An expanded stack (its key in
    /// `expanded`) stays in place, followed by its items, as on macOS.
    /// With `stacksFolders`, folders and aliases share a stack of their own instead.
    public static func entries(for items: [FileItem], byKind: Bool, stacksFolders: Bool = false,
                               expanded: Set<String> = []) -> [DesktopEntry] {
        guard byKind else { return items.map(DesktopEntry.item) }
        return entries(for: items, grouping: .kind, stacksFolders: stacksFolders, expanded: expanded)
    }

    /// Stacks by `grouping`, as Finder's Group Stacks By: as by kind, a group of one item shows the item, and
    /// folders and aliases stay on their own (or share the Folders stack). An item with several tags goes
    /// into the stack of its first one.
    public static func entries(for items: [FileItem], grouping: StackGrouping, stacksFolders: Bool = false,
                               expanded: Set<String> = [], facts: StackFacts = StackFacts()) -> [DesktopEntry] {
        let group = { (item: FileItem) in Self.group(of: item, by: grouping, stacksFolders: stacksFolders, facts: facts) }
        let groups = Dictionary(grouping: items, by: group)
        var seen = Set<String>()
        return items.flatMap { item -> [DesktopEntry] in
            let id = group(item)
            guard seen.insert(id).inserted, let members = groups[id] else { return [] }
            guard members.count > 1 else { return [.item(item)] }
            let stack = DesktopEntry.stack(kind: id, items: members)
            return expanded.contains(stack.key) ? [stack] + members.map(DesktopEntry.item) : [stack]
        }
    }

    /// Folders and aliases each keep a group of their own, so they are never stacked, or share the
    /// "Folders" stack with `stacksFolders`.
    private static func group(of item: FileItem, by grouping: StackGrouping, stacksFolders: Bool,
                              facts: StackFacts) -> String {
        guard !item.isFolder && !item.isAlias else {
            return stacksFolders ? StackGroup.folders.id : "item:" + item.url.path
        }
        let group: StackGroup
        switch grouping {
        case .kind: group = .kind(item.kind ?? "Documents")
        case .dateLastOpened: group = .period(of: facts.lastOpened[item.url], now: facts.now, calendar: facts.calendar)
        case .dateAdded: group = .period(of: item.added, now: facts.now, calendar: facts.calendar)
        case .dateModified: group = .period(of: item.modified, now: facts.now, calendar: facts.calendar)
        case .dateCreated: group = .period(of: item.created, now: facts.now, calendar: facts.calendar)
        case .tags: group = facts.tags[item.url]?.first.map(StackGroup.tag) ?? .noTags
        }
        return group.id
    }
}

/// The desktop grid. Cells are numbered column by column from the top-right, as Finder fills them, or from
/// the top-left, as Windows does (`fromRight` false).
public struct DesktopGrid: Sendable {
    public let cell: CGSize
    public let area: CGSize
    public let columns: Int
    public let rows: Int
    public let fromRight: Bool

    /// Cells no icon may take: under the desktop's widgets, which macOS draws above the icons.
    public let blockedCells: Set<Int>

    /// `blocked`: areas kept clear of icons (the widgets), from the top-left of `area`.
    public init(cell: CGSize, area: CGSize, fromRight: Bool = true, blocked: [CGRect] = []) {
        self.cell = cell
        self.area = area
        self.fromRight = fromRight
        let columns = max(1, Int(area.width / cell.width))
        let rows = max(1, Int(area.height / cell.height))
        self.columns = columns
        self.rows = rows
        var cells: Set<Int> = []
        if !blocked.isEmpty {
            for index in 0..<(columns * rows) {
                let column = index / rows
                let x = fromRight ? max(area.width - CGFloat(column + 1) * cell.width, 0) : CGFloat(column) * cell.width
                // A cell barely touched (a few points of its edge) stays free.
                let box = CGRect(x: x, y: CGFloat(index % rows) * cell.height, width: cell.width, height: cell.height)
                    .insetBy(dx: cell.width * 0.2, dy: cell.height * 0.2)
                if blocked.contains(where: { $0.intersects(box) }) { cells.insert(index) }
            }
        }
        blockedCells = cells
    }

    public var capacity: Int { columns * rows }
    /// The cells icons may take.
    public var freeCapacity: Int { capacity - blockedCells.count }

    public func origin(ofCell index: Int) -> CGPoint {
        CGPoint(x: x(ofColumn: index / rows), y: CGFloat(index % rows) * cell.height)
    }

    /// The left of a column: counted from the right edge when the grid starts there.
    private func x(ofColumn column: Int) -> CGFloat {
        fromRight ? max(area.width - CGFloat(column + 1) * cell.width, 0) : CGFloat(column) * cell.width
    }

    public func cellIndex(nearest point: CGPoint) -> Int {
        let fromLeft = Int((point.x / cell.width).rounded())
        let counted = fromRight ? Int(((area.width - cell.width - point.x) / cell.width).rounded()) : fromLeft
        let column = min(max(counted, 0), columns - 1)
        let row = min(max(Int((point.y / cell.height).rounded()), 0), rows - 1)
        return column * rows + row
    }

    /// The free cell closest to `point` (never one under a widget), or the nearest cell if every cell is taken.
    public func nearestFreeCell(to point: CGPoint, taken: Set<Int>) -> Int {
        let free = (0..<capacity).filter { !taken.contains($0) && !blockedCells.contains($0) }
        return free.min { distance(origin(ofCell: $0), point) < distance(origin(ofCell: $1), point) }
            ?? cellIndex(nearest: point)
    }

    /// Keeps a freely placed item fully inside the area.
    public func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), max(area.width - cell.width, 0)),
                y: min(max(point.y, 0), max(area.height - cell.height, 0)))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

public struct DesktopLayout: Equatable, Sendable {
    /// Where each shown entry goes, from the top-left of the usable area.
    public var positions: [String: CGPoint]
    /// Entries that didn't fit, in order: put in the overflow stack, or hidden.
    public var overflow: [String]
    /// The last cell, kept for the overflow stack when there is one.
    public var overflowPosition: CGPoint?
}

public enum DesktopArranger {
    /// Saved positions are kept (moved to the nearest free cell when the grid is on); entries without one
    /// fill the first free cells. When there are more entries than cells, the last ones don't fit; with
    /// `overflowStack`, the last cell is kept for the stack that collects them.
    public static func layout(for keys: [String], saved: [String: CGPoint], grid: DesktopGrid,
                              snapToGrid: Bool, overflowStack: Bool) -> DesktopLayout {
        let needsStack = overflowStack && keys.count > grid.freeCapacity
        // The stack takes the last cell no widget covers.
        let stackCell = (0..<grid.capacity).reversed().first { !grid.blockedCells.contains($0) } ?? grid.capacity - 1
        let slots = needsStack ? grid.freeCapacity - 1 : grid.freeCapacity
        var positions: [String: CGPoint] = [:]
        var taken: Set<Int> = grid.blockedCells
        if needsStack { taken.insert(stackCell) }

        for key in keys where positions.count < slots {
            guard let point = saved[key] else { continue }
            if snapToGrid || grid.blockedCells.contains(grid.cellIndex(nearest: point)) {
                // On the grid, or placed freely where a widget now is: the nearest free cell.
                let cell = grid.nearestFreeCell(to: point, taken: taken)
                positions[key] = grid.origin(ofCell: cell)
                taken.insert(cell)
            } else {
                positions[key] = grid.clamp(point)
                taken.insert(grid.cellIndex(nearest: point))
            }
        }
        var next = 0
        for key in keys where positions[key] == nil && positions.count < slots {
            while next < grid.capacity && taken.contains(next) { next += 1 }
            guard next < grid.capacity else { break }
            positions[key] = grid.origin(ofCell: next)
            taken.insert(next)
        }
        let overflow = keys.filter { positions[$0] == nil }
        return DesktopLayout(positions: positions, overflow: overflow,
                             overflowPosition: needsStack ? grid.origin(ofCell: stackCell) : nil)
    }

    /// Where dragged entries land, given where they started (`moving`) and how far they were dragged:
    /// the nearest free cells with the grid on, exactly where dropped with it off. The other entries in
    /// `positions` keep their places, as on Windows.
    public static func drop(_ moving: [String: CGPoint], by offset: CGSize, among positions: [String: CGPoint],
                            grid: DesktopGrid, snapToGrid: Bool) -> [String: CGPoint] {
        var result = positions
        // Top-left first, so a group dropped together keeps its arrangement.
        let ordered = moving.sorted { ($0.value.x, $0.value.y) < ($1.value.x, $1.value.y) }
        ordered.forEach { result[$0.key] = nil }
        var taken = Set(result.values.map { grid.cellIndex(nearest: $0) }).union(grid.blockedCells)
        for (key, origin) in ordered {
            let target = CGPoint(x: origin.x + offset.width, y: origin.y + offset.height)
            if snapToGrid || grid.blockedCells.contains(grid.cellIndex(nearest: target)) {
                let cell = grid.nearestFreeCell(to: target, taken: taken)
                result[key] = grid.origin(ofCell: cell)
                taken.insert(cell)
            } else {
                result[key] = grid.clamp(target)
            }
        }
        return result
    }
}
