import AppKit
import SuiteCore
import SuiteFilesCore
import SuiteFilesUI

/// The menu bar while the desktop is clicked, laid out like Finder's but limited to what the desktop does.
/// Commands reach the desktop through the responder chain (`DesktopViewController`); places open where
/// folders open (`FileViewer`: Explorer while it manages files, Finder otherwise).
enum DesktopMenu {
    /// The app's name as the Mac's language says it: Bureau in French, Desktop otherwise.
    static var appName: String {
        Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Desktop"
    }

    static func make() -> NSMenu {
        let main = NSMenu()
        let shiftCmd: NSEvent.ModifierFlags = [.command, .shift]
        let optCmd: NSEvent.ModifierFlags = [.command, .option]
        let ctrlCmd: NSEvent.ModifierFlags = [.command, .control]

        let app = submenu(appName, in: main)
        add(app, String(format: L("About %@"), appName), #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        add(app, L("Settings"), #selector(Actions.showSettings), ",", target: Actions.shared)
        app.addItem(.separator())
        add(app, String(format: L("Hide %@"), appName), #selector(NSApplication.hide(_:)), "h")
        add(app, L("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", optCmd)
        add(app, L("Show All"), #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, String(format: L("Quit %@"), appName), #selector(NSApplication.terminate(_:)), "q")

        let file = submenu(L("File"), in: main)
        add(file, L("New Window"), #selector(Actions.newWindow), "n", target: Actions.shared)
        add(file, L("New Folder"), #selector(DesktopViewController.newFolder(_:)), "n", shiftCmd)
        add(file, L("Open"), #selector(DesktopViewController.openSelection(_:)), "o")
        file.addItem(.separator())
        add(file, L("Properties"), #selector(DesktopViewController.showProperties(_:)), "i")
        add(file, L("Change Icon"), #selector(DesktopViewController.changeIcon(_:)))
        add(file, L("Rename"), #selector(DesktopViewController.renameSelection(_:)))
        add(file, L("Quick Look"), #selector(DesktopViewController.toggleQuickLook(_:)), "y")
        file.addItem(.separator())
        add(file, L("Eject"), #selector(DesktopViewController.eject(_:)), "e")
        add(file, L("Move to Trash"), #selector(DesktopViewController.moveToTrash(_:)), "\u{8}")

        let edit = submenu(L("Edit"), in: main)
        add(edit, L("Undo"), #selector(DesktopViewController.undo(_:)), "z")
        add(edit, L("Redo"), #selector(DesktopViewController.redo(_:)), "z", shiftCmd)
        edit.addItem(.separator())
        add(edit, L("Cut"), #selector(DesktopViewController.cut(_:)), "x")
        add(edit, L("Copy"), #selector(DesktopViewController.copy(_:)), "c")
        add(edit, L("Paste"), #selector(DesktopViewController.paste(_:)), "v")
        add(edit, L("Move Item Here"), #selector(DesktopViewController.pasteMoving(_:)), "v", optCmd)
        add(edit, L("Select All"), #selector(DesktopViewController.selectAll(_:)), "a")
        edit.addItem(.separator())
        add(edit, L("Emoji & Symbols"), #selector(NSApplication.orderFrontCharacterPalette(_:)), " ", ctrlCmd)

        let view = submenu(L("View"), in: main)
        add(view, L("Use Stacks"), #selector(DesktopViewController.toggleStacks(_:)), "0", ctrlCmd)
        let groups = NSMenu(title: L("Group Stacks By"))
        for (title, grouping) in DesktopViewController.groupStacksTitles {
            add(groups, L(title), #selector(DesktopViewController.groupStacks(_:))).representedObject = grouping.rawValue
        }
        addSubmenu(groups, to: view)
        let sort = NSMenu(title: L("Sort By"))
        add(sort, L("Name"), #selector(DesktopViewController.sortByName(_:)))
        add(sort, L("Kind"), #selector(DesktopViewController.sortByKind(_:)))
        add(sort, L("Date Modified"), #selector(DesktopViewController.sortByDate(_:)))
        add(sort, L("Size"), #selector(DesktopViewController.sortBySize(_:)))
        addSubmenu(sort, to: view)
        add(view, L("Clean Up"), #selector(DesktopViewController.cleanUp(_:)))
        let cleanUp = NSMenu(title: L("Clean Up By"))
        for (title, key) in DesktopViewController.cleanUpTitles {
            add(cleanUp, L(title), #selector(DesktopViewController.cleanUpBy(_:))).representedObject = key.rawValue
        }
        addSubmenu(cleanUp, to: view)
        view.addItem(.separator())
        let labels = NSMenu(title: L("Label Position"))
        for (title, position) in DesktopViewController.labelPositionTitles {
            add(labels, L(title), #selector(DesktopViewController.setLabelPosition(_:))).representedObject = position.rawValue
        }
        addSubmenu(labels, to: view)
        add(view, L("Show Item Info"), #selector(DesktopViewController.toggleItemInfo(_:)))
        add(view, L("Show Icon Preview"), #selector(DesktopViewController.toggleIconPreview(_:)))
        view.addItem(.separator())
        add(view, L("Show File Extensions"), #selector(Actions.toggleExtensions), target: Actions.shared)
        add(view, L("Show Full Name of Selected Items"), #selector(Actions.toggleFullNames), target: Actions.shared)

        let go = submenu(L("Go"), in: main)
        for place in Actions.places {
            let item = add(go, L(place.title), #selector(Actions.goToPlace(_:)), place.key, shiftCmd,
                           target: Actions.shared)
            item.representedObject = place.url
        }

        let window = submenu(L("Window"), in: main)
        add(window, L("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window

        _ = submenu(L("Help"), in: main)
        return main
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                            _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        menu.addItem(item)
        return item
    }

    private static func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    private static func submenu(_ title: String, in main: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }

    /// What the menu does that isn't the desktop's own (settings, windows, places, display settings).
    final class Actions: NSObject, NSMenuItemValidation {
        static let shared = Actions()

        struct Place {
            let title: String
            let key: String
            let url: URL
        }

        /// Finder's Go menu, with its shortcuts.
        static let places: [Place] = {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let folder = { (directory: FileManager.SearchPathDirectory) in
                FileManager.default.urls(for: directory, in: .userDomainMask).first ?? home
            }
            return [
                Place(title: "Documents", key: "o", url: folder(.documentDirectory)),
                Place(title: "Desktop", key: "d", url: folder(.desktopDirectory)),
                Place(title: "Downloads", key: "l", url: folder(.downloadsDirectory)),
                Place(title: "Home", key: "h", url: home),
                Place(title: "Applications", key: "a", url: URL(fileURLWithPath: "/Applications")),
                Place(title: "Utilities", key: "u", url: URL(fileURLWithPath: "/Applications/Utilities")),
            ]
        }()

        @objc func showSettings() { SuiteSettingsApp.show(tab: "Desktop") }

        @objc func newWindow() { FileViewer.openFolder(FileManager.default.homeDirectoryForCurrentUser) }

        @objc func goToPlace(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            FileViewer.openFolder(url)
        }

        @objc func toggleExtensions() { DisplaySettings.showsFileExtensions.toggle() }

        @objc func toggleFullNames() { DisplaySettings.showsFullNameOfSelection.toggle() }

        func validateMenuItem(_ item: NSMenuItem) -> Bool {
            if item.action == #selector(toggleExtensions) {
                item.state = DisplaySettings.showsFileExtensions ? .on : .off
            } else if item.action == #selector(toggleFullNames) {
                item.state = DisplaySettings.showsFullNameOfSelection ? .on : .off
            }
            return true
        }
    }
}

/// The app's strings, from its own catalog.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
