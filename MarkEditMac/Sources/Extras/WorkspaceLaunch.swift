//
//  WorkspaceLaunch.swift
//  MarkEditMac
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit
import MarkEditKit
import Workspace

/*
 What the app does at launch about a folder, and the debug overrides and menu that stand in for
 the panels a scripted session cannot click.

 Split out of `WorkspaceSplitViewController.swift` on 2026-09-24, when that file hit SwiftLint's
 1000-line limit — a build failure here, not a warning — for the third time in a day. Everything
 that only needed AppKit had already moved to the module, where a file costs no
 `project.pbxproj` lines; what is left extends `AppDelegate` and `EditorViewController`, so it
 has to be in the app target. **This is the planned split the tracker asked for rather than the
 forced one:** the launch rule and the overrides that exist to test it belong together, and the
 container, the document switch and the sidebar's menu stay where they were.

 The cost is **4 `project.pbxproj` lines**, in the worst file in the fork's merge surface.
 */

// MARK: - Launch

extension AppDelegate {
  /**
   Open the sidebar's folder, at the moment the app opens its other granted folders.

   Called from `startAccessingGrantedFolder()`, which `Application.main()` runs before
   `NSApplicationMain` — before any window exists, and so before a document restored into one
   might need to be read through the folder's security scope. `AppDelegate+FileSystem.swift`
   takes one upstream commit a year, which makes it the cheapest line in the seam to spend,
   and it is the flow this belongs to besides: both are the app reopening a folder the user
   granted it once.

   **Which folder is `LaunchFolder`'s decision, and it cannot hold up a launch.** Last Used or
   a pinned Custom folder, resolved off the main thread under a bounded wait, with every
   failure answered by carrying on with no folder — the reasoning is with the cases in
   `LaunchFolder.restore()`.
   */
  func startAccessingWorkspaceRoot() {
  #if DEBUG
    if applyDebugRoot() {
      return
    }
  #endif

    LaunchFolder.shared.restore()
  }

  /**
   Whether a launch with nothing to restore opens an untitled document rather than a file
   panel. The rule, and why it overrides upstream's, is `LaunchFolder.opensUntitledFile`; this
   only supplies the one thing the module cannot see.

   `@Storage` cannot tell a chosen `newWindowBehavior` from its default — it answers
   `.openDocument` for "wants the panel" and for "has never opened Settings" alike — so this
   asks `UserDefaults` whether the key is there at all. The key is repeated rather than read
   from the property wrapper, which exposes no accessor for it. If upstream ever renames it,
   this reads nil, which means "not set", which means the fork's own rule applies: the
   direction that fails toward the fork's behaviour rather than away from it.

   It governs a Dock-icon click with no windows open as well, which is the same method and the
   same question.
   */
  var opensUntitledFileForWorkspace: Bool {
    LaunchFolder.shared.opensUntitledFile(
      hasExplicitPreference: UserDefaults.standard.object(forKey: "general.new-window-behavior") != nil
    )
  }
}

#if DEBUG
/**
 The environment overrides that stand in for a folder the user picked.

 They exist because choosing a folder ends in an open panel, and a panel is one of the things
 that cannot be clicked from a scripted session on this machine — so without them the whole
 milestone would only be checkable by hand.

 `DEBUG_WORKSPACE_ROOT` opens a folder for this launch and forgets it, which is what a
 verification run wants: it must not leave a root behind for the next launch to restore.
 `DEBUG_WORKSPACE_SAVE_ROOT` takes the other half — it runs the real `save`, the same bookmark
 written to the same sandboxed defaults the panel would have written, so that the relaunch it
 is supposed to survive can actually be tested. `DEBUG_WORKSPACE_PIN_ROOT` does the same for
 the Custom launch folder, which is the Settings panel nothing here can click either.

 `DEBUG_WORKSPACE_LAUNCH_RESET` is the undo, and it exists because the other two write state
 that outlives the test: this suite shares `UserDefaults` with every real launch of the app, so
 a test that pins a fixture and then deletes it would leave the person using this app pinned to
 a folder that is not there. It puts the sidebar's filter preferences back too, for the same
 reason — the suite works those switches in the real Settings pane.
 */
