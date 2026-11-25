import Foundation
import DesktopSettings

/// Which folder or stack a drag rests on, and when it springs open: once the pointer has stayed on the
/// same one for the delay. A target that already sprang open during the drag doesn't again.
public struct SpringLoader: Sendable {
    public private(set) var target: String?
    private var since: Date?
    private var sprung: Set<String> = []

    public init() {}

    /// The pointer is over `target` (nil: nothing that springs). Returns true when the target changed, so a
    /// new wait starts.
    @discardableResult
    public mutating func hover(_ target: String?, at date: Date) -> Bool {
        guard target != self.target else { return false }
        self.target = target
        since = target == nil ? nil : date
        return true
    }

    /// The target to open now, if the pointer has rested on it long enough.
    public mutating func fire(at date: Date, delay: TimeInterval) -> String? {
        guard let target, let since, date.timeIntervalSince(since) >= delay - 0.001,
              !sprung.contains(target) else { return nil }
        sprung.insert(target)
        return target
    }

    /// The drag ended.
    public mutating func reset() {
        self = SpringLoader()
    }
}
