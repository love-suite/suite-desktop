import AppKit
import DesktopSettings
import DesktopCore
import Quartz
import SuiteCore
import SuiteFilesCore
import SuiteFilesUI

/// The desktop: icons placed freely or on a grid, optionally stacked, like the Windows desktop.
final class DesktopViewController: NSViewController {
    static let desktopURL =
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

    let canvas = DesktopCanvasView()
    var typeSelect = TypeSelect()
    let nameOverlay = FullNameOverlay()
    let quickLook = QuickLook()
    var watcher: DirectoryWatcher?
    var popover: NSPopover?

    var items: [FileItem] = []
    /// The disks and servers mounted, shown as Finder's settings say (`DesktopVolume.shown`).
    var volumes: [DesktopVolume] = []
    /// While dragging, the folder or stack the pointer rests on, which springs open (`SpringLoading`).
    var springLoader = SpringLoader()
    var springWork: DispatchWorkItem?
    var springSettings: SpringLoading?
    /// Sort order, shared with Explorer windows showing the Desktop folder.
    var sortOptions = FolderViewOptions()
    /// Grid, icon size, stacks and saved positions, shared with the settings window (saved on change).
    var desktop: DesktopSettings {
        get { DesktopSettings.current }
        set { DesktopSettings.current = newValue }
    }

    var entries: [DesktopEntry] = []
    /// Where each entry is, from the top-left of the usable area.
    var positions: [String: CGPoint] = [:]
    var icons: [String: IconItemView] = [:]
    var selection = Set<String>()
    /// Stacks opened in place by a click.
    var expandedStacks = Set<String>()
    var grid = DesktopGrid(cell: DesktopSettings().cellSize, area: .zero)
    /// The screen minus the menu bar and the Dock, in canvas coordinates.
    var usable = NSRect.zero
    /// The desktop's widgets, in canvas coordinates: icons keep clear of them, as Finder's do.
    var widgetAreas: [CGRect] = []
    private var widgetWatcher: WidgetWatcher?

    // A click or drag in progress.
    var pressedKey: String?
    var dragStart: NSPoint?
    var dragOrigins: [String: CGPoint] = [:]
    var isDragging = false
    /// Faded copies left where the icons moving under the pointer came from.
    var originGhosts: [NSView] = []
    var bandStart: NSPoint?
    var bandBase = Set<String>()
    // A drag handed over to macOS once the pointer left the desktop for another window.
    var sessionStart: NSPoint?
    var sessionOrigins: [String: CGPoint] = [:]

    // MARK: Lifecycle

