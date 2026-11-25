import AppKit
import SuiteFilesUI

protocol DesktopCanvasDelegate: AnyObject {
    func canvasMouseDown(_ event: NSEvent, at point: NSPoint)
    func canvasMouseDragged(_ event: NSEvent, at point: NSPoint)
    func canvasMouseUp(_ event: NSEvent, at point: NSPoint)
    func canvasMenu(at point: NSPoint) -> NSMenu?
    /// Returns true when the key was handled.
    func canvasKeyDown(_ event: NSEvent) -> Bool
    // Files dragged onto the desktop, from another app, a window or the desktop itself.
    func canvasDragUpdated(_ info: NSDraggingInfo, at point: NSPoint) -> NSDragOperation
    func canvasDragExited()
    func canvasPerformDrop(_ info: NSDraggingInfo, at point: NSPoint) -> Bool
}

/// The desktop surface: icons sit wherever they were put; every click is handled here.
final class DesktopCanvasView: NSView {
    weak var delegate: DesktopCanvasDelegate?

    /// The rubber-band rectangle drawn while dragging over the background.
    var selectionRect: NSRect? {
        didSet {
            band.isHidden = selectionRect == nil
            band.frame = selectionRect ?? .zero
        }
    }

    /// The cells dragged icons will land on, drawn behind the icons.
    var dropTargets: [NSRect] = [] {
        didSet {
            while targetViews.count < dropTargets.count {
                let view = NSView()
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).cgColor
                view.layer?.borderColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.7).cgColor
                view.layer?.borderWidth = 1.5
                view.layer?.cornerRadius = 8
                view.layer?.zPosition = -1
                addSubview(view)
                targetViews.append(view)
            }
            for (index, view) in targetViews.enumerated() {
                view.isHidden = index >= dropTargets.count
                if index < dropTargets.count { view.frame = dropTargets[index] }
            }
        }
    }

    private var targetViews: [NSView] = []

    private let band: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.2).cgColor
        view.layer?.borderColor = NSColor.selectedContentBackgroundColor.cgColor
        view.layer?.borderWidth = 1
        view.layer?.zPosition = 20
        view.isHidden = true
        return view
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Layer-backed so names and the rubber band can sit above the icons (zPosition).
        wantsLayer = true
        addSubview(band)
        registerForDraggedTypes(FileDrop.draggedTypes)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        delegate?.canvasDragUpdated(sender, at: convert(sender.draggingLocation, from: nil)) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        delegate?.canvasDragUpdated(sender, at: convert(sender.draggingLocation, from: nil)) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        delegate?.canvasDragExited()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        delegate?.canvasPerformDrop(sender, at: convert(sender.draggingLocation, from: nil)) ?? false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    /// Clicking the desktop while another app is in front acts at once, as on Windows.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Icons are drawn by subviews, but the canvas handles every click itself.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) { delegate?.canvasMouseDown(event, at: location(of: event)) }
    override func mouseDragged(with event: NSEvent) { delegate?.canvasMouseDragged(event, at: location(of: event)) }
    override func mouseUp(with event: NSEvent) { delegate?.canvasMouseUp(event, at: location(of: event)) }
    override func menu(for event: NSEvent) -> NSMenu? { delegate?.canvasMenu(at: location(of: event)) }

    override func keyDown(with event: NSEvent) {
        if delegate?.canvasKeyDown(event) != true { super.keyDown(with: event) }
    }

    private func location(of event: NSEvent) -> NSPoint {
        convert(event.locationInWindow, from: nil)
    }
}
