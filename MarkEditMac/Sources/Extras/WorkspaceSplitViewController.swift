//
//  WorkspaceSplitViewController.swift
//  MarkEditMac
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit
import MarkEditKit
import Workspace

/**
 Container for the contents of an editor window: a folder sidebar beside the editor.

 Upstream makes `EditorViewController` the window's `contentViewController` directly.
 The fork puts this in between, so a sidebar can share the window and so the editor
 can later be replaced in place without tearing the window down.

 Nothing should reach for this type to find the editor. Code that needs the editor
 descends to it with `hostedEditor` (`Extras/NSApplication+Extras.swift`), which works
 whether or not this container is in the way.

 It lives in `Extras` rather than a directory of its own because a new group in
 `project.pbxproj` is merge surface in the worst file in the repository, and this is
 the only new app-target file the fork budgets for.
 */
final class WorkspaceSplitViewController: NSSplitViewController {
  /// The editor occupying the detail pane.
  let editor: EditorViewController

  init(editor: EditorViewController) {
    self.editor = editor
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Created in code, never from a storyboard")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

  #if DEBUG
    WorkspaceDebugMenu.installIfNeeded()
  #endif

    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
    // A collapsed item doesn't load its view until it is first shown
    sidebarItem.isCollapsed = !Self.showsSidebarOnLaunch
    addSplitViewItem(sidebarItem)

    addSplitViewItem(NSSplitViewItem(viewController: editor))
    sidebar.setRoot(Self.hardcodedRoot)
  }

  /// Whether a sidebar pane is currently showing.
  var showsSidebar: Bool {
    splitViewItems.contains { $0.behavior == .sidebar && !$0.isCollapsed }
  }

  private lazy var sidebar = WorkspaceSidebarController(
    host: self,
    options: FolderScanner.Options(
      // The types the app declares as its own, plus extension-less files, which notes
      // folders are full of and which open as plain text
      fileExtensions: Set(NewFilenameExtension.allCases.map(\.rawValue)),
      showsHiddenFiles: AppPreferences.General.showHiddenFiles
    )
  )
}

// MARK: - WorkspaceHost

/**
 The app half of the sidebar's protocol: the module knows about `URL`, this knows about
 documents. It is the only place the two meet.
 */
extension WorkspaceSplitViewController: WorkspaceHost {
  var currentFileURL: URL? {
    editor.document?.fileURL
  }

  func openInPlace(_ url: URL) {
    guard let windowController = view.window?.windowController as? EditorWindowController else {
      return Logger.assertFail("Missing window controller to switch documents in")
    }

    WorkspaceDocumentSwitcher.shared.switchDocument(to: url, in: windowController)
  }
}

// MARK: - Titlebar

extension NSWindow {
  /**
   Whether this window is showing a workspace sidebar.

   AppKit stops providing `NSTitlebarBackgroundView` as soon as a split view item with
   `.sidebar` behavior is visible: on macOS 26 and later the titlebar area is drawn by the
   scroll pocket instead, which lives beside the content view rather than under
   `NSTitlebarContainerView`. Verified by dumping that subtree with the sidebar collapsed
   (`NSTitlebarBackgroundView` present, and hidden by `modernTitleBar` anyway) and expanded
   (absent, with an `NSScrollPocket` backdrop view added next to the content view).

   `allowsFullHeightLayout = false` does not bring it back; a visible sidebar is enough.

   Code that customises the titlebar background uses this to tell that expected absence
   from a real one.
   */
  var showsWorkspaceSidebar: Bool {
    (contentViewController as? WorkspaceSplitViewController)?.showsSidebar ?? false
  }
}

// MARK: - Private

private extension WorkspaceSplitViewController {
  /// The sidebar has no toggle yet, so it stays collapsed unless asked for.
  static var showsSidebarOnLaunch: Bool {
  #if DEBUG
    return ProcessInfo.processInfo.environment["DEBUG_WORKSPACE_SIDEBAR"] == "YES"
  #else
    return false
  #endif
  }

  /**
   The folder the tree lists, until M5 resolves one from a security-scoped bookmark.

   Hardcoded means hardcoded to nothing in a release build: the sidebar shows its empty
   state, and since it also starts collapsed, a release build behaves exactly as it did
   before this milestone.
   */
  static var hardcodedRoot: URL? {
  #if DEBUG
    guard let path = ProcessInfo.processInfo.environment["DEBUG_WORKSPACE_ROOT"] else {
      return nil
    }

    return URL(filePath: NSString(string: path).expandingTildeInPath)
  #else
    return nil
  #endif
  }
}

// MARK: - Document Switching

extension EditorDocument {
  /**
   Bind this document to a window and an editor that already exist.

   These are the steps `makeWindowControllers` takes once the window and the editor exist,
   minus the ones that only mean something for a brand-new window. They are duplicated here
   rather than factored out of `makeWindowControllers` on purpose: that function is in the
   hottest file in the upstream seam, and a structural diff there costs more at every sync
   than four repeated lines cost to maintain. The only change that file carries for this is
   `hostViewController` losing its `private`.

   Forgetting `hostViewController` is the silent failure mode — `EditorDocument.bridge` is
   `hostViewController?.bridge`, so a document that holds a window but no host talks to
   nothing and saves stale text.
   */
  func adopt(windowController: EditorWindowController, contentViewController: EditorViewController) {
    // First, because `NSWindowController.document` detaches from its previous document when
    // it is set. Adding to the new document is the ordering that never leaves the controller
    // document-less; the reverse order would.
    addWindowController(windowController)

    isTerminating = false
    hostViewController = contentViewController

    // `EditorViewController.representedObject.didSet` calls `resetEditor()`, which keys off
    // document identity and rebuilds CodeMirror's `EditorView` in the same `WKWebView`.
    // This single assignment is the entire editor-side switch.
    contentViewController.representedObject = self
  }
}

