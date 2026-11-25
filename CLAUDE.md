# Desktop: project brief

Desktop (`local.suite.desktop`, executable `Desktop`; named Bureau on a Mac in French:
`fr.lproj/InfoPlist.strings`, `LSHasLocalizedDisplayName`) is the suite's desktop in place of Finder's: the icons on the screen's background, their arrangement, stacks, the desktop's right-click menu
and its menu bar. It was part of Explorer until 2026-11-24 (its history is Explorer's for the files that
came from there). While it runs it hides Finder's desktop (Finder keeps its windows) and Suite Guard puts
Finder's desktop back should it vanish; quitting puts Finder's desktop back as the user had it.
It is an ordinary app (no `LSUIElement`; `.regular`, as Finder is):
macOS then picks it, as it picks Finder, when an app quits with its last window, instead of switching
Space; it has the menu bar when the desktop is clicked. Bar never shows it (`BarHiddenApps`, `suite-bar`).

## Architecture

```
DesktopSettings (library, no UI; the only product other repositories see)
    DesktopSettings (arrangement, icon size, grid spacing, text size, label position, item info, icon
    preview, stacks and what they group by, disks and servers shown, spring-loading, positions), in
    Desktop.app's defaults (`local.suite.desktop`); FinderDesktopView (Finder's View Options for the
    desktop and its Show*OnDesktop keys, as Finder keeps them); SpringLoading (macOS's spring-loading
    settings); DesktopMessage, the distributed notifications with Suite Settings
DesktopCore     (library, no UI, unit-tested) DesktopArranger, DesktopEntry, DesktopGrid, DesktopLayout,
    DesktopStacker and StackGroup (Group Stacks By); DesktopVolume (disks and servers on the desktop);
    DesktopCleanUp (Clean Up By) and FileFacts (Date Last Opened, tags); ItemInfo (Show Item Info);
    SpringLoader; FinderDesktop (Finder's desktop as the user set it up: View Options, items shown and the
    icons' places), FinderDesktopSync and FinderSyncRecord (the two-way sync with Finder's settings)
Desktop         (Desktop.app) DesktopWindow, DesktopViewController, DesktopCanvasView,
    DesktopDragAndDrop (with spring-loaded folders), DesktopItemInfo (the item info's text, its cache, stack
    names), StackViewController, DesktopMenu (its menu bar), WidgetWatcher and DesktopWidgets
    (macOS's widgets), FinderSync (reads and writes Finder's settings), AppDelegate (Finder's desktop,
    Suite Guard, settings, login item, updates), FileRoles (where folders open), FirstLaunch, EmptySpace
```

From the other repositories: `SuiteFilesCore` and `SuiteFilesUI` (`suite-files`) for everything about files
and their views; `FinderGuard` (`suite-guard`) for hiding Finder's desktop (`FinderManager`, which keeps
Finder's own setting in Desktop's defaults, `FinderDesktopBeforeHiding`) and loading Suite Guard
(`GuardAgent.update()`); `SuiteCore` for opening Explorer (`ExplorerLink`), Suite Settings
(`SuiteSettingsApp.show(tab: "Desktop")`), updates and relaunching. The display settings it shares with
Explorer's windows (`DisplaySettings`, file extensions for instance) are in Explorer's defaults for now.
Desktop never imports Explorer's code.

## How it runs

- At launch: Finder's desktop hidden, Suite Guard loaded, the desktop window shown, a login item registered
  once (the first launch), updates checked.
- First launch (no `DesktopSettings` saved yet): Finder's desktop as the user set it up (`FirstLaunch`,
  `FinderDesktop.onThisMac`): its View Options (`com.apple.finder` `DesktopViewSettings`: icon size, grid
  spacing, text size, label position, item info, icon preview, Sort By, Use Stacks and Group Stacks By),
  the items its General settings show on the desktop (`ShowHardDrivesOnDesktop`,
  `ShowExternalHardDrivesOnDesktop`, `ShowRemovableMediaOnDesktop`, `ShowMountedServersOnDesktop`) and its
  icons where Finder placed them (`~/Desktop/.DS_Store`, `FinderIconPositions`).
