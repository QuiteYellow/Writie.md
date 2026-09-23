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
    ProductNameMenu.applyIfNeeded()
    WorkspaceSidebarMenu.installIfNeeded()

  #if DEBUG
    WorkspaceDebugMenu.installIfNeeded()
  #endif

    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
    // A collapsed item doesn't load its view until it is first shown
    sidebarItem.isCollapsed = !Self.showsSidebarOnLaunch

    // Both measured rather than chosen, and both explained where they are declared
    sidebarItem.minimumThickness = SidebarWidth.Bounds.minimum
    sidebarItem.maximumThickness = SidebarWidth.Bounds.maximum
    addSplitViewItem(sidebarItem)

    // The root picker is pinned to the item rather than placed inside the sidebar's own view,
    // which is what earns it the system's footer treatment. Below macOS 26 the class doesn't
    // exist and `WorkspaceSidebarView` draws the picker along its own bottom edge instead.
    if #available(macOS 26.0, *) {
      sidebarItem.addBottomAlignedAccessoryViewController(sidebar.makeFooterAccessory())
    }

    addSplitViewItem(NSSplitViewItem(viewController: editor))

    // Every moment this window might have started showing a different file. The sync is a
    // no-op when nothing changed, so asking often is cheaper than finding one perfect hook.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidBecomeKey(_:)),
      name: NSWindow.didBecomeKeyNotification,
      object: nil
    )
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    sidebar.hostDocumentDidChange()
  }

  /**
   Apply the remembered width, once, on the first layout pass.

   **Not `viewWillAppear`, which is where this was written first and was measurably wrong.**
   `setPosition(_:ofDividerAt:)` needs a split view that has laid out; called before the first
   pass it is discarded, AppKit lays the sidebar out at `minimumThickness` instead, and the
   resize that follows *records* that width — so a stored 240 became a stored 180 on the first
   launch and stayed there. Read off the running app: `frame={{0, 0}, {180, 774}}` with
   `workspace.sidebar-width` already overwritten to 180.

   The toolbar migration rides along for a related reason: `EditorViewController` replaces the
   window's placeholder toolbar from *its* `viewWillAppear`, so this is the first moment the
   real toolbar is the one being looked at.
   */
  override func viewDidLayout() {
    super.viewDidLayout()

    guard !hasAppliedStoredWidth else {
      return
    }

    // Before the call, because applying a position lays out again
    hasAppliedStoredWidth = true
    applyStoredSidebarWidth()
    WorkspaceToolbarItems.installIfNeeded(in: view.window)
  }

  /**
   Remember the width the user dragged to.

   `NSSplitViewController` is its own split view's delegate and implements this, so the
   fork overrides rather than observing `NSSplitView.didResizeSubviewsNotification` — one
   less observer, and no chance of a second window's drag arriving here.

   It fires for window resizes and for every frame of a collapse animation too, neither of
   which is a width the user chose. The resize case is harmless: the sidebar holds its
   thickness while the editor takes the change, so the value written is the one already
   stored. The animation case is what `SidebarWidth.record` refuses.
   */
  override func splitViewDidResizeSubviews(_ notification: Notification) {
    super.splitViewDidResizeSubviews(notification)

    // Nothing before the stored width has been applied is a width the user chose — it is the
    // layout AppKit picked while waiting for one, and recording it overwrites what it was
    // waiting for
    guard hasAppliedStoredWidth, let sidebarItem, !sidebarItem.isCollapsed else {
      return
    }

    // The sidebar is expanded and laid out, which is the thing `toggleSidebar(_:)` wants to
    // know: from here on AppKit has a thickness of its own to expand back to
    hasLaidOutSidebar = true
    SidebarWidth.shared.record(sidebarItem.viewController.view.frame.width)
  }

  /**
   Reveal the sidebar at the remembered width the first time a window shows one.

   **Only the first time, and only in a window that launched collapsed.** After AppKit has
   laid the sidebar out once it remembers the thickness itself and its own animation comes
   back to the right place — measured: 320pt, collapsed, expanded, 320pt. What it has nothing
   to remember is a window that launched with the sidebar hidden, and there it expands to
   `minimumThickness`. That is the case this covers.

   **The reveal is not animated in that one case, and two animated versions were tried
   first.** Wrapping `super.toggleSidebar(_:)` in an `NSAnimationContext` group and applying
   the width from the completion handler left the sidebar at 180 with 300 stored; driving
   `sidebarItem.animator().isCollapsed = false` inside the group instead did exactly the same.
   So the collapse animation does not join the caller's group, its completion fires while the
   animation is still running, and a `setPosition` issued there is overwritten by it. A
   `setPosition` *after* the animation settles does stick — checked by hand through lldb —
   which is what leaves a delay as the only way to keep the animation, and a magic number
   timed against an AppKit animation is worse than one unanimated reveal.
   */
  override func toggleSidebar(_ sender: Any?) {
    guard let sidebarItem, sidebarItem.isCollapsed, !hasLaidOutSidebar else {
      return super.toggleSidebar(sender)
    }

    sidebarItem.isCollapsed = false
    applyStoredSidebarWidth()
  }

  /**
   Move the highlight to whatever this window is showing, whenever it comes forward.

   **Why this is needed at all, and why it is not KVO on `representedObject`.**
   `makeWindowControllers` builds this controller *before* it assigns `representedObject`, so
   the sidebar's model is created while the window still has no document and
   `currentFileURL` is nil. After that the selection was only ever set by a click in this
   window's own sidebar — so a second tab, opened any other way, highlighted nothing, and a
   window's highlight said where the user last clicked rather than what the window was
   showing. Measured with a UI test: Open in New Window produced `window=beta.md` and
   `selected=[]`.

   `representedObject` is the precise signal and Swift cannot observe it: NSViewController's
   overlay does not redeclare it `@objc dynamic`, and the compiler rejects the key path
   outright. Old-style string-key-path KVO would work and brings manual teardown with it. The
   window coming forward is the indirect signal, needs neither, and covers every route that
   was broken — a restored document, File ▸ Open, Open in New Window, a reopened closed tab —
   because all of them end with a window becoming key. The one route it does not cover is an
   in-place switch, where the sidebar click is what set the selection in the first place.
   */
  @objc func windowDidBecomeKey(_ notification: Notification) {
    guard notification.object as? NSWindow === view.window else {
      return
    }

    sidebar.hostDocumentDidChange()
  }

  /// This window's sidebar pane, collapsed or not.
  var sidebarItem: NSSplitViewItem? {
    splitViewItems.first { $0.behavior == .sidebar }
  }

  /// Whether a sidebar pane is currently showing. What the menu item's title reads off.
  var showsSidebar: Bool {
    sidebarItem?.isCollapsed == false
  }

  /// Whether this window has a sidebar pane at all, showing or not.
  var hasSidebar: Bool {
    sidebarItem != nil
  }

  /**
   Name the sidebar's menu item for what it will do, the way every document app does.

   `NSSplitViewController` already implements `toggleSidebar(_:)` and already validates it, so
   the item's action is that selector with no target and the responder chain finds this
   controller — which means `super` decides whether it is enabled and this override only
   supplies the title.

   `validateUserInterfaceItem` rather than `validateMenuItem`: `NSSplitViewController` conforms
   to `NSUserInterfaceValidations` and implements the former, and an unrelated
   `validateMenuItem` would take precedence over it with no `super` to fall back to.
   */
  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(toggleSidebar(_:)), let menuItem = item as? NSMenuItem {
      menuItem.title = showsSidebar ? WorkspaceStrings.hideSidebar : WorkspaceStrings.showSidebar
    }

    return super.validateUserInterfaceItem(item)
  }

  /**
   Move the divider to the remembered width.

   A no-op while the sidebar is collapsed: `setPosition` would reveal it, and what reveals the
   sidebar is the toggle and the launch rule, never a width being restored.
   */
  private func applyStoredSidebarWidth() {
    guard showsSidebar else {
      return
    }

    splitView.setPosition(SidebarWidth.shared.width, ofDividerAt: 0)
  }

  private var hasAppliedStoredWidth = false
  private var hasLaidOutSidebar = false

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

  var newFileExtension: String {
    AppPreferences.General.newFilenameExtension.rawValue
  }

  func openInPlace(_ url: URL) {
    guard let windowController = view.window?.windowController as? EditorWindowController else {
      return Logger.assertFail("Missing window controller to switch documents in")
    }

    WorkspaceDocumentSwitcher.shared.switchDocument(to: url, in: windowController)
  }

  /**
   Open `url` in a window of its own, rather than as a tab of this one.

   `openDocument(display: true)` joins the key window's tab group when tabbing is on, and this
   is the one gesture in the fork that exists to *not* do that — Open in New Window is the
   escape hatch for wanting two files at once. So automatic tabbing is turned off around the
   call, which is the pattern `AppDelegate+ClosedTab.swift:47-62` already uses for the same
   reason; the counter is what keeps two quick invocations from restoring it out of order.
   */
  func openInNewWindow(_ url: URL) {
    if Self.inFlightOpens == 0 {
      Self.savedAllowsAutomaticWindowTabbing = NSWindow.allowsAutomaticWindowTabbing
      NSWindow.allowsAutomaticWindowTabbing = false
    }

    Self.inFlightOpens += 1
    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
      Self.inFlightOpens -= 1
      if Self.inFlightOpens == 0 {
        NSWindow.allowsAutomaticWindowTabbing = Self.savedAllowsAutomaticWindowTabbing ?? true
        Self.savedAllowsAutomaticWindowTabbing = nil
      }

      if let error {
        NSSound.beep()
        Logger.log(.error, "Failed to open \(url.lastPathComponent) in a new window: \(error.localizedDescription)")
      }
    }
  }
}