/**
 Replaces the document shown by an editor window, in place, with the document at another URL.

 The window and its `WKWebView` are reused; only `representedObject` changes. This is the
 behaviour the fork exists for — clicking a file in the sidebar replaces what the window is
 showing, rather than opening a second window.

 The outgoing document is asked to close *before* anything moves, so a save sheet lands on
 the window that still owns it and the switch stays refusable.
 */
@MainActor
final class WorkspaceDocumentSwitcher: NSObject {
  static let shared = WorkspaceDocumentSwitcher()

  /**
   Show the document at `url` in `windowController`'s window.

   Asks the outgoing document to close first. That either succeeds silently, saves, or puts
   a sheet on this window and lets the user cancel — and a cancelled switch leaves everything
   as it was, which is the correct answer rather than a gap.
   */
  func switchDocument(to url: URL, in windowController: EditorWindowController) {
    guard let editor = windowController.contentViewController?.hostedEditor, let current = editor.document else {
      return Logger.assertFail("Missing editor or document to switch away from")
    }

    guard pending == nil else {
      // A switch is already waiting on a save sheet, don't stack another one behind it
      return NSSound.beep()
    }

    let target = url.standardizedFileURL
    guard current.fileURL?.standardizedFileURL != target else {
      return // Already showing it
    }

    // Open in New Window is the escape hatch for two files at once, so a file that already
    // has a window keeps it rather than being pulled into this one.
    if let existing = NSDocumentController.shared.document(for: target) as? EditorDocument, !existing.windowControllers.isEmpty {
      return existing.showWindows()
    }

    let request = SwitchRequest(url: target, windowController: windowController, editor: editor, previous: current)

    // The common flow is: new window, then pick a file. An untouched draft has nothing to
    // save and nothing to confirm, so it must not raise a sheet.
    if current.fileURL == nil && !current.isDocumentEdited && current.stringValue.isEmpty {
      return perform(request)
    }

    // Asked while the outgoing document still owns the window, so the sheet lands on the
    // right one. This also flushes the web view's text into `stringValue`.
    //
    // `self` deliberately does not implement `confirmsChanges(_:shouldClose:contextInfo:)`:
    // `EditorDocument.canClose` only routes there when the delegate responds to that
    // selector, and `confirmsChanges` sets `isReleasedWhenClosed` on the document's windows
    // and closes them — destroying the window this is trying to keep.
    pending = request
    current.canClose(
      withDelegate: self,
      shouldClose: #selector(document(_:shouldClose:contextInfo:)),
      contextInfo: nil
    )
  }

  // MARK: - Private

  override private init() {}

  private struct SwitchRequest {
    let url: URL
    let windowController: EditorWindowController
    let editor: EditorViewController
    let previous: EditorDocument
  }

  private var pending: SwitchRequest?

  @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
    guard let request = pending else {
      return Logger.assertFail("Received a close decision with no switch pending")
    }

    pending = nil

    // Cancelled: the outgoing document keeps the window, exactly as it was
    guard shouldClose else {
      return
    }

    perform(request)
  }

  private func perform(_ request: SwitchRequest) {
    // display: false keeps the incoming document from calling `makeWindowControllers`
    // and opening a second window
    NSDocumentController.shared.openDocument(withContentsOf: request.url, display: false) { document, _, error in
      guard let next = document as? EditorDocument else {
        NSSound.beep()
        Logger.log(.error, "Failed to open \(request.url.lastPathComponent): \(error?.localizedDescription ?? "unknown error")")
        return
      }

      let previous = request.previous
      self.captureTabState(of: previous, in: request.windowController)
      next.adopt(windowController: request.windowController, contentViewController: request.editor)
      request.windowController.synchronizeWindowTitleWithDocumentName()

      // Transferring the window controller leaves the outgoing document open and registered
      // — measured, not assumed — so it is closed here. `EditorDocument.close()` pushes it
      // onto the closed-tab history, which turns cmd-shift-t into a back button.
      if previous !== next && previous.windowControllers.isEmpty {
        previous.close()
      }

      next.invalidateRestorableState()
      request.windowController.window?.invalidateRestorableState()
    }
  }

  /**
   Record how the outgoing document's window sat among its tabs, before the window moves.

   `EditorDocument.saveToClosedTabHistory` captures this itself, but it reads
   `windowControllers.first?.window` and by the time the outgoing document closes the window
   belongs to the incoming one. Left uncaptured, `lastWasStandalone` keeps its `false`
   default, which tells `reopenClosedTab` the file used to be a tab — so cmd-shift-t would
   answer a switch by opening a tab, in a fork whose whole point is not having them.
   */
  private func captureTabState(of document: EditorDocument, in windowController: EditorWindowController) {
    guard document.lastTabIndex == nil, let window = windowController.window else {
      return
    }

    let tabbedWindows = window.tabbedWindows
    document.lastTabIndex = tabbedWindows?.firstIndex(of: window)
    document.lastWasStandalone = tabbedWindows == nil || tabbedWindows?.count == 1
    document.lastSiblingWindow = tabbedWindows?.first { $0 !== window }
  }
}

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

    let holder = NSMenuItem()
    holder.submenu = menu
    mainMenu.addItem(holder)
  }

  // MARK: - Private

  private static let environmentKey = "DEBUG_WORKSPACE_SWITCH_PATHS"
  private static var isInstalled = false

  private static var targetURLs: [URL] {
    let paths = ProcessInfo.processInfo.environment[environmentKey] ?? ""
    return paths.split(separator: ":").map {
      URL(filePath: NSString(string: String($0)).expandingTildeInPath)
    }
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