- While it runs, its settings and Finder's View Options stay one (`FinderSync`), both ways: a change in
  Suite Settings reaches Finder as the closest value Finder accepts, a change in Finder reaches Desktop; a
  timestamped record (`FinderSyncRecord`) tells a user's change from an old value Finder writes back.
- Disks and servers: as Finder's settings say which (`DesktopVolume.shown`: hard disks, external disks and
  disk images, removable media, servers), before the files, so they take the top-right cells; mounts,
  unmounts and renames show at once (`NSWorkspace` notifications); Eject (context menu, File › Eject,
  Command-E) unmounts them; they open where folders open. They are never copied, moved or trashed from
  the desktop (`selectedFiles`, `commandSelection`).
- Clean Up and Clean Up By (context menu and View menu, while icons are placed by hand): the icons to the
  nearest free cells, or lined up once in Finder's order (`DesktopCleanUp`), the sort order unchanged.
- Show Item Info: read in the background, kept per version of a file (`ItemInfoCache`); Label Position
  Right and the item info's line are drawn by `IconItemView` (`suite-files`: `labelOnRight`, `info`,
  `showsPreview`).
- Spring-loaded folders: while dragging (on the desktop or from another app), a folder, disk or stack the
  pointer rests on opens after macOS's delay (`SpringLoading.system()`, the global domain's
  `com.apple.springing.enabled` and `.delay`, read once per drag); off with the desktop's setting.
- Widgets: macOS draws them (Notification Center windows just above the desktop's icons) and Desktop leaves
  them visible, keeping its icons out of their way (`DesktopWidgets`, read from the Window Server).
  `WidgetWatcher` tells when they change from Notification Center's Accessibility events (the permission is
  asked at each launch until granted); without it, a mouse release has them looked at again.
- On a Space with no other window, Desktop makes itself active, as Finder does (`EmptySpace`).
- Suite Settings' agent covers, in System Settings, the macOS settings Desktop takes over while it runs
  ("Show items on desktop", "Click wallpaper to reveal desktop").
- Folders opened on the desktop and the Go menu open in Explorer while it manages files (installed, its
  Explorer/Finder switch on Explorer), in Finder otherwise (`FileRoles`).
- Settings written by Suite Settings: `DesktopMessage.applySettings`; display settings: Explorer's
  `applySettings` command.
- `--restore-finder` puts Finder's desktop back after a crash; `--relaunch` (make-app.sh) asks the running
  copy to reopen itself, as an update does, without giving Finder its desktop back.

## Work to do

- "Delete Immediately" of items that need root: Explorer's Suite Trash helper lets only Explorer in, so
  Desktop reports them as not deleted (`FileActions.eraseNeedingRoot` unset).

## Building and running

- `swift build` and `swift test` for development.
- `scripts/make-app.sh` builds `build/Desktop.app` (release), signs it with the "Suite Local Signing"
  certificate from the login keychain, so macOS permissions survive rebuilds (ad-hoc signing, the
  fallback, re-asks every build), and installs it as `~/Applications/Desktop.app`, the only copy Launch
  Services knows. It records the branch and commit in the Info.plist (`SuiteBuildBranch`,
  `SuiteBuildCommit`) and refuses to replace an installed copy built from another branch, or from an unknown
  one, unless `--force`: another session may be testing it. `INSTALL_DIR=` builds without installing. A
  running copy is relaunched from the new one.
- Never ask the user to open `build/Desktop.app` from a worktree.
- UI can't be checked by unit tests and screenshots of the user's screen are not available: check UI by
  rendering views offscreen (`cacheDisplay`) from a scratch package that compiles the sources.