private extension AppDelegate {
  func applyDebugRoot() -> Bool {
    let environment = ProcessInfo.processInfo.environment

    // First, because it is the undo for everything below: the UI suite shares `UserDefaults`
    // with every real launch, so a test that pins a fixture, remembers a folder or ticks a
    // filter is writing the preferences of whoever uses this app. It **restores** rather than
    // clears — clearing is what destroyed a real folder's bookmark on 2026-09-24, and a
    // security-scoped bookmark cannot be recreated without the user picking the folder again.
    if environment["DEBUG_WORKSPACE_LAUNCH_RESET"] != nil {
      WorkspaceDebugState.restore()
      return true
    }

    // Snapshot before anything is written, and only when a test is driving: a real launch sets
    // none of these and takes no snapshot, so it can never be restored over.
    guard environment.keys.contains(where: { $0.hasPrefix("DEBUG_WORKSPACE_") }) else {
      return false
    }

    // Makes the state as it stands the state a later reset goes back to. Exists for the one
    // test that has to prove the undo restores rather than wipes, which needs a folder that
    // looks as if it was there before the suite ran.
    if environment["DEBUG_WORKSPACE_ADOPT_STATE"] != nil {
      WorkspaceDebugState.adopt()
      return true
    }

    WorkspaceDebugState.captureIfNeeded()

    // Both of the next two can be set together — last used folder *and* a pin — so neither
    // returns early. The saved root goes first so that the pin is what ends up open.
    var isHandled = false

    if let path = environment["DEBUG_WORKSPACE_SAVE_ROOT"] {
      saveDebugRoot(path)
      isHandled = true
    }

    if let path = environment["DEBUG_WORKSPACE_PIN_ROOT"] {
      // Empty means "Custom mode with nothing pinned", which is the fallback case: the launch
      // rule should quietly use the last folder instead, and that is worth being able to test.
      if path.isEmpty {
        LaunchFolder.shared.clearPinnedFolder()
        LaunchFolder.shared.mode = .custom
      } else {
        LaunchFolder.shared.pinFolder(URL(filePath: NSString(string: path).expandingTildeInPath))
      }

      LaunchFolder.shared.restore()
      return true
    }

    if isHandled {
      LaunchFolder.shared.restore()
      return true
    }

    if let path = environment["DEBUG_WORKSPACE_ROOT"] {
      // Set but empty means "start with no folder at all". A UI test asserting the empty
      // state needs that: it shares `UserDefaults` with every real launch, so without it the
      // test inherits whatever folder the person using the app last chose, and passes or
      // fails on their state rather than on its own.
      if !path.isEmpty {
        BookmarkStore.shared.useWithoutSaving(URL(filePath: NSString(string: path).expandingTildeInPath))
      }

      return true
    }

    return false
  }

  /// The real `save`, so the bookmark a relaunch has to survive is the one the panel writes.
  func saveDebugRoot(_ path: String) {
    let folder = URL(filePath: NSString(string: path).expandingTildeInPath)
    do {
      try BookmarkStore.shared.save(folder)
      Logger.log(.info, "Remembered workspace root: \(folder.path)")
    } catch {
      Logger.log(.error, "Failed to remember workspace root: \(error)")
    }
  }
}
#endif

// MARK: - Debug Menu

#if DEBUG
/**
 Drives `WorkspaceDocumentSwitcher` from the menu bar, before any sidebar exists to drive it.

 Switching is the step of this fork that can fail, so it gets to fail on its own, with no
 file tree, no bookmarks and no selection model in the picture. Set
 `DEBUG_WORKSPACE_SWITCH_PATHS` to a colon-separated list of files to get one menu item per
 file, on cmd-ctrl-1 upwards.

 Built in code rather than in `Main.storyboard`: the storyboard is upstream's, and a debug
 affordance is not worth a permanent diff in it.
 */