// MARK: - Titlebar

extension NSWindow {
  /**
   Whether this window has a workspace sidebar at all, collapsed or not.

   AppKit stops providing `NSTitlebarBackgroundView` as soon as a split view item with
   `.sidebar` behavior is visible: on macOS 26 and later the titlebar area is drawn by the
   scroll pocket instead, which lives beside the content view rather than under
   `NSTitlebarContainerView`. Verified by dumping that subtree with the sidebar collapsed
   (`NSTitlebarBackgroundView` present, and hidden by `modernTitleBar` anyway) and expanded
   (absent, with an `NSScrollPocket` backdrop view added next to the content view).

   `allowsFullHeightLayout = false` does not bring it back; a visible sidebar is enough.

   **This asks whether the window has a sidebar, not whether one is showing, and the
   difference is a crash.** M2 wrote the narrower question, because the only case it had seen
   was launching with the sidebar already open. Adding the toggle produced the other one:
   `NSSplitViewController` lays the window out from inside `_collapse:splitViewItem:`, at a
   moment when the item is already collapsed and AppKit has not yet put the titlebar
   background view back, so the narrower question answered "not showing" and
   `Logger.assertFail` — fatal in DEBUG — took the app down. Measured from the crash report,
   not inferred: `EditorWindow.updateTitleBarAppearance` under `-[NSSplitViewItem
   _setCollapsed:animated:]`.

   What widening costs is smaller than the crash but is not nothing, and is worth naming: in
   the one window state M2 dumped — collapsed, not fullscreen — the view was present, so the
   assert was not firing there and nothing is lost. The state that was never dumped is
   fullscreen with the toolbar hidden, the one case `updateTitleBarAppearance` actually uses
   this view for. If it were missing there with the sidebar collapsed, this would now be
   silent where it used to shout. That case is still unverified, and it is on the fork's open
   list for exactly this reason.

   Code that customises the titlebar background uses this to tell that expected absence
   from a real one.
   */
  var hasWorkspaceSidebar: Bool {
    (contentViewController as? WorkspaceSplitViewController)?.hasSidebar ?? false
  }
}