- Never let test programs act on the real Finder or its desktop.
- Releases: as every app of the suite (`scripts/publish.sh`, `.github/workflows/release.yml`); the feed is
  `https://github.com/love-suite/suite-desktop/releases/latest/download/update.json`
  (the GitHub repository it is built from).

## The suite

This repository is part of Love Suite, one repository per app under `github.com/love-suite`:
`suite-core` (the shared library), `suite-files` (the file layer of the apps handling files),
`suite-guard`, `suite-desktop` (the desktop), `suite-explorer`, `suite-bar` (the Dock), `suite-viewer`,
`suite-clipboard`, `suite-settings` (the settings), `suite-awake` (keeping the Mac awake), `suite-launcher`, `suite-bindings`,
`suite-ai-organizer`; `homebrew-tap` (the tap `love-suite/tap`, one cask per app) and `suite` (the
front page, the suite's version, the scripts that act on every repository). Locally they sit side by side
in `~/GitHub/paul-amour/suite/`.

## Conventions (the same in every repository of the suite)

- The user writes in French and expects answers in French; everything in the code stays in English: code,
  comments, tests, docs, commit messages. Do not add co-author trailers.
- No "…" in menu items, buttons or messages: the user wants none, anywhere.
- Behaviour follows Windows unless Apple's design is asked for.
- Swift Package Manager, `swift-tools-version:5.9`, macOS 13+. Tests use Swift Testing (`import Testing`).
- Toolchain: swiftly, Swift 6.4.2 (`.swift-version`, git-ignored). If `swift test` complains about a
  missing toolchain: `swiftly use 6.4.2`.
- AppKit for windows that need fine control; SwiftUI is allowed for small panels (settings, pickers).
- No private APIs and no system modifications (SIP stays on).
- Git: one worktree per feature under `.worktrees/` (git-ignored), one branch per change
  (`feat/<feature>`, `fix/<area>/<what>`), merged into `main` one by one; `main` stays stable.
- Versions are `AA.Y`, then `AA.Y.Z` for a fix (`VERSION`, tag `vVERSION`: 27.1, then 27.1.1; SwiftPM reads
  `v27.1` as 27.1.0): `AA` is the latest macOS in production (27), `AA.Y` is the same in every repository of
  the suite so the apps work together, `Z` is this repository's own. A change of `AA.Y` is made in `suite`
  and reaches every repository. While a version is being prepared, `VERSION` doesn't move (27.1 now):
  development builds are `VERSION-dev.N`, N the commits since `VERSION` was set, merges aside, from 1 (`make-app.sh`),
  and a change another repository needs gets a development tag, `vVERSION-dev.N`, which releases nothing.
  Dependencies on other repositories of the suite (`suite-core`, `suite-files`, `suite-guard`, settings
  libraries) use
  `.upToNextMinor(from: "27.1.0-dev.1")` (the latest development tag, then the release);
  `Package.resolved` is committed. Tags are never moved once pushed. The build number (`CFBundleVersion`,
  which the updater compares) stays the number of commits.
- Changing two repositories at once: `swift package edit <Package> --path ../<repository>` points at the
  neighbour's working copy until its tag exists, `swift package unedit` goes back. Never committed.
- Code goes only where it is used: `suite-core` holds what every app needs; what only some apps share lives
  in a library repository of its own (`suite-files` for the apps handling files), which only those apps
  depend on. An app's own code never goes into another app's repository, and an app exposes only its
  settings, as `<App>Settings`, for Suite Settings. See `suite/docs/architecture.md`.
- Do not run commands that delete user data. Trash instead of delete.
- No code converting saved settings at launch. Before the first release nothing needs converting (the
  developer's own settings don't count): rename freely. Between released versions, a change to saved
  settings is a `SettingsMigration` (suite-core) for the version that brought it, given to the app's
  `SuiteUpdater`, which runs it once after the update.