@MainActor
enum WorkspaceDebugMenu {
  static func installIfNeeded() {
    guard !isInstalled, let mainMenu = NSApp.mainMenu else {
      return
    }

    isInstalled = true
    let menu = NSMenu(title: "Workspace")

    for item in menuItems {
      menu.addItem(item)
    }

    if let dropItem {
      menu.addItem(.separator())
      menu.addItem(dropItem)
    }

    if let sidebarDropItem {
      menu.addItem(sidebarDropItem)
    }

    let holder = NSMenuItem()
    holder.submenu = menu
    mainMenu.addItem(holder)
  }

  // MARK: - Private

  private static let environmentKey = "DEBUG_WORKSPACE_SWITCH_PATHS"
  private static let dropEnvironmentKey = "DEBUG_WORKSPACE_DROP_PATHS"
  private static let sidebarDropEnvironmentKey = "DEBUG_WORKSPACE_SIDEBAR_DROP_PATHS"
  private static var isInstalled = false

  private static var targetURLs: [URL] {
    let paths = ProcessInfo.processInfo.environment[environmentKey] ?? ""
    return paths.split(separator: ":").map {
      URL(filePath: NSString(string: String($0)).expandingTildeInPath)
    }
  }

  private static var dropURLs: [URL] {
    urls(from: dropEnvironmentKey)
  }

  private static var sidebarDropURLs: [URL] {
    urls(from: sidebarDropEnvironmentKey)
  }

  private static func urls(from key: String) -> [URL] {
    let paths = ProcessInfo.processInfo.environment[key] ?? ""
    return paths.split(separator: ":").map {
      URL(filePath: NSString(string: String($0)).expandingTildeInPath)
    }
  }

  /**
   Drop those files on the editor, without a drag.

   A drag cannot be synthesized from a scripted session or from XCUITest across two apps, so
   the fork's drop path would otherwise only ever be checkable by hand. This calls the same
   delegate method `EditorWebView.performDragOperation` calls, which is the half that copies
   into `assets/` and writes the link — the promise half above it needs a real promise and
   stays a manual check.
   */
  private static var dropItem: NSMenuItem? {
    let urls = dropURLs
    guard !urls.isEmpty else {
      return nil
    }

    let item = NSMenuItem(
      title: "Drop \(urls.count) file(s) on the editor",
      action: #selector(WorkspaceDropDebugger.dropDebugTargets(_:)),
      keyEquivalent: "0"
    )

    item.keyEquivalentModifierMask = [.command, .control]
    item.target = WorkspaceDropDebugger.shared
    item.representedObject = urls
    return item
  }

  /**
   Drop those files on a sidebar row, without a drag.

   `DEBUG_WORKSPACE_SIDEBAR_DROP_ROW` names the row, by its file name; leaving it out means the
   sidebar itself, which is the empty space under the tree and resolves to the root.
   `DEBUG_WORKSPACE_SIDEBAR_DROP_MOVE=YES` stands in for holding ⌘, which XCUITest cannot hold
   across a gesture it is not performing.

   It is the same entry points a real drop takes, from the point onwards — see
   `WorkspaceSidebarController.debugDrop` for what that does and does not establish.
   */
  private static var sidebarDropItem: NSMenuItem? {
    let urls = sidebarDropURLs
    guard !urls.isEmpty else {
      return nil
    }

    let row = ProcessInfo.processInfo.environment["DEBUG_WORKSPACE_SIDEBAR_DROP_ROW"]
    let item = NSMenuItem(
      title: "Drop \(urls.count) file(s) on \(row ?? "the sidebar")",
      action: #selector(WorkspaceDropDebugger.dropDebugTargetsOnSidebar(_:)),
      keyEquivalent: "9"
    )

    item.keyEquivalentModifierMask = [.command, .control]
    item.target = WorkspaceDropDebugger.shared
    item.representedObject = urls
    return item
  }