// MARK: - Private

private extension WorkspaceSplitViewController {
  /// Shared by every window, because `NSWindow.allowsAutomaticWindowTabbing` is.
  static var inFlightOpens = 0
  static var savedAllowsAutomaticWindowTabbing: Bool?

  /**
   Whether a new window opens with its sidebar showing.

   A folder to show, so it shows. View ▸ Show Sidebar changes it for the window from there;
   what is remembered across launches is the *folder*, not whether a given window had the
   sidebar open, and that is deliberate — restoring a folder into `UserDefaults` while every
   window stayed collapsed would be indistinguishable from having forgotten it.

   **It asks whether a folder is configured, not whether one is open**, so the sidebar also
   shows in the cases where opening it did not work: a pinned folder on a volume that has gone
   away, or one that resolved too slowly for the launch deadline. That shows the empty state,
   which names the problem and offers Choose Folder… — and for the slow case it is the view
   that fills in when the resolve finally lands. Asking the narrower question would have
   answered a folder that failed with a collapsed sidebar and no explanation anywhere.

   A build with no folder ever chosen behaves exactly as it did before this milestone: empty
   sidebar, collapsed.
   */
  static var showsSidebarOnLaunch: Bool {
  #if DEBUG
    if ProcessInfo.processInfo.environment["DEBUG_WORKSPACE_SIDEBAR"] == "YES" {
      return true
    }
  #endif

    return LaunchFolder.shared.isFolderRooted
  }
}