    override func loadView() {
        canvas.delegate = self
        view = canvas
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let center = NotificationCenter.default
        center.addObserver(forName: DisplaySettings.didChange, object: nil, queue: .main) { [weak self] _ in
            // Thumbnails on or off, full names, hidden files: the desktop is read and drawn again.
            self?.reload()
        }
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                           queue: .main) { [weak self] _ in self?.layoutEntries() }
        for name in [IconPickerWindow.didChange, FileUndo.didChange] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reload() }
        }
        center.addObserver(forName: FolderViewStore.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.reloadSortOptions()
        }
        sortOptions = FolderViewStore.shared.options(for: Self.desktopURL)
        center.addObserver(forName: DesktopSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.layoutEntries()
        }
        // Disks and servers come and go (and are renamed) at once, as on Finder's desktop.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reloadVolumes() }
        }
        volumes = DesktopVolume.mounted()
        reload()
        // The icons make room when the widgets change.
        widgetWatcher = WidgetWatcher { [weak self] in self?.updateWidgetAreas() }
        updateWidgetAreas()
        watcher = DirectoryWatcher(url: Self.desktopURL) { [weak self] in
            DispatchQueue.main.async { self?.reload() }
        }
        watcher?.start()
    }

    /// Layout passes happen all the time (even mid-drag, when labels are added); only a new size matters.
    var laidOutSize = NSSize.zero

    override func viewDidLayout() {
        super.viewDidLayout()
        guard canvas.bounds.size != laidOutSize else { return }
        laidOutSize = canvas.bounds.size
        layoutEntries()
    }

    // MARK: Contents and layout

    func reload() {
        let loaded = (try? DirectoryLoader.load(Self.desktopURL, showHidden: DisplaySettings.showsHiddenFiles)) ?? []
        items = FileSorter.sorted(loaded, by: sortOptions.sortKey, ascending: sortOptions.ascending,
                                  foldersFirst: desktop.foldersFirst.sorts(finder: DisplaySettings.finderSortsFoldersFirstOnDesktop))
        layoutEntries()
    }

    func reloadVolumes() {
        let mounted = DesktopVolume.mounted()
        guard mounted != volumes else { return }
        volumes = mounted
        layoutEntries()
    }

    /// Picks up a sort order changed in an Explorer window showing the Desktop folder.
    func reloadSortOptions() {
        let stored = FolderViewStore.shared.options(for: Self.desktopURL)
        guard stored != sortOptions else { return }
        sortOptions = stored
        reload()
    }

    /// With `unfoldingFrom`, icons slide to their new places and newly shown ones fly out of that frame
    /// (a stack being unfolded), as macOS animates stacks.
    /// With `animated`, icons slide to their new places (Clean Up).
    func layoutEntries(unfoldingFrom origin: NSRect? = nil, animated: Bool = false) {
        updateUsableArea()
        let settings = desktop
        let side = CGFloat(settings.iconSide)
        grid = DesktopGrid(cell: settings.cellSize, area: usable.size, fromRight: settings.startsAtRight,
                           blocked: widgetAreas.map { $0.offsetBy(dx: -usable.minX, dy: -usable.minY) })
        // Disks and servers first: they take the first cells, the top-right corner, as on Finder's desktop.
        let all = DesktopVolume.shown(volumes, settings: settings).map(DesktopEntry.volume) + stackedEntries()
        // As on macOS, stacks and Keep Arranged keep the desktop in sort order: saved positions don't apply.
        let layout = DesktopArranger.layout(for: all.map(\.key), saved: isArranged ? [:] : desktop.positions,
                                            grid: grid, snapToGrid: desktop.snapToGrid,
                                            overflowStack: desktop.overflowStack)
        let overflow = Set(layout.overflow)
        entries = all.filter { !overflow.contains($0.key) }
        positions = layout.positions
        if let stackPosition = layout.overflowPosition {
            let extra = all.filter { overflow.contains($0.key) }.flatMap(\.items)
            entries.append(.overflow(items: extra))
            positions[DesktopEntry.overflowKey] = stackPosition
        }
        let keys = entries.map(\.key)
        selection.formIntersection(keys)

        for (key, icon) in icons where !keys.contains(key) {
            icon.view.removeFromSuperview()
            icons[key] = nil
        }
        var moves: [(NSView, NSRect)] = []
        for entry in entries {
            let isNew = icons[entry.key] == nil
            let icon = icons[entry.key] ?? makeIcon()
            icon.iconSide = side
            icon.nameSize = CGFloat(settings.textSize)
            icon.boldName = settings.boldNames
            icon.labelOnRight = settings.labelPosition == .right
            icon.showsPreview = settings.showsIconPreview
            switch entry {
            case .item(let item):
                icon.configure(with: item)
            case .volume(let volume):
                icon.configure(with: volume.item)
            case .stack(_, let items), .overflow(let items):
                icon.configure(name: displayName(of: entry),
                               image: StackIcon.image(for: items.map(\.url), side: side,
                                                      expanded: expandedStacks.contains(entry.key)),
                               count: nil)
            }
            if settings.showsItemInfo { showInfo(of: entry, on: icon) }
            let target = frame(of: entry.key)
            if let origin {
                if isNew { icon.view.frame = origin }
                moves.append((icon.view, target))
            } else if animated && !isNew {
                moves.append((icon.view, target))
            } else {
                icon.view.frame = target
            }
            icon.isSelected = selection.contains(entry.key)
            icons[entry.key] = icon
        }
        if !moves.isEmpty {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                moves.forEach { view, target in view.animator().frame = target }
            }
        }
        updateNameOverlay()
    }

    /// The entries from the files: stacked as Group Stacks By says while stacks are on.
    func stackedEntries() -> [DesktopEntry] {
        guard stacksActive else { return items.map(DesktopEntry.item) }
        let grouping = desktop.stackGrouping
        let facts = FileFacts.read(for: items, lastOpened: grouping == .dateLastOpened, tags: grouping == .tags)
        return DesktopStacker.entries(for: items, grouping: grouping, stacksFolders: desktop.stacksFolders,
                                      expanded: expandedStacks, facts: facts)
    }

    /// The name shown under an entry: stacks are named after their group in the Mac's language.
    func displayName(of entry: DesktopEntry) -> String {
        switch entry {
        case .item(let item): return DisplaySettings.name(of: item)
        case .stack(let id, _): return StackNames.name(of: StackGroup(id: id))
        case .overflow: return L("More Items")
        case .volume(let volume): return volume.item.name
        }
    }

    func makeIcon() -> IconItemView {
        let icon = IconItemView()
        icon.onDesktop = true
        canvas.addSubview(icon.view)
        return icon
    }

    func updateWidgetAreas() {
        guard let screen = view.window?.screen ?? NSScreen.main else { return }
        let areas = DesktopWidgets.areas(on: screen)
        guard areas != widgetAreas else { return }
        widgetAreas = areas
        layoutEntries()
    }

    /// The window covers the whole screen, but icons stay clear of the menu bar and the Dock.
    func updateUsableArea() {
        guard let screen = view.window?.screen ?? NSScreen.main else { return }
        let full = screen.frame
        let visible = screen.visibleFrame
        let margin: CGFloat = 8
        usable = NSRect(x: visible.minX - full.minX + margin, y: full.maxY - visible.maxY + margin,
                        width: visible.width - 2 * margin, height: visible.height - 2 * margin)
    }

    func frame(of key: String) -> NSRect {
        let position = positions[key] ?? .zero
        return NSRect(origin: NSPoint(x: usable.minX + position.x, y: usable.minY + position.y),
                      size: grid.cell)
    }

    func key(at point: NSPoint) -> String? {
        entries.last { frame(of: $0.key).contains(point) }?.key
    }

    func applySelection() {
        for (key, icon) in icons { icon.isSelected = selection.contains(key) }
        quickLook.urls = selectedItems.map(\.url)
        updateNameOverlay()
    }

    func updateNameOverlay() {
        let cells = entries.filter { selection.contains($0.key) }.map { entry -> (String, NSRect) in
            (displayName(of: entry), frame(of: entry.key))
        }
        // Names on the right have the room of the cell: the overlay is for names under the icons.
        let shown = isDragging || desktop.labelPosition == .right ? [] : cells
        nameOverlay.update(in: canvas, cells: shown, iconSide: CGFloat(desktop.iconSide))
    }

    // MARK: Opening

    /// Folders, and shortcuts to folders, open in our own Explorer window; files and apps open as usual.
    static func open(_ item: FileItem) {
        if item.isFolder {
            FileViewer.openFolder(item.url)
        } else if let target = ShortcutResolver.folderTarget(of: item.url) {
            FileViewer.openFolder(target)
        } else {
            FileActions.openFile(item.url)
        }
    }

    func open(_ key: String) {
        guard let entry = entries.first(where: { $0.key == key }) else { return }
        switch entry {
        case .item(let item): Self.open(item)
        case .volume(let volume): Self.open(volume.item)
        case .stack: toggleStack(key)
        // There is no room to unfold the overflow stack, so it opens in a popover.
        case .overflow(let items): showStack(items, from: key)
        }
    }

    /// A type stack unfolds in place, its items flying out right after it; clicking it again gathers them
    /// back into the stack and the icons after it close the gap.
    func toggleStack(_ key: String) {
        let stackFrame = frame(of: key)
        guard expandedStacks.contains(key) else {
            expandedStacks.insert(key)
            layoutEntries(unfoldingFrom: stackFrame)
            return
        }
        let members = (entries.first { $0.key == key }?.items ?? []).map { DesktopEntry.itemKey(forName: $0.name) }
        let views = members.compactMap { icons[$0]?.view }
        expandedStacks.remove(key)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            views.forEach { $0.animator().frame = stackFrame }
        }, completionHandler: { [weak self] in
            self?.layoutEntries(unfoldingFrom: stackFrame)
        })
    }

    func isTypeStack(_ key: String) -> Bool {
        if case .stack = entries.first(where: { $0.key == key }) { return true }
        return false
    }

    func showStack(_ items: [FileItem], from key: String) {
        guard let anchor = icons[key]?.view else { return }
        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = StackViewController(items: items) { [weak popover] item in
            popover?.close()
            Self.open(item)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        self.popover = popover
    }

    var selectedEntries: [DesktopEntry] {
        entries.filter { selection.contains($0.key) }
    }

    var selectedItems: [FileItem] {
        selectedEntries.flatMap(\.items)
    }

    /// The selected files, without the disks and servers: what is copied, moved, trashed or compressed.
    var selectedFiles: [FileItem] {
        selectedEntries.filter { $0.volume == nil }.flatMap(\.items)
    }

    var selectedVolumes: [DesktopVolume] {
        selectedEntries.compactMap(\.volume)
    }
}

