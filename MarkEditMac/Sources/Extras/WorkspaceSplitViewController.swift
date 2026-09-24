//
//  WorkspaceSplitViewController.swift
//  MarkEditMac
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit
import UniformTypeIdentifiers
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
    hostDocumentDidChange()
  }

  /// Point the sidebar's highlight at whatever this window is showing now — or at nothing,
  /// when that file is outside the folder being listed.
  func hostDocumentDidChange() {
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

    hostDocumentDidChange()
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

  /// The sidebar's debug drop hook, forwarded. The menu item is `WorkspaceLaunch`'s and the
  /// work is the module's; this exists because the controller is private to this class.
  func debugDrop(_ files: [URL], onRowNamed rowName: String?, moving: Bool) -> Bool {
    sidebar.debugDrop(files, onRowNamed: rowName, moving: moving)
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
    // The types the app declares as its own, plus extension-less files, which notes folders
    // are full of and which open as plain text. Everything else about what the sidebar lists
    // is `SidebarFilter`, read at every scan — the hidden-file rule used to come from
    // `AppPreferences.General.showHiddenFiles`, which is the *save panel's* checkbox, and it
    // was captured here once, so neither of the two ways it could change reached a window
    // that was already open.
    fileExtensions: Set(NewFilenameExtension.allCases.map(\.rawValue))
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

  /**
   Whether `url` is something this app *edits*, which is what decides whether a drop opens it
   or attaches it.

   **The two obvious answers are both wrong, and one of them shipped for an hour.**
   `typeForContents(of:)` hands back a type for anything, inventing a dynamic UTI when it has
   to. Pairing it with `documentClass(forType:)` looks like the fix and is not: upstream
   declares a **`public.data` "Binary File"** type — role `Viewer`, for opening a binary in
   read-only mode — so every file on the disk has a document class here, and a dropped PNG
   opened as a document instead of landing in `assets/`. The UI test caught it; the reasoning
   that produced it did not.

   So the question is asked of the app's own declarations, filtered to the types it declares as
   an **Editor**: the Markdown spellings, `.textbundle`, and the plain-text family. Derived
   rather than hardcoded, so a type upstream adds is covered without anyone remembering this.

   A file with no extension is text by the same convention the sidebar lists it under — notes
   folders are full of them and the app opens them as plain text.
   */
  func canOpen(_ url: URL) -> Bool {
    guard !url.pathExtension.isEmpty else {
      return true
    }

    guard let type = UTType(filenameExtension: url.pathExtension) else {
      return false
    }

    return Self.editableTypes.contains { type.conforms(to: $0) }
  }

  func grantAccess(to folder: URL) async -> Bool {
    guard let delegate = NSApp.appDelegate else {
      return false
    }

    NSApp.closeOpenPanels()
    return await delegate.saveGrantedFolderAsBookmark(startingAt: folder)
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

  var allowsTabs: Bool {
    AppPreferences.Window.tabbingMode != .disallowed
  }

  /**
   Open `url` as a tab of this window — the mirror image of `openInNewWindow` above.

   Where that one turns `allowsAutomaticWindowTabbing` off to keep a file out of the tab group,
   this forces tabbing on for one open. The pattern is upstream's own, from
   `EditorViewController+Menu.swift:167` (`createNewTab`): flip `EditorWindow.forcedTabbing` and
   the window's `tabbingMode`, then put both back, so the persisted Tabbing Mode preference is
   never written to. `forcedTabbing` is what `EditorWindow.awakeFromNib` reads, which is why it
   has to be set before the document's window is made and cleared after.

   Restored in the completion handler rather than on the next runloop turn as `createNewTab`
   does, because this open is asynchronous and the next turn can arrive first.
   */
  func openInNewTab(_ url: URL) {
    let window = view.window
    let restoredTabbingMode = window?.tabbingMode

    EditorWindow.forcedTabbing = true
    window?.tabbingMode = .preferred

    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
      EditorWindow.forcedTabbing = false
      if let restoredTabbingMode {
        window?.tabbingMode = restoredTabbingMode
      }

      if let error {
        NSSound.beep()
        Logger.log(.error, "Failed to open \(url.lastPathComponent) in a new tab: \(error.localizedDescription)")
      }
    }
  }
}

// MARK: - Private

private extension WorkspaceSplitViewController {
  /// The types this app declares itself an *editor* of, read out of its own `Info.plist`.
  /// The `Viewer` entries — upstream's `public.data` binary fallback — are deliberately left
  /// out: being able to display a file is not a reason to open one that was dropped as an
  /// attachment. See `canOpen(_:)`.
  static let editableTypes: [UTType] = {
    let declared = Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]]
    return (declared ?? [])
      .filter { $0["CFBundleTypeRole"] as? String == "Editor" }
      .flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
      .compactMap { UTType($0) }
  }()

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

      // The sidebar hears about every other route into a window through `didBecomeKey`, and an
      // in-place switch is the one that never fires it — the window was already key. That was
      // fine while a sidebar click was the only thing that switched in place, because the click
      // had set the highlight itself. It stopped being true the moment a *drop* could switch
      // the document: a note dropped from outside the folder left the previously open row
      // highlighted, saying the window was showing a file it was not. Reported, not theorised.
      (request.windowController.window?.contentViewController as? WorkspaceSplitViewController)?
        .hostDocumentDidChange()
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
