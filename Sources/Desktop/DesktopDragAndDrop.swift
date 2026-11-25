import AppKit
import DesktopCore
import DesktopSettings
import SuiteFilesCore
import SuiteFilesUI

/// Drag and drop between the desktop and everything else. Moving icons around the desktop is handled
/// by the canvas itself; once the pointer reaches another window the drag becomes a system drag
/// session, so other apps (and Explorer windows) receive the files.
extension DesktopViewController: NSDraggingSource {
    struct FolderTarget {
        let key: String
        let url: URL
    }

    /// The folder icon under `point` (an alias to a folder counts, and a disk), skipping the items being
    /// dragged.
    func folderEntry(at point: NSPoint, excluding excluded: Set<String>) -> FolderTarget? {
        for entry in entries.reversed() where !excluded.contains(entry.key) && frame(of: entry.key).contains(point) {
            switch entry {
            case .volume(let volume): return FolderTarget(key: entry.key, url: volume.url)
            case .item(let item):
                guard let url = FileDrop.folderTarget(of: item) else { return nil }
                return FolderTarget(key: entry.key, url: url)
            default: return nil
            }
        }
        return nil
    }

    // MARK: Spring-loaded folders

    /// While dragging, a folder, disk or stack the pointer rests on opens after macOS's spring-loading
    /// delay, as on Finder's desktop: a folder in its window (where the drag goes on), a stack in place.
    func springLoad(over point: NSPoint, excluding excluded: Set<String>) {
        // macOS's settings, read once per drag.
        let system = springSettings ?? SpringLoading.system()
        springSettings = system
        guard desktop.springLoading, system.enabled else { return }
        let target = folderEntry(at: point, excluding: excluded)?.key ?? stackKey(at: point, excluding: excluded)
        guard springLoader.hover(target, at: Date()) else { return }
        springWork?.cancel()
        guard target != nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.springOpen() }
        springWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + system.delay, execute: work)
    }

    func endSpringLoading() {
        springWork?.cancel()
        springWork = nil
        springLoader.reset()
        springSettings = nil
    }

    /// A stack, folded, under the pointer: dragging onto it unfolds it.
    private func stackKey(at point: NSPoint, excluding excluded: Set<String>) -> String? {
        guard let entry = entries.last(where: { !excluded.contains($0.key) && frame(of: $0.key).contains(point) })
        else { return nil }
        switch entry {
        case .stack: return expandedStacks.contains(entry.key) ? nil : entry.key
        case .overflow: return entry.key
        default: return nil
        }
    }

    private func springOpen() {
        guard let key = springLoader.fire(at: Date(), delay: springSettings?.delay ?? 0),
              let entry = entries.first(where: { $0.key == key }) else { return }
        switch entry {
        case .stack: toggleStack(key)
        case .overflow(let items): showStack(items, from: key)
        case .item, .volume:
            guard let folder = folderEntry(at: NSPoint(x: frame(of: key).midX, y: frame(of: key).midY),
                                           excluding: []) else { return }
            FileViewer.openFolder(folder.url)
        }
    }

    func pointerIsOverAnotherWindow() -> Bool {
        let number = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
        return number != 0 && number != view.window?.windowNumber
    }

    /// Puts the icons back in place and lets macOS carry the files from here, drawn as the icons.
    func handOffToSystemDrag(_ event: NSEvent, at point: NSPoint) {
        // The images start where the icons are under the pointer by now, not where they came from.
        let moved = dragStart.map { CGSize(width: point.x - $0.x, height: point.y - $0.y) } ?? .zero
        sessionStart = dragStart
        sessionOrigins = dragOrigins
        let keys = Array(dragOrigins.keys)
        dragStart = nil
        dragOrigins = [:]
        isDragging = false
        pressedKey = nil
        canvas.dropTargets = []
        removeOriginGhosts()
        for key in keys {
            icons[key]?.view.frame = frame(of: key)
            icons[key]?.setGhost(false)
        }
        updateNameOverlay()

        let items: [NSDraggingItem] = keys.flatMap { key -> [NSDraggingItem] in
            guard let entry = entries.first(where: { $0.key == key }), let view = icons[key]?.view else { return [] }
            let image = Self.snapshot(of: view)
            return entry.items.map { item in
                let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
                dragItem.setDraggingFrame(view.frame.offsetBy(dx: moved.width, dy: moved.height),
                                          contents: DragGhost.faded(image))
                return dragItem
            }
        }
        guard !items.isEmpty else { return }
        // Their images are taken: the icons stay in place, faded, while the files travel.
        for key in keys { icons[key]?.setGhost(true) }
        canvas.beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : [.move, .copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        endSpringLoading()
        for key in sessionOrigins.keys { icons[key]?.setGhost(false) }
        sessionStart = nil
        sessionOrigins = [:]
        canvas.dropTargets = []
        // Files may have been moved away by the app that took them.
        reload()
    }

    static func snapshot(of view: NSView) -> NSImage {
        let image = NSImage(size: view.bounds.size)
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }

    // MARK: Dropping onto the desktop

    func canvasDragUpdated(_ info: NSDraggingInfo, at point: NSPoint) -> NSDragOperation {
        let fromDesktop = (info.draggingSource as AnyObject?) === self
        springLoad(over: point, excluding: fromDesktop ? Set(sessionOrigins.keys) : [])
        if let folder = folderEntry(at: point, excluding: fromDesktop ? Set(sessionOrigins.keys) : []) {
            canvas.dropTargets = [frame(of: folder.key)]
            return FileDrop.dragOperation(for: info, into: folder.url)
        }
        if fromDesktop {
            // Back over the desktop: the icons will just move, as with a drag that never left.
            if desktop.showDropTarget, let start = sessionStart {
                let offset = CGSize(width: point.x - start.x, height: point.y - start.y)
                let landing = DesktopArranger.drop(sessionOrigins, by: offset, among: positions, grid: grid,
                                                   snapToGrid: desktop.snapToGrid)
                canvas.dropTargets = sessionOrigins.keys.compactMap { landing[$0] }.map(cellFrame)
            }
            return .move
        }
        canvas.dropTargets = desktop.showDropTarget ? [cellFrame(grid.origin(ofCell: cell(under: point)))] : []
        return FileDrop.dragOperation(for: info, into: Self.desktopURL)
    }

    func canvasDragExited() {
        canvas.dropTargets = []
        endSpringLoading()
    }

    func canvasPerformDrop(_ info: NSDraggingInfo, at point: NSPoint) -> Bool {
        canvas.dropTargets = []
        endSpringLoading()
        let fromDesktop = (info.draggingSource as AnyObject?) === self
        if let folder = folderEntry(at: point, excluding: fromDesktop ? Set(sessionOrigins.keys) : []) {
            FileDrop.perform(info, into: folder.url)
            reload()
            return true
        }
        if fromDesktop, let start = sessionStart {
            let landing = DesktopArranger.drop(sessionOrigins, by: CGSize(width: point.x - start.x,
                                                                          height: point.y - start.y),
                                               among: positions, grid: grid, snapToGrid: desktop.snapToGrid)
            save(landing)
            return true
        }
        let added = FileDrop.perform(info, into: Self.desktopURL) { [weak self] received in
            // Files made at the drop (a picture from a browser, an item from Clipboard).
            self?.reload()
            self?.place(received, at: point)
        }
        reload()
        place(added, at: point)
        return !added.isEmpty || !FileDrop.promises(in: info).isEmpty
    }

    // MARK: Helpers

    func transfer(_ urls: [URL], into folder: URL, operation: TransferOperation) {
        FileDrop.transfer(urls, into: folder, operation: operation)
        reload()
    }

    /// New items land where they were dropped: the nearest free cells, or exactly there without the grid.
    private func place(_ urls: [URL], at point: NSPoint) {
        guard !urls.isEmpty, !stacksActive else { return }
        let keys = urls.map { DesktopEntry.itemKey(forName: $0.lastPathComponent) }
        // The reload already gave the new items a free cell somewhere; they belong at the drop point.
        var saved = positions.filter { !keys.contains($0.key) }
        var taken = Set(saved.values.map { grid.cellIndex(nearest: $0) })
        let anchor = CGPoint(x: point.x - usable.minX - grid.cell.width / 2,
                             y: point.y - usable.minY - grid.cell.height / 2)
        for (index, key) in keys.enumerated() {
            if desktop.snapToGrid {
                let cell = grid.nearestFreeCell(to: anchor, taken: taken)
                saved[key] = grid.origin(ofCell: cell)
                taken.insert(cell)
            } else {
                saved[key] = grid.clamp(CGPoint(x: anchor.x + CGFloat(index) * grid.cell.width, y: anchor.y))
            }
        }
        save(saved)
    }

    private func save(_ landing: [String: CGPoint]) {
        var saved = landing
        saved[DesktopEntry.overflowKey] = nil
        desktop.positions = saved
    }

    private func cell(under point: NSPoint) -> Int {
        grid.cellIndex(nearest: CGPoint(x: point.x - usable.minX - grid.cell.width / 2,
                                        y: point.y - usable.minY - grid.cell.height / 2))
    }

    private func cellFrame(_ position: CGPoint) -> NSRect {
        NSRect(origin: NSPoint(x: usable.minX + position.x, y: usable.minY + position.y), size: grid.cell)
    }
}
