import AppKit
import DesktopCore
import SuiteFilesCore
import SuiteFilesUI

/// Finder's Show Item Info on the desktop: the blue line under the names, read in the background
/// (`ItemInfo`) and kept for each version of a file.
extension DesktopViewController {
    func showInfo(of entry: DesktopEntry, on icon: IconItemView) {
        switch entry {
        case .volume(let volume):
            if let total = volume.capacity, let available = volume.available {
                icon.info = ItemInfoText.text(.capacity(total: total, available: available))
            }
        case .stack(_, let items), .overflow(let items):
            icon.info = ItemInfoText.text(.items(items.count))
        case .item(let item):
            let key = entry.key
            ItemInfoCache.shared.info(for: item, countingHidden: DisplaySettings.showsHiddenFiles) { [weak self] info in
                // The icon may show something else by now.
                guard let self, self.desktop.showsItemInfo, let shown = self.icons[key],
                      case .item(let current)? = self.entries.first(where: { $0.key == key }),
                      current.url == item.url else { return }
                shown.info = info.map(ItemInfoText.text)
            }
        }
    }
}

/// The item info read once per version of a file (its modification date), off the main thread.
final class ItemInfoCache {
    static let shared = ItemInfoCache()

    private struct Key: Hashable {
        let path: String
        let modified: Date?
        let countingHidden: Bool
    }

    private var known: [Key: ItemInfo?] = [:]
    private var waiting: [Key: [(ItemInfo?) -> Void]] = [:]
    private let queue = DispatchQueue(label: "local.suite.desktop.item-info", qos: .utility)

    /// `completion` runs on the main thread, at once when the info is known.
    func info(for item: FileItem, countingHidden: Bool, completion: @escaping (ItemInfo?) -> Void) {
        let key = Key(path: item.url.path, modified: item.modified, countingHidden: countingHidden)
        if let info = known[key] { return completion(info) }
        if waiting[key] != nil {
            waiting[key]?.append(completion)
            return
        }
        waiting[key] = [completion]
        queue.async {
            let info = ItemInfo.read(for: item, countingHidden: countingHidden)
            DispatchQueue.main.async {
                if self.known.count > 5000 { self.known.removeAll() }
                self.known[key] = .some(info)
                self.waiting.removeValue(forKey: key)?.forEach { $0(info) }
            }
        }
    }
}

/// The item info as Finder writes it, in the Mac's language.
enum ItemInfoText {
    static func text(_ info: ItemInfo) -> String {
        switch info {
        case .items(let count):
            return String(format: count == 1 ? L("%d item") : L("%d items"), count)
        case .pixels(let width, let height):
            return String(format: L("%d × %d"), width, height)
        case .capacity(let total, let available):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return String(format: L("%@, %@ free"), formatter.string(fromByteCount: total),
                          formatter.string(fromByteCount: available))
        case .duration(let seconds):
            return ItemInfo.durationText(seconds)
        }
    }
}

/// Stacks named after their group, as Finder names them: the type of file, a period of time, a tag.
enum StackNames {
    static func name(of group: StackGroup) -> String {
        switch group {
        case .kind(let kind): return kind
        case .folders: return L("Folders")
        case .today: return L("Today")
        case .yesterday: return L("Yesterday")
        case .previousDays(let days): return String(format: L("Previous %d Days"), days)
        case .month(let month):
            let symbols = DateFormatter().standaloneMonthSymbols ?? []
            return symbols.indices.contains(month - 1) ? symbols[month - 1].capitalized : String(month)
        case .year(let year): return String(year)
        case .noDate: return L("No Date")
        case .tag(let tag): return tag
        case .noTags: return L("No Tags")
        }
    }
}