// MARK: - Menu

/**
 View ▸ Show Sidebar, added to a menu bar the fork does not own a line of.

 `Main.storyboard` takes **23 upstream commits a year** — as expensive as `EditorDocument.swift`
 — so the item is inserted at runtime instead. The alternative considered was a toolbar item:
 AppKit ships `NSToolbarItem.Identifier.toggleSidebar`, already localised and already wired to
 the same action, and it is cheap in merge surface (`EditorToolbarItems.swift` takes 6 commits
 a year). It was not taken as the *primary* affordance because a toolbar is customisable —
 someone who removes the item would be left with no way to bring the sidebar back — and because
 without `NSTrackingSeparatorToolbarItem` it would sit among the formatting buttons on the far
 side of the titlebar rather than above the sidebar it toggles. That belongs with the titlebar
 pass the fork already owes, and this item is what the toolbar item would invoke anyway.
 */
@MainActor
enum WorkspaceSidebarMenu {
  static func installIfNeeded() {
    guard !isInstalled, let mainMenu = NSApp.mainMenu else {
      return
    }

    guard let viewMenu = mainMenu.viewMenu else {
      // Reached only if upstream restructures its menu bar, and then it is worth knowing
      // about at the sync rather than by noticing the item is missing.
      return Logger.assertFail("Missing a View menu to add the sidebar toggle to")
    }

    isInstalled = true

    // No target: `NSSplitViewController` implements and validates `toggleSidebar(_:)`, and
    // the responder chain finds whichever window's split view controller is in front.
    let item = NSMenuItem(
      title: WorkspaceStrings.showSidebar,
      action: #selector(NSSplitViewController.toggleSidebar(_:)),
      keyEquivalent: "s"
    )

    item.keyEquivalentModifierMask = [.command, .control]
    item.setAccessibilityIdentifier(Constants.menuItemIdentifier)

    // The top of View, where every other macOS app puts it
    viewMenu.insertItem(item, at: 0)
    viewMenu.insertItem(.separator(), at: 1)
  }

  enum Constants {
    static let menuItemIdentifier = "workspace.menu.toggleSidebar"
  }

  // MARK: - Private

  private static var isInstalled = false
}

