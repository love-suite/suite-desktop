import CoreServices
import Foundation
import SuiteFilesCore

/// Finder's Clean Up By: what the icons are lined up by, once, from the top of the grid (the sort order
/// itself doesn't change).
public enum CleanUpKey: String, CaseIterable, Sendable {
    case name, kind, dateLastOpened, dateAdded, dateModified, dateCreated, size, tags
}

public enum DesktopCleanUp {
    /// The items in Clean Up By order, as Finder lines them up: names and kinds A to Z, dates and sizes
    /// newest and largest first (items without one last), tagged items first by their first tag; ties by
    /// name. With `foldersFirst`, folders (and aliases to them) come before the files.
    public static func ordered(_ items: [FileItem], by key: CleanUpKey, foldersFirst: Bool = false,
                               facts: StackFacts = StackFacts()) -> [FileItem] {
        func byName(_ a: FileItem, _ b: FileItem) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        func newestFirst(_ a: Date?, _ b: Date?) -> Bool? {
            switch (a, b) {
            case let (a?, b?): return a == b ? nil : a > b
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return nil
            }
        }
        func text(_ a: String?, _ b: String?) -> Bool? {
            switch (a, b) {
            case let (a?, b?):
                let order = a.localizedStandardCompare(b)
                return order == .orderedSame ? nil : order == .orderedAscending
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return nil
            }
        }
        return items.sorted { a, b in
            if foldersFirst && a.sortsAsFolder != b.sortsAsFolder { return a.sortsAsFolder }
            let first: Bool?
            switch key {
            case .name: first = nil
            case .kind: first = text(a.kind, b.kind)
            case .dateLastOpened: first = newestFirst(facts.lastOpened[a.url], facts.lastOpened[b.url])
            case .dateAdded: first = newestFirst(a.added, b.added)
            case .dateModified: first = newestFirst(a.modified, b.modified)
            case .dateCreated: first = newestFirst(a.created, b.created)
            case .size:
                switch (a.size, b.size) {
                case let (x?, y?) where x != y: first = x > y
                case (.some, nil): first = true
                case (nil, .some): first = false
                default: first = nil
                }
            case .tags: first = text(facts.tags[a.url]?.first, facts.tags[b.url]?.first)
            }
            return first ?? byName(a, b)
        }
    }
}

/// What Finder knows of a file beyond its resource values: when it was last opened (Spotlight's
/// `kMDItemLastUsedDate`, what Finder's Date Last Opened shows) and its tags.
public enum FileFacts {
    public static func lastOpened(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    public static func tags(_ url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }

    /// The facts a grouping or a Clean Up needs, read only for them.
    public static func read(for items: [FileItem], lastOpened: Bool, tags: Bool) -> StackFacts {
        var facts = StackFacts()
        guard lastOpened || tags else { return facts }
        for item in items {
            if lastOpened, let date = Self.lastOpened(item.url) { facts.lastOpened[item.url] = date }
            if tags {
                let names = Self.tags(item.url)
                if !names.isEmpty { facts.tags[item.url] = names }
            }
        }
        return facts
    }
}
