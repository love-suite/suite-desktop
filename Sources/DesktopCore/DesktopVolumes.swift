import Foundation
import DesktopSettings
import SuiteFilesCore

/// A disk or server on the desktop, as Finder shows them there (Settings › General › Show these items on
/// the desktop).
public struct DesktopVolume: Equatable, Sendable {
    /// Finder's four kinds of items on the desktop.
    public enum Kind: Int, Comparable, Sendable {
        /// The Mac's own disks: Hard disks.
        case hardDisk
        /// Disks plugged in, disk images: External disks.
        case externalDisk
        /// Media that come out of their drive (CDs, DVDs, SD cards) and iPods: CDs, DVDs and iPods.
        case removableMedia
        /// Network volumes: Connected servers.
        case server

        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        /// How Finder tells them apart, from the volume's resource values: a volume not on this Mac is a
        /// server; removable media come next; then a disk not inside the Mac (or that can be ejected, when
        /// macOS doesn't say) is external.
        public static func of(isLocal: Bool?, isInternal: Bool?, isRemovable: Bool?, isEjectable: Bool?) -> Kind {
            if isLocal == false { return .server }
            if isRemovable == true { return .removableMedia }
            if let isInternal { return isInternal ? .hardDisk : .externalDisk }
            return isEjectable == true ? .externalDisk : .hardDisk
        }
    }

    /// The volume as a folder, named as Finder names it (the volume's localized name).
    public let item: FileItem
    public let kind: Kind
    /// The startup disk, which can't be ejected.
    public let isStartup: Bool
    /// Capacity and free space, in bytes, for the item info.
    public let capacity: Int64?
    public let available: Int64?

    public init(item: FileItem, kind: Kind, isStartup: Bool = false, capacity: Int64? = nil, available: Int64? = nil) {
        self.item = item
        self.kind = kind
        self.isStartup = isStartup
        self.capacity = capacity
        self.available = available
    }

    public var url: URL { item.url }
    public var canEject: Bool { !isStartup }

    /// Whether Finder's settings, as the desktop holds them, show this kind.
    public static func shows(_ kind: Kind, in settings: DesktopSettings) -> Bool {
        switch kind {
        case .hardDisk: settings.showsHardDisks
        case .externalDisk: settings.showsExternalDisks
        case .removableMedia: settings.showsRemovableMedia
        case .server: settings.showsConnectedServers
        }
    }

    /// The volumes the settings show, in Finder's order: the startup disk first, then hard disks, external
    /// disks, removable media and servers, each by name. They come before the files, so they take the first
    /// cells (the top-right corner, as Finder puts them).
    public static func shown(_ volumes: [DesktopVolume], settings: DesktopSettings) -> [DesktopVolume] {
        volumes.filter { shows($0.kind, in: settings) }.sorted { a, b in
            if a.isStartup != b.isStartup { return a.isStartup }
            if a.kind != b.kind { return a.kind < b.kind }
            return a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
        }
    }

    private static let keys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsRemovableKey,
        .volumeIsEjectableKey, .volumeIsBrowsableKey, .volumeIsRootFileSystemKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .localizedTypeDescriptionKey,
    ]

    /// The volumes mounted on this Mac that Finder would show (read only): hidden and system volumes
    /// left out.
    public static func mounted() -> [DesktopVolume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable != false
            else { return nil }
            let name = values.volumeLocalizedName ?? FileManager.default.displayName(atPath: url.path)
            let item = FileItem(url: url, name: name, isDirectory: true, isPackage: false, size: nil, modified: nil,
                                isHidden: false, kind: values.localizedTypeDescription)
            let kind = Kind.of(isLocal: values.volumeIsLocal, isInternal: values.volumeIsInternal,
                               isRemovable: values.volumeIsRemovable, isEjectable: values.volumeIsEjectable)
            return DesktopVolume(item: item, kind: kind, isStartup: values.volumeIsRootFileSystem == true,
                                 capacity: values.volumeTotalCapacity.map(Int64.init),
                                 // Free space as Finder counts it: purgeable space included.
                                 available: values.volumeAvailableCapacityForImportantUsage)
        }
    }
}