private extension NSMenu {
  /**
   The View menu.

   Found by an item AppKit's own menu template puts in it, not by the title "View", which is
   right in exactly one localisation.
   */
  var viewMenu: NSMenu? {
    items.compactMap(\.submenu).first { submenu in
      submenu.items.contains { $0.action == #selector(NSWindow.toggleFullScreen(_:)) }
    }
  }
}

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
 a folder that is not there.
 */
private extension AppDelegate {
  func applyDebugRoot() -> Bool {
    let environment = ProcessInfo.processInfo.environment

    // First, because it is the undo for the two below: the UI suite shares `UserDefaults` with
    // every real launch, so a test that pins a fixture and then deletes it would otherwise
    // leave the person using this app pinned to a folder that no longer exists.
    if environment["DEBUG_WORKSPACE_LAUNCH_RESET"] != nil {
      LaunchFolder.shared.clearPinnedFolder()
      LaunchFolder.shared.mode = .lastUsed
      BookmarkStore.shared.clear()
      return true
    }

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

    // Every folder-rooted launch opens an untitled draft, so this is now the *first* thing
    // that happens in a session rather than a corner: window opens on a blank document, user
    // clicks a file. A blank draft has nothing to save, and a save panel there would make the
    // fork's core gesture ask a question about a document nobody typed in.
    if current.fileURL == nil {
      return discardDraftThenPerform(request)
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

  /**
   Switch away from an untitled draft, silently when it is empty and with a sheet when it is not.

   **Both facts this depends on were measured, and both contradicted the obvious guess.** The
   earlier version asked `!isDocumentEdited && stringValue.isEmpty` and let anything else raise
   a sheet. Once every folder-rooted launch began opening a draft, the first sidebar click of
   every session put up a save panel — `identifier: 'save-panel'`, read off the running app
   through XCUITest, with `previous.close()` bisected out to prove it was not the cause. Tracing
   the switcher's own state on the same launch gave the reason:

   ```
   switchDocument target=alpha.md fileURL=nil edited=true len=1
   discardDraft: flushed  len=1 edited=true
   ```

   So a brand-new document is **already `isDocumentEdited`, and already one character long** —
   a line break the editor puts there itself, before anyone has typed anything. Neither flag
   nor emptiness can tell an untouched draft from a typed one, because an untouched draft is
   not empty and does not claim to be unedited.

   What is left is the content, trimmed. The flush comes first — `updateContent` is the same
   round trip `canClose` makes one step later, so it costs nothing to make it here where the
   answer is still useful — and then:

   - **Nothing but whitespace.** `.changeCleared` and switch, no sheet. The change count is
     cleared because the draft reports itself edited even now, and AppKit would otherwise put
     up the very panel this exists to avoid.
   - **Anything else.** Fall through to `canClose`, which offers to save it. Text is never
     discarded without asking.

   **The cost, stated rather than buried: a draft holding only spaces or newlines is discarded
   silently.** That is the price of the measurement above — the editor's own line break is
   indistinguishable from a typed one — and it buys away a save panel in front of the fork's
   central gesture, on every launch. Worth it, and the only case it loses is a document whose
   entire content is whitespace.

   `pending` is held across the flush, so a second click during the round trip beeps instead of
   starting a second switch.
   */
  private func discardDraftThenPerform(_ request: SwitchRequest) {
    let draft = request.previous
    pending = request

    draft.updateContent { [weak self] in
      guard let self, pending != nil else {
        return
      }

      pending = nil

      guard Self.isBlank(draft.stringValue) else {
        // Something was typed after all, so this is a real document and gets the real question
        pending = request
        return draft.canClose(
          withDelegate: self,
          shouldClose: #selector(document(_:shouldClose:contextInfo:)),
          contextInfo: nil
        )
      }

      // Nothing to save, and nothing to ask about
      draft.updateChangeCount(.changeCleared)
      perform(request)
    }
  }

  /// Whether a draft's content is only the whitespace the editor itself starts a document with.
  /// A new document measures one character long before anyone types — see above.
  private static func isBlank(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