// MARK: - Clicks, dragging and rubber-band selection

extension DesktopViewController: DesktopCanvasDelegate {
    func canvasMouseDown(_ event: NSEvent, at point: NSPoint) {
        view.window?.makeFirstResponder(canvas)
        let key = key(at: point)
        let modifiers = event.modifierFlags
        if event.clickCount == 2, let key {
            // A single click already unfolded or folded a type stack.
            if !isTypeStack(key) { open(key) }
            return
        }
        pressedKey = key
        if let key {
            if modifiers.contains(.command) {
                selection.formSymmetricDifference([key])
            } else if modifiers.contains(.shift) {
                selection.insert(key)
            } else if !selection.contains(key) {
                selection = [key]
            }
            // Kept arranged (stacks, Keep Arranged), as on macOS, icons can't be moved.
            if !isArranged {
                dragStart = point
                // The overflow stack always sits in the last cell.
                dragOrigins = positions.filter { selection.contains($0.key) && $0.key != DesktopEntry.overflowKey }
            }
        } else {
            if !modifiers.contains(.command) && !modifiers.contains(.shift) { selection = [] }
            bandStart = point
            bandBase = selection
        }
        applySelection()
    }

    func canvasMouseDragged(_ event: NSEvent, at point: NSPoint) {
        if let start = dragStart {
            let offset = CGSize(width: point.x - start.x, height: point.y - start.y)
            guard isDragging || hypot(offset.width, offset.height) > 3 else { return }
            isDragging = true
            if pointerIsOverAnotherWindow() {
                handOffToSystemDrag(event, at: point)
                return
            }
            if desktop.iconsFollowCursor {
                if originGhosts.isEmpty { showOriginGhosts() }
                for (key, origin) in dragOrigins {
                    icons[key]?.view.setFrameOrigin(NSPoint(x: usable.minX + origin.x + offset.width,
                                                            y: usable.minY + origin.y + offset.height))
                }
            } else {
                for key in dragOrigins.keys { icons[key]?.setGhost(true) }
            }
            springLoad(over: point, excluding: Set(dragOrigins.keys))
            if let folder = folderEntry(at: point, excluding: Set(dragOrigins.keys)) {
                // Over a folder: dropping puts the items inside it.
                canvas.dropTargets = [frame(of: folder.key)]
            } else if desktop.showDropTarget {
                let landing = dropPositions(for: offset)
                canvas.dropTargets = dragOrigins.keys.compactMap { landing[$0] }.map {
                    NSRect(origin: NSPoint(x: usable.minX + $0.x, y: usable.minY + $0.y), size: grid.cell)
                }
            } else {
                canvas.dropTargets = []
            }
            updateNameOverlay()
        } else if let start = bandStart {
            let band = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                              width: abs(point.x - start.x), height: abs(point.y - start.y))
            canvas.selectionRect = band
            let hit = Set(entries.map(\.key).filter { frame(of: $0).intersects(band) })
            selection = event.modifierFlags.contains(.command)
                ? bandBase.symmetricDifference(hit) : bandBase.union(hit)
            applySelection()
        }
    }

    func canvasMouseUp(_ event: NSEvent, at point: NSPoint) {
        if let start = dragStart, isDragging {
            if let folder = folderEntry(at: point, excluding: Set(dragOrigins.keys)) {
                // Disks stay where they are mounted: only files go into the folder.
                let urls = entries.filter { dragOrigins.keys.contains($0.key) && $0.volume == nil }
                    .flatMap(\.items).map(\.url)
                let operation = FileTransfer.defaultOperation(for: urls, into: folder.url,
                                                              forceCopy: event.modifierFlags.contains(.option))
                transfer(urls, into: folder.url, operation: operation)
                layoutEntries()
            } else {
                moveSelection(by: CGSize(width: point.x - start.x, height: point.y - start.y))
            }
        } else if let key = pressedKey, event.modifierFlags.intersection([.command, .shift]).isEmpty {
            // A plain click inside a multiple selection keeps just the clicked item.
            selection = [key]
            applySelection()
            if isTypeStack(key) { toggleStack(key) }
        }
        for key in dragOrigins.keys { icons[key]?.setGhost(false) }
        removeOriginGhosts()
        endSpringLoading()
        pressedKey = nil
        dragStart = nil
        dragOrigins = [:]
        isDragging = false
        bandStart = nil
        canvas.selectionRect = nil
        canvas.dropTargets = []
        updateNameOverlay()
    }

    /// As in Windows, the icons stay where they were, faded, while they show through under the pointer.
    func showOriginGhosts() {
        for key in dragOrigins.keys {
            guard let icon = icons[key] else { continue }
            let ghost = NSImageView(frame: icon.view.frame)
            ghost.image = DragGhost.faded(Self.snapshot(of: icon.view), alpha: DragGhost.alpha)
            ghost.imageScaling = .scaleNone
            canvas.addSubview(ghost, positioned: .below, relativeTo: icon.view)
            originGhosts.append(ghost)
            icon.setContentAlpha(DragGhost.imageAlpha)
        }
    }

    func removeOriginGhosts() {
        originGhosts.forEach { $0.removeFromSuperview() }
        originGhosts = []
    }

    /// The same calculation drives the drop-target preview and the drop itself. The overflow stack's
    /// cell counts as taken.
    func dropPositions(for offset: CGSize) -> [String: CGPoint] {
        DesktopArranger.drop(dragOrigins, by: offset, among: positions, grid: grid,
                             snapToGrid: desktop.snapToGrid)
    }

    func moveSelection(by offset: CGSize) {
        var saved = dropPositions(for: offset)
        saved[DesktopEntry.overflowKey] = nil
        desktop.positions = saved
        isDragging = false
        layoutEntries()
    }

    func canvasKeyDown(_ event: NSEvent) -> Bool {
        if handleFileKey(event) { return true }
        if let direction = Self.arrowDirection(event) {
            moveSelection(toward: direction)
            return true
        }
        if let text = FileKeys.typedText(event) {
            let typed = typeSelect.add(text)
            if let index = TypeSelect.match(typed, in: entries.map(displayName(of:))) {
                selection = [entries[index].key]
                applySelection()
            }
            return true
        }
        return false
    }

    private static func arrowDirection(_ event: NSEvent) -> CGVector? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch event.keyCode {
        case 123: return CGVector(dx: -1, dy: 0)
        case 124: return CGVector(dx: 1, dy: 0)
        case 125: return CGVector(dx: 0, dy: 1)   // the canvas is flipped: down is +y
        case 126: return CGVector(dx: 0, dy: -1)
        default: return nil
        }
    }

    /// Arrows select the nearest icon that way, as on the Windows desktop.
    private func moveSelection(toward direction: CGVector) {
        guard let current = entries.last(where: { selection.contains($0.key) }) else {
            if let first = entries.first { selection = [first.key]; applySelection() }
            return
        }
        let from = frame(of: current.key)
        let origin = CGPoint(x: from.midX, y: from.midY)
        let candidates = entries.filter { $0.key != current.key }.compactMap { entry -> (String, CGFloat)? in
            let to = frame(of: entry.key)
            let dx = to.midX - origin.x, dy = to.midY - origin.y
            let along = dx * direction.dx + dy * direction.dy
            guard along > 1 else { return nil }
            let across = abs(dx * direction.dy - dy * direction.dx)
            return (entry.key, along + across * 2)
        }
        guard let next = candidates.min(by: { $0.1 < $1.1 }) else { return }
        selection = [next.0]
        applySelection()
    }

    func canvasMenu(at point: NSPoint) -> NSMenu? {
        let key = key(at: point)
        if let key, !selection.contains(key) {
            selection = [key]
        } else if key == nil {
            selection = []
        }
        applySelection()
        return makeMenu(onItem: key != nil)
    }
}

