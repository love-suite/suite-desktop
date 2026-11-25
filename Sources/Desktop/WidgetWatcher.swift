import AppKit
import ApplicationServices

/// Tells when the desktop's widgets may have changed (added, moved, resized, removed), without looking
/// regularly. With the Accessibility permission, Notification Center, which draws them, reports its
/// windows' changes (checked on macOS 27). Until the permission is granted, a widget being always added,
/// moved or removed with the mouse, the mouse's release has them looked at. Nothing runs at rest.
@MainActor
final class WidgetWatcher {
    private let changed: () -> Void
    private var observer: (pid: pid_t, observer: AXObserver)?
    private var pending: DispatchWorkItem?
    private var monitor: Any?

    init(changed: @escaping () -> Void) {
        self.changed = changed
        // Asked at each launch until granted: the request also puts Bureau in System Settings › Privacy &
        // Security › Accessibility, where the user turns it on.
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        watchNotificationCenter()

        // Notification Center restarted, or the permission granted: watched again.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WidgetWatcher.shared?.watchNotificationCenter() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { WidgetWatcher.shared?.watchNotificationCenter() }
            }
        }
        WidgetWatcher.shared = self
    }

    nonisolated(unsafe) static weak var shared: WidgetWatcher?

    /// What is reported comes in bursts (a widget dragged moves its window many times): looked at once
    /// the burst is over.
    func soon(after delay: TimeInterval = 0.1) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Without the permission, the mouse's releases stand in for Notification Center's reports.
    private func watchMouse(_ watching: Bool) {
        if watching, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { _ in
                MainActor.assumeIsolated { WidgetWatcher.shared?.soon(after: 0.3) }
            }
        } else if !watching, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func watchNotificationCenter() {
        watchMouse(!AXIsProcessTrusted())
        guard AXIsProcessTrusted(),
              let centre = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first,
              observer?.pid != centre.processIdentifier else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer.observer), .defaultMode) }
        // Notification Center does report its widgets' windows moving (checked on macOS 27).
        let callback: AXObserverCallback = { _, _, _, _ in
            MainActor.assumeIsolated { WidgetWatcher.shared?.soon() }
        }
        var created: AXObserver?
        guard AXObserverCreate(centre.processIdentifier, callback, &created) == .success, let created else { return }
        let application = AXUIElementCreateApplication(centre.processIdentifier)
        for name in [kAXWindowCreatedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
                     kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(created, application, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = (centre.processIdentifier, created)
        soon()
    }
}
