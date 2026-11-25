import AppKit
import CoreGraphics

final class DesktopWindow: NSWindow {
    // Borderless windows refuse key status by default; we need it for selection and keyboard.
    override var canBecomeKey: Bool { true }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        isMovable = false
        // Setting this explicitly stops clicks on see-through areas from falling to the wallpaper (which activates Finder).
        ignoresMouseEvents = false
        contentViewController = DesktopViewController()
        // Assigning the content view controller shrinks the window to the view's (empty) size.
        setFrame(screen.frame, display: true)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let screen = self.screen ?? NSScreen.main else { return }
            self.setFrame(screen.frame, display: true)
        }
    }
}