// MARK: - View options: icon size, grid, stacks, sort order

extension DesktopViewController: NSMenuItemValidation {
    /// Same selectors as Explorer windows, so the View menu reaches the desktop through the responder chain.
    fileprivate static let sortItems: [(String, Selector)] = [
        ("Name", #selector(sortByName(_:))), ("Type", #selector(sortByKind(_:))),
        ("Date Added", #selector(sortByDateAdded(_:))), ("Date Modified", #selector(sortByDate(_:))),
        ("Date Created", #selector(sortByDateCreated(_:))), ("Size", #selector(sortBySize(_:))),
    ]
    static let sortKeys: [Selector: SortKey] = [
        #selector(sortByName(_:)): .name, #selector(sortByDate(_:)): .modified,
        #selector(sortBySize(_:)): .size, #selector(sortByKind(_:)): .kind,
        #selector(sortByDateAdded(_:)): .added, #selector(sortByDateCreated(_:)): .created,
    ]
    /// Three steps of Finder's Icon Size slider; any other size comes from Finder or Suite Settings.
    fileprivate static let sizeItems: [(String, Double)] = [
        ("Large Icons", 96), ("Medium Icons", 64), ("Small Icons", 40),
    ]

    @objc func sortByName(_ sender: Any?) { sort(by: .name) }
    @objc func sortByDate(_ sender: Any?) { sort(by: .modified) }
    @objc func sortBySize(_ sender: Any?) { sort(by: .size) }
    @objc func sortByKind(_ sender: Any?) { sort(by: .kind) }
    @objc func sortByDateAdded(_ sender: Any?) { sort(by: .added) }
    @objc func sortByDateCreated(_ sender: Any?) { sort(by: .created) }

    /// Like Windows, sorting rearranges every icon in the new order.
    func sort(by key: SortKey) {
        sortOptions.sort(by: key)
        FolderViewStore.shared.save(sortOptions, for: Self.desktopURL)
        desktop.positions = [:]
        reload()
    }

    @objc fileprivate func setIconSize(_ sender: NSMenuItem) {
        guard let side = sender.representedObject as? Double else { return }
        desktop.iconSide = side
        layoutEntries()
    }

    @objc fileprivate func toggleSnapToGrid(_ sender: Any?) {
        desktop.snapToGrid.toggle()
        if desktop.snapToGrid {
            // Line everything up on the grid now, and remember it there.
            layoutEntries()
            desktop.positions = positions.filter { $0.key != DesktopEntry.overflowKey }
        }
        layoutEntries()
    }

    /// Stacks group by type, as Finder's do, whatever the sort order inside them; or only while sorted by
    /// type (a setting).
    var stacksActive: Bool {
        desktop.stacks && (!desktop.stacksOnlyWhenSortedByType || sortOptions.sortKey == .kind)
    }

    /// The desktop in sort order, icons not placed by hand: with stacks, or Keep Arranged.
    var isArranged: Bool { stacksActive || desktop.keepArranged }

    @objc fileprivate func toggleKeepArranged(_ sender: Any?) {
        desktop.keepArranged.toggle()
        layoutEntries()
    }

    @objc func toggleStacks(_ sender: Any?) {
        desktop.stacks.toggle()
        layoutEntries()
    }

    @objc fileprivate func toggleShowDropTarget(_ sender: Any?) {
        desktop.showDropTarget.toggle()
    }

    @objc fileprivate func toggleIconsFollowCursor(_ sender: Any?) {
        desktop.iconsFollowCursor.toggle()
    }

    @objc fileprivate func toggleOverflowStack(_ sender: Any?) {
        desktop.overflowStack.toggle()
        layoutEntries()
    }

    /// Group Stacks By: the grouping is the item's represented object (`StackGrouping`'s raw value).
    @objc func groupStacks(_ sender: NSMenuItem) {
        guard let grouping = (sender.representedObject as? String).flatMap(StackGrouping.init(rawValue:)) else { return }
        expandedStacks = []
        desktop.stackGrouping = grouping
        layoutEntries()
    }

    /// Clean Up: every icon to the nearest free cell of the grid, as Finder's Clean Up.
    @objc func cleanUp(_ sender: Any?) {
        guard !isArranged else { return }
        let keys = entries.map(\.key).filter { $0 != DesktopEntry.overflowKey }
        let layout = DesktopArranger.layout(for: keys, saved: positions, grid: grid, snapToGrid: true,
                                            overflowStack: desktop.overflowStack)
        desktop.positions = layout.positions
        layoutEntries(animated: true)
    }

    /// Clean Up By: the icons lined up once in that order from the first cell, disks first; the sort order
    /// and the arrangement don't change (the represented object is `CleanUpKey`'s raw value).
    @objc func cleanUpBy(_ sender: NSMenuItem) {
        guard !isArranged, let key = (sender.representedObject as? String).flatMap(CleanUpKey.init(rawValue:))
        else { return }
        let files = entries.compactMap { entry -> FileItem? in
            if case .item(let item) = entry { return item }
            return nil
        }
        let facts = FileFacts.read(for: files, lastOpened: key == .dateLastOpened, tags: key == .tags)
        let foldersFirst = desktop.foldersFirst.sorts(finder: DisplaySettings.finderSortsFoldersFirstOnDesktop)
        let ordered = DesktopCleanUp.ordered(files, by: key, foldersFirst: foldersFirst, facts: facts)
        let keys = entries.compactMap { $0.volume.map { DesktopEntry.volumeKey(for: $0.url) } }
            + ordered.map { DesktopEntry.itemKey(forName: $0.name) }
        let layout = DesktopArranger.layout(for: keys, saved: [:], grid: grid, snapToGrid: true,
                                            overflowStack: desktop.overflowStack)
        desktop.positions = layout.positions
        layoutEntries(animated: true)
    }

    @objc func setLabelPosition(_ sender: NSMenuItem) {
        guard let position = (sender.representedObject as? String).flatMap(LabelPosition.init(rawValue:)) else { return }
        desktop.labelPosition = position
        layoutEntries()
    }

    @objc func toggleItemInfo(_ sender: Any?) {
        desktop.showsItemInfo.toggle()
        layoutEntries()
    }

    @objc func toggleIconPreview(_ sender: Any?) {
        desktop.showsIconPreview.toggle()
        layoutEntries()
    }

    /// Eject: the selected disks and servers, as Finder's File › Eject (Command-E).
    @objc func eject(_ sender: Any?) {
        let volumes = selectedVolumes.filter(\.canEject)
        guard !volumes.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for volume in volumes {
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
                } catch {
                    let message = String(format: L("The disk “%@” wasn’t ejected."), volume.item.name)
                    DispatchQueue.main.async {
                        self?.showError(message + " " + error.localizedDescription)
                    }
                }
            }
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let enabled = validateFileCommand(item) { return enabled }
        updateSortItem(item)
        switch item.action {
        case #selector(eject(_:)):
            return selectedVolumes.contains(where: \.canEject)
        case #selector(cleanUp(_:)), #selector(cleanUpBy(_:)):
            return !isArranged
        case #selector(groupStacks(_:)):
            item.state = desktop.stackGrouping.rawValue == item.representedObject as? String ? .on : .off
            return desktop.stacks
        case #selector(setLabelPosition(_:)):
            item.state = desktop.labelPosition.rawValue == item.representedObject as? String ? .on : .off
        case #selector(toggleItemInfo(_:)):
            item.state = desktop.showsItemInfo ? .on : .off
        case #selector(toggleIconPreview(_:)):
            item.state = desktop.showsIconPreview ? .on : .off
        case #selector(toggleStacks(_:)):
            item.state = desktop.stacks ? .on : .off
        default: break
        }
        return true
    }

    /// Checks the current sort key and shows its direction; choosing it again reverses it.
    fileprivate func updateSortItem(_ item: NSMenuItem) {
        guard let action = item.action, let key = Self.sortKeys[action] else { return }
        let current = key == sortOptions.sortKey
        item.state = current ? .on : .off
        let title = item.title.replacingOccurrences(of: " ↑", with: "").replacingOccurrences(of: " ↓", with: "")
        item.title = title + (current ? (sortOptions.ascending ? " ↑" : " ↓") : "")
    }
}

// MARK: - Context menu

extension DesktopViewController {
    func makeMenu(onItem: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if onItem, selectedFiles.isEmpty, !selectedVolumes.isEmpty {
            // Disks and servers, as Finder's menu for them: Open, Eject, Properties.
            menu.addItem(item("Open", #selector(openSelected)))
            menu.addItem(.separator())
            let volumes = selectedVolumes
            let eject = item("Eject", #selector(eject(_:)))
            if volumes.count == 1 { eject.title = String(format: L("Eject “%@”"), volumes[0].item.name) }
            eject.isEnabled = volumes.contains(where: \.canEject)
            menu.addItem(eject)
            menu.addItem(.separator())
            menu.addItem(item("Properties", #selector(propertiesOfSelection)))
        } else if onItem {
            menu.addItem(item("Open", #selector(openSelected)))
            if selectedItems.count == 1, let file = selectedItems.first, !file.isFolder {
                menu.addItem(openWithItem(for: file.url))
            }
            menu.addItem(.separator())
            menu.addItem(item("Cut", #selector(cutSelected)))
            menu.addItem(item("Copy", #selector(copySelected)))
            let rename = item("Rename", #selector(renameSelected))
            let single = selectedEntries.count == 1
            rename.isEnabled = single && { if case .item = selectedEntries[0] { true } else { false } }()
            menu.addItem(rename)
            menu.addItem(.separator())
            menu.addItem(item("Move to Trash", #selector(trashSelected)))
            menu.addItem(.separator())
            if selectedItems.count == 1, let only = selectedItems.first, Archiver.isArchive(only.url) {
                menu.addItem(item("Extract All", #selector(extractSelected)))
            }
            menu.addItem(item(selectedItems.count == 1 ? "Compress “\(selectedItems[0].name)”"
                                                       : "Compress \(selectedItems.count) Items",
                              #selector(compressSelected)))
            menu.addItem(.separator())
            menu.addItem(item("Quick Look", #selector(quickLookSelected)))
            menu.addItem(item("Change Icon", #selector(changeIcon(_:))))
            menu.addItem(item("Properties", #selector(propertiesOfSelection)))
        } else {
            menu.addItem(submenu("View", viewMenuItems()))
            menu.addItem(submenu("Sort By", Self.sortItems.map { title, action in
                let sortItem = item(title, action)
                updateSortItem(sortItem)
                return sortItem
            }))
            if sortOptions.sortKey == .kind {
                let stacks = item("Use Stacks", #selector(toggleStacks(_:)))
                stacks.state = desktop.stacks ? .on : .off
                stacks.toolTip = "Groups items of the same type."
                menu.addItem(stacks)
            }
            if desktop.stacks {
                menu.addItem(submenu("Group Stacks By", groupStacksItems()))
            }
            // Finder's Clean Up and Clean Up By, while icons are placed by hand.
            let cleanUp = item("Clean Up", #selector(cleanUp(_:)))
            cleanUp.isEnabled = !isArranged
            menu.addItem(cleanUp)
            let cleanUpBy = submenu("Clean Up By", cleanUpByItems())
            cleanUpBy.isEnabled = !isArranged
            menu.addItem(cleanUpBy)
            let overflow = item("Overflow Stack", #selector(toggleOverflowStack(_:)))
            overflow.state = desktop.overflowStack ? .on : .off
            overflow.toolTip = "When the desktop is full, the items that don't fit go into one stack. "
                + "Turned off, they are hidden."
            menu.addItem(overflow)
            menu.addItem(.separator())
            menu.addItem(submenu("New", [item("Folder", #selector(newFolder(_:))),
                                         item("Text File", #selector(newTextFile)),
                                         item("Markdown File", #selector(newMarkdownFile))]))
            let paste = item("Paste", #selector(pasteHere))
            paste.isEnabled = FileClipboard.canPaste
            menu.addItem(paste)
            menu.addItem(.separator())
            menu.addItem(item("Desktop Settings", #selector(showSettings(_:))))
            menu.addItem(item("Display Settings", #selector(openDisplaySettings)))
            menu.addItem(item("Change Wallpaper", #selector(openWallpaperSettings)))
        }
        return menu
    }

    func viewMenuItems() -> [NSMenuItem] {
        var items = Self.sizeItems.map { title, size in
            let sizeItem = item(title, #selector(setIconSize(_:)))
            sizeItem.representedObject = size
            sizeItem.state = desktop.iconSide == size ? .on : .off
            return sizeItem
        }
        items.append(.separator())
        let snap = item("Align Icons to Grid", #selector(toggleSnapToGrid(_:)))
        snap.state = desktop.snapToGrid ? .on : .off
        items.append(snap)
        let arranged = item("Keep Arranged", #selector(toggleKeepArranged(_:)))
        arranged.state = desktop.keepArranged ? .on : .off
        items.append(arranged)
        items.append(.separator())
        let target = item("Show Drop Target", #selector(toggleShowDropTarget(_:)))
        target.state = desktop.showDropTarget ? .on : .off
        items.append(target)
        let follow = item("Move Icons While Dragging", #selector(toggleIconsFollowCursor(_:)))
        follow.state = desktop.iconsFollowCursor ? .on : .off
        items.append(follow)
        items.append(.separator())
        items.append(submenu("Label Position", labelPositionItems()))
        let info = item("Show Item Info", #selector(toggleItemInfo(_:)))
        info.state = desktop.showsItemInfo ? .on : .off
        items.append(info)
        let preview = item("Show Icon Preview", #selector(toggleIconPreview(_:)))
        preview.state = desktop.showsIconPreview ? .on : .off
        items.append(preview)
        return items
    }

    /// Finder's Group Stacks By, in its order. `target` nil: through the responder chain (the menu bar).
    static let groupStacksTitles: [(String, StackGrouping)] = [
        ("Kind", .kind), ("Date Last Opened", .dateLastOpened), ("Date Added", .dateAdded),
        ("Date Modified", .dateModified), ("Date Created", .dateCreated), ("Tags", .tags),
    ]

    /// Finder's Clean Up By, in its order.
    static let cleanUpTitles: [(String, CleanUpKey)] = [
        ("Name", .name), ("Kind", .kind), ("Date Last Opened", .dateLastOpened), ("Date Added", .dateAdded),
        ("Date Modified", .dateModified), ("Date Created", .dateCreated), ("Size", .size), ("Tags", .tags),
    ]

    static let labelPositionTitles: [(String, LabelPosition)] = [("Bottom", .bottom), ("Right", .right)]

    func groupStacksItems() -> [NSMenuItem] {
        Self.groupStacksTitles.map { title, grouping in
            let entry = item(title, #selector(groupStacks(_:)))
            entry.representedObject = grouping.rawValue
            entry.state = desktop.stackGrouping == grouping ? .on : .off
            return entry
        }
    }

    func cleanUpByItems() -> [NSMenuItem] {
        Self.cleanUpTitles.map { title, key in
            let entry = item(title, #selector(cleanUpBy(_:)))
            entry.representedObject = key.rawValue
            return entry
        }
    }

    func labelPositionItems() -> [NSMenuItem] {
        Self.labelPositionTitles.map { title, position in
            let entry = item(title, #selector(setLabelPosition(_:)))
            entry.representedObject = position.rawValue
            entry.state = desktop.labelPosition == position ? .on : .off
            return entry
        }
    }

    func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: NSLocalizedString(title, comment: ""), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: NSLocalizedString(title, comment: ""), action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc func quickLookSelected() {
        if !QuickLook.isVisible { QuickLook.toggle() }
    }

    @objc func propertiesOfSelection() {
        PropertiesWindow.show(selectedItems.map(\.url))
    }

    // File › Properties and File › Quick Look, through the responder chain.
    @objc func changeIcon(_ sender: Any?) {
        IconPickerWindow.show(for: selectedItems.map(\.url))
    }

    @objc func showProperties(_ sender: Any?) {
        PropertiesWindow.show(selectedItems.map(\.url))
    }

    @objc func toggleQuickLook(_ sender: Any?) {
        QuickLook.toggle()
    }

    @objc func showSettings(_ sender: Any?) {
        SuiteSettingsApp.show(tab: "Desktop")
    }

    // Windows' "Display settings" and "Personalize": the matching System Settings panes.
    @objc func openDisplaySettings() {
        openSystemSettings("com.apple.Displays-Settings.extension")
    }

    @objc func openWallpaperSettings() {
        openSystemSettings("com.apple.Wallpaper-Settings.extension")
    }

    func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:" + pane) {
            NSWorkspace.shared.open(url)
        }
    }

    // Quick Look asks the responder chain who supplies the items.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        quickLook.urls = selectedItems.map(\.url)
        quickLook.take(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }

    @objc func openSelected() {
        selectedEntries.forEach { open($0.key) }
    }

    @objc func cutSelected() { handle(.cut) }
    @objc func copySelected() { handle(.copy) }
    @objc func pasteHere() { handle(.paste) }
    @objc func trashSelected() { handle(.moveToTrash) }
    @objc func renameSelected() { beginInlineRename() }

    @objc func compressSelected() {
        if let archive = FileActions.compress(selectedFiles.map(\.url)) { showChanges(selecting: [archive]) }
    }

    @objc func extractSelected() {
        guard let archive = selectedFiles.first?.url, let folder = FileActions.extract(archive) else { return }
        showChanges(selecting: [folder])
    }

    /// Open With: the apps that can open the file, the default first, then Other….
    func openWithItem(for url: URL) -> NSMenuItem {
        let submenu = NSMenu()
        for app in FileActions.applications(toOpen: url) {
            let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
            let entry = NSMenuItem(title: name, action: #selector(MenuAction.run), keyEquivalent: "")
            entry.image = NSWorkspace.shared.icon(forFile: app.path)
            entry.image?.size = NSSize(width: 16, height: 16)
            entry.target = MenuAction.shared
            entry.representedObject = { FileActions.open([url], with: app) } as () -> Void
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        let other = NSMenuItem(title: "Other", action: #selector(MenuAction.run), keyEquivalent: "")
        other.target = MenuAction.shared
        other.representedObject = { FileActions.chooseApplication(for: [url]) } as () -> Void
        submenu.addItem(other)
        let openWith = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        openWith.submenu = submenu
        return openWith
    }

    // The File menu's actions, while the desktop is in front.
    @objc func newFolder(_ sender: Any?) { handle(.newFolder) }
    @objc func openSelection(_ sender: Any?) { openSelected() }
    @objc func renameSelection(_ sender: Any?) { beginInlineRename() }
    @objc func moveToTrash(_ sender: Any?) { handle(.moveToTrash) }

    // The Edit menu.
    @objc func copy(_ sender: Any?) { handle(.copy) }
    @objc func cut(_ sender: Any?) { handle(.cut) }
    @objc func paste(_ sender: Any?) { handle(.paste) }
    @objc func pasteMoving(_ sender: Any?) { handle(.pasteMoving) }
    @objc func undo(_ sender: Any?) { handle(.undo) }
    @objc func redo(_ sender: Any?) { handle(.redo) }
    @objc override func selectAll(_ sender: Any?) { selectAllCommand() }

    @objc func newTextFile() { createFile(.text) }
    @objc func newMarkdownFile() { createFile(.markdown) }

    /// Like Explorer: a new file is created with a default name, then renamed in place.
    func createFile(_ template: FileTemplate) {
        guard let created = FileActions.create(template, in: Self.desktopURL) else { return }
        showChanges(selecting: [created])
        beginInlineRename()
    }

    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            showError(error.localizedDescription)
        }
        reload()
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - Keyboard and Edit menu commands, shared with Explorer windows

extension DesktopViewController: FileCommandHandling {
    /// Disks and servers aren't copied, moved or trashed from the desktop: they are ejected.
    var commandSelection: [URL] { selectedFiles.map(\.url) }
    var commandFolder: URL? { Self.desktopURL }

    func openCommandSelection() { openSelected() }
    func goUpCommand() {}

    func selectAllCommand() {
        selection = Set(entries.map(\.key))
        applySelection()
    }

    func showChanges(selecting urls: [URL]) {
        reload()
        guard !urls.isEmpty else { return }
        let keys = Set(urls.map { DesktopEntry.itemKey(forName: $0.lastPathComponent) })
        selection = Set(entries.map(\.key).filter(keys.contains))
        applySelection()
    }

    /// F2: a field over the icon's name; the icon keeps its place under the new name.
    func beginInlineRename() {
        guard selectedEntries.count == 1, case .item(let item) = selectedEntries[0] else { return }
        let key = selectedEntries[0].key
        let cell = frame(of: key)
        let rect: NSRect
        if desktop.labelPosition == .right, let name = icons[key]?.nameView {
            // Over the name, from where it starts on the icon's right to the cell's end.
            let shown = canvas.convert(name.frame, from: name.superview)
            rect = NSRect(x: shown.minX - 2, y: shown.minY, width: cell.maxX - shown.minX + 10, height: 20)
        } else {
            let top = cell.minY + IconItemView.nameTop(iconSide: CGFloat(desktop.iconSide))
            rect = NSRect(x: cell.minX - 10, y: top, width: cell.width + 20, height: 20)
        }
        nameOverlay.update(in: canvas, cells: [], iconSide: CGFloat(desktop.iconSide))
        let hiding = icons[key].map { [$0.nameView] } ?? []
        let showsExtension = DisplaySettings.showsFileExtensions
        InlineRenamer.begin(in: canvas, over: rect, name: item.displayName(showingExtension: showsExtension),
                            font: .systemFont(ofSize: 12), hiding: hiding, wraps: true) { [weak self] name in
            guard let self else { return }
            guard let name, let renamed = FileActions.rename(item.url, to: item.fullName(
                fromEdited: name, showingExtension: showsExtension)) else {
                self.updateNameOverlay()
                return
            }
            let newKey = DesktopEntry.itemKey(forName: renamed.lastPathComponent)
            if let position = self.positions[key] { self.desktop.positions[newKey] = position }
            self.showChanges(selecting: [renamed])
        }
    }
}

/// The desktop's widgets, as macOS draws them: windows of Notification Center just above the desktop's
/// icons (Finder moves its icons out of their way). Read from the Window Server, on any Space.
enum DesktopWidgets {
    static func areas(on screen: NSScreen) -> [CGRect] {
        let centres = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")
            .map(\.processIdentifier)
        guard !centres.isEmpty else { return [] }
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        // The screen's frame in the Window Server's coordinates (top-left origin), where windows are given.
        let frame = CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY,
                           width: screen.frame.width, height: screen.frame.height)
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, centres.contains(owner),
                  let layer = info[kCGWindowLayer as String] as? Int, layer > iconLevel, layer < iconLevel + 10,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0) }),
                  frame.intersects(bounds), bounds.width < frame.width else { return nil }
            // In the canvas (the window covers the screen, flipped): from the screen's top-left.
            return bounds.offsetBy(dx: -frame.minX, dy: -frame.minY)
        }.sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
    }
}
