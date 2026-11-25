import Foundation

/// What Suite Settings and Desktop.app say to each other, as distributed notifications.
public enum DesktopMessage: String, CaseIterable, Sendable {
    /// To the desktop: settings were written (the Desktop tab, a profile); read them again.
    case applySettings
    /// To the desktop, from a new copy started with `--relaunch` (after a build): reopen as for an
    /// update, keeping Finder's desktop hidden.
    case relaunch

    public var name: Notification.Name { Notification.Name("local.suite.desktop." + rawValue) }

    /// Delivered at once, even to an app in the background, which both often are.
    public func post(_ userInfo: [String: Any]? = nil) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: userInfo,
                                                                     deliverImmediately: true)
    }

    @discardableResult
    public func observe(_ handler: @escaping (Notification) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main, using: handler)
    }
}