  private static var menuItems: [NSMenuItem] {
    let urls = targetURLs
    guard !urls.isEmpty else {
      // Action is nil, so this is disabled and reads as instructions
      return [NSMenuItem(title: "Set \(environmentKey) to a colon-separated list of files", action: nil, keyEquivalent: "")]
    }

    return urls.enumerated().map { index, url in
      let item = NSMenuItem(
        title: "Switch to \(url.lastPathComponent)",
        action: #selector(WorkspaceDocumentSwitcher.switchToDebugTarget(_:)),
        keyEquivalent: index < 9 ? "\(index + 1)" : ""
      )

      item.keyEquivalentModifierMask = [.command, .control]
      item.target = WorkspaceDocumentSwitcher.shared
      item.representedObject = url
      return item
    }
  }
}

/// The debug menu's drop item, and nothing else. A target for an `@objc` action has to be an
/// object, and this has no state worth putting on the switcher.
@MainActor
final class WorkspaceDropDebugger: NSObject, NSMenuItemValidation {
  static let shared = WorkspaceDropDebugger()

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    guard menuItem.representedObject is [URL] else {
      return false
    }

    if menuItem.action == #selector(dropDebugTargetsOnSidebar(_:)) {
      return sidebar != nil
    }

    return NSApp.currentEditor != nil
  }

  /// The sidebar's drop, driven from the row the environment named. A beep is the failure the
  /// UI test reads as "the rows never reported their frames", which is the thing worth
  /// catching — so this must not fall back to dropping on the root.
  @objc fileprivate func dropDebugTargetsOnSidebar(_ sender: NSMenuItem) {
    guard let urls = sender.representedObject as? [URL], let sidebar else {
      return NSSound.beep()
    }

    let environment = ProcessInfo.processInfo.environment
    let landed = sidebar.debugDrop(
      urls,
      onRowNamed: environment["DEBUG_WORKSPACE_SIDEBAR_DROP_ROW"],
      moving: environment["DEBUG_WORKSPACE_SIDEBAR_DROP_MOVE"] == "YES"
    )

    if !landed {
      NSSound.beep()
    }
  }

  private var sidebar: WorkspaceSplitViewController? {
    NSApp.keyWindow?.contentViewController as? WorkspaceSplitViewController
  }

  @objc fileprivate func dropDebugTargets(_ sender: NSMenuItem) {
    guard let urls = sender.representedObject as? [URL], let editor = NSApp.currentEditor else {
      return NSSound.beep()
    }

    guard let webView = editor.webView as? EditorWebView else {
      return NSSound.beep()
    }

    // The same two steps `EditorWebView.performDragOperation` takes, in the same order: the
    // fork's branch first, upstream's delegate for whatever it did not claim.
    // `DEBUG_WORKSPACE_DROP_RECEIVED` says to treat the files as a promise's output, which is
    // the half that may not fall back to linking them where they lie.
    let deliver: ([URL]) -> Void = { fileURLs in
      editor.editorWebView(webView, didDrop: fileURLs)
    }

    let handled = ProcessInfo.processInfo.environment["DEBUG_WORKSPACE_DROP_RECEIVED"] == "YES"
      ? EditorDrops.takesOver(received: urls, in: editor.view.window, then: deliver)
      : EditorDrops.takesOver(files: urls, in: editor.view.window, then: deliver)

    if !handled {
      deliver(urls)
    }
  }
}

extension WorkspaceDocumentSwitcher: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    menuItem.representedObject is URL && Self.debugTargetWindowController != nil
  }

  @objc fileprivate func switchToDebugTarget(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL, let windowController = Self.debugTargetWindowController else {
      return NSSound.beep()
    }

    switchDocument(to: url, in: windowController)
  }

  /**
   The window a debug switch acts on.

   The real sidebar will name its own window, so this ordering exists only here. It falls
   back past `keyWindow` and `mainWindow` to any visible editor window because both are nil
   while the app is inactive, and driving the menu from a script is exactly the case where
   the app is not the one in front.
   */
  fileprivate static var debugTargetWindowController: EditorWindowController? {
    let candidates = [NSApp.keyWindow, NSApp.mainWindow] + NSApp.windows.filter(\.isVisible)
    for window in candidates {
      if let windowController = window?.windowController as? EditorWindowController {
        return windowController
      }
    }

    return nil
  }
}
#endif
