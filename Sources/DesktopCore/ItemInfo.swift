import CoreServices
import Foundation
import ImageIO
import SuiteFilesCore
import UniformTypeIdentifiers

/// Finder's Show Item Info: the second line under a name, for the items that have one: a folder's number of
/// items, a picture's size in pixels, a disk's capacity and free space, the length of a song or a movie.
public enum ItemInfo: Equatable, Sendable {
    case items(Int)
    case pixels(width: Int, height: Int)
    case capacity(total: Int64, available: Int64)
    case duration(TimeInterval)

    /// Read from the file (in the background: folders are counted, pictures opened); nil when Finder shows
    /// none. Hidden items count only when they are shown.
    public static func read(for item: FileItem, countingHidden: Bool = false) -> ItemInfo? {
        if item.isFolder {
            let options: FileManager.DirectoryEnumerationOptions = countingHidden ? [] : [.skipsHiddenFiles]
            let contents = try? FileManager.default.contentsOfDirectory(at: item.url, includingPropertiesForKeys: nil,
                                                                        options: options)
            return contents.map { .items($0.count) }
        }
        guard !item.isAlias, let type = UTType(filenameExtension: item.url.pathExtension) else { return nil }
        if type.conforms(to: .image) {
            guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
            // Pictures turned by their orientation (5 to 8) show their width and height swapped, as Finder does.
            let turned = ((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1) >= 5
            return turned ? .pixels(width: height, height: width) : .pixels(width: width, height: height)
        }
        if type.conforms(to: .audiovisualContent) {
            guard let metadata = MDItemCreateWithURL(nil, item.url as CFURL),
                  let seconds = MDItemCopyAttribute(metadata, kMDItemDurationSeconds) as? NSNumber else { return nil }
            return .duration(seconds.doubleValue)
        }
        return nil
    }

    /// A length as Finder writes it: minutes and seconds, hours first when there are some (`1:02:03`).
    public static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest)
                         : String(format: "%02d:%02d", minutes, rest)
    }
}
