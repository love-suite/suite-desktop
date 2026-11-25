import Foundation

/// macOS's spring-loading, which Finder follows: while dragging, a folder opens when the pointer rests on
/// it. Set in System Settings › Accessibility › Pointer Control, kept in the global domain
/// (`com.apple.springing.enabled`, `com.apple.springing.delay`, in seconds); on, half a second, unless set.
public struct SpringLoading: Equatable, Sendable {
    public var enabled = true
    public var delay: TimeInterval = 0.5

    public static let enabledKey = "com.apple.springing.enabled"
    public static let delayKey = "com.apple.springing.delay"

    public init(enabled: Bool = true, delay: TimeInterval = 0.5) {
        self.enabled = enabled
        self.delay = delay
    }

    /// From the global domain's values; what is missing keeps macOS's default.
    public init(global: [String: Any]) {
        if let value = (global[Self.enabledKey] as? NSNumber)?.boolValue { enabled = value }
        if let value = (global[Self.delayKey] as? NSNumber)?.doubleValue { delay = max(0, value) }
    }

    /// As set on this Mac (read only).
    public static func system() -> SpringLoading {
        let domain = kCFPreferencesAnyApplication
        CFPreferencesAppSynchronize(domain)
        var global: [String: Any] = [:]
        for key in [enabledKey, delayKey] {
            global[key] = CFPreferencesCopyAppValue(key as CFString, domain)
        }
        return SpringLoading(global: global)
    }
}
