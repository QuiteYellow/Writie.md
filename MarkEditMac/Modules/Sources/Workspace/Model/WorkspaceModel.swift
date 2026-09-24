//
//  WorkspaceModel.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 What the sidebar is showing, and what happens when a row is clicked.

 `@Observable` rather than `ObservableObject`: the SwiftUI view reads the properties it uses
 and re-renders on those, with no `@Published` and no Combine.

 The root is not the model's to own — it belongs to `BookmarkStore`, one folder for the whole
 app — so the model observes it rather than being told about it. That is what makes a folder
 chosen in one window the folder every other window's sidebar shows.

 **That last sentence used to read as a justification, and it is not one.** Asked directly, the
 user called the shared root an oversight: windows should be independent, each with its own root,
 and "Last Used" should restore the root of the window closed last. Scheduled, not done — the
 change is a root per model, a store that can hold more than one, and a launch record of which
 window closed last. `TRACKER.md` ▸ *Backlog* ▸ C10 has the blast radius, including the existing
 test that asserts today's cross-window behaviour.

 **The tree is read one directory at a time.** Expanding a row lists that directory and starts
 watching it; collapsing forgets both, and forgets everything under it, which is what a
 collapsed row means. So the work and the number of open descriptors are bounded by what is
 on screen rather than by the size of the folder.
 */
@MainActor
@Observable
public final class WorkspaceModel {
  /// The root's own listing. Subdirectories have no state of their own — an unreadable one
  /// lists as empty, because a folder the user cannot open is not worth a window-wide error.
  public enum State {
    case noRoot
    case loading
    case loaded([FileNode])
    case unreadable(URL)
  }

  public private(set) var state: State = .noRoot

  /// The folder being listed. Read-only here; `chooseFolder` and `closeFolder` change it.
  public var root: URL? { roots.url }

  /**
   The row drawn as selected. Setting it is what opens a file.

   One property with two writers, which is why `followHostDocument()` exists: a click is the
   sidebar driving the window, and a document arriving is the window driving the sidebar, and
   the second must not be mistaken for the first.
   */
  public var selection: URL? {
    didSet {
      guard !isFollowingHost, let selection, selection != oldValue else {
        return
      }

      open(selection)
    }
  }

  /**
   Point the highlight at whatever the window is showing now.

   Called whenever the window's document changes, which is every route into a window except
   this sidebar: a file restored at launch, File ▸ Open, Open in New Window, a reopened closed
   tab. Without it a window highlights a file only if that file was clicked in *its own*
   sidebar — so a second tab showed nothing selected, and the highlight in a window said where
   the user had last clicked rather than what the window was showing.

   It must not open anything. The window already has the document; re-opening it would be at
   best a no-op the switcher discards and at worst a loop.
   */
  public func followHostDocument() {
    let url = host?.currentFileURL
    guard url != selection else {
      return
    }

    isFollowingHost = true
    selection = url
    isFollowingHost = false
  }

  /// `fileExtensions` are the types the app declares as its own, which only the app knows.
  /// Everything else about what gets listed is `filter`'s, and is followed while it changes.
  public init(
    host: WorkspaceHost?,
    fileExtensions: Set<String>,
    filter: SidebarFilter = .shared,
    roots: BookmarkStore = .shared
  ) {
    self.host = host
    self.fileExtensions = fileExtensions
    self.filter = filter
    self.roots = roots

    observeRoot()
    observeFilter()
    rootDidChange()
  }

  /// What `directory` contains, or nil if it has not been listed — which for a directory
  /// means its row is collapsed, and for the root means the first scan is still running.
  public func listing(of directory: URL) -> [FileNode]? {
    if case .loaded(let nodes) = state, directory == root {
      return nodes
    }

    return listings[directory]
  }

  public func isExpanded(_ directory: URL) -> Bool {
    expanded.contains(directory)
  }

  /// Expanding lists a directory and starts watching it; collapsing forgets both, along with
  /// everything expanded underneath it.
  public func setExpanded(_ isExpanded: Bool, for directory: URL) {
    if isExpanded {
      guard expanded.insert(directory).inserted else {
        return
      }

      load(directory)
    } else {
      guard expanded.remove(directory) != nil else {
        return
      }

      forget(directory)
    }
  }

  // MARK: - Context menu

  /**
   A name being asked for, and what the user has typed so far.

   Two things ask: renaming something that exists, and naming a folder that does not yet. One
   prompt with two cases rather than two alerts, because the view is the same three controls and
   only the title and the confirm button differ.

   View state on the model rather than in the view, because the rows are a recursive
   `WorkspaceOutline` and the alert belongs at the top of the list: threading a binding from
   one to the other means passing it through every level of the tree. `WorkspaceModel` is the
   sidebar's view model, not a domain model, so this is where it belongs anyway.
   */
  public private(set) var prompt: Prompt?
  public var proposedName = ""

  /// Whatever the file system last said, when it said no. Shown as an alert and cleared by it.
  public var failure: String?

  /// Create a file next to `url` — inside it when it is a folder, beside it when it is not —
  /// and open it, which is what makes this one gesture rather than two.
  public func newFile(near url: URL) {
    attempt {
      let created = try FileActions.createFile(
        in: directory(for: url),
        named: WorkspaceStrings.untitled,
        extension: host?.newFileExtension ?? ""
      )

      selection = created
      host?.openInPlace(created)
    }
  }

  public func openInNewWindow(_ url: URL) {
    host?.openInNewWindow(url)
  }

  public func revealInFinder(_ url: URL) {
    FileActions.revealInFinder(url)
  }

  public func isDirectory(_ url: URL) -> Bool {
    node(for: url)?.isDirectory == true
  }

  /// Pick a new folder. Cancelling the panel leaves the current one in place.
  public func chooseFolder() {
    Task { [weak self] in
      guard let self, let folder = await FolderPicker.chooseFolder(startingAt: roots.url) else {
        return
      }

      roots.open(folder)
    }
  }

  /// Whether the sidebar **as a whole** is the target of a drag right now: a folder about to
  /// re-root it, or a file bound for the root, which has no row of its own to light up.
  /// On the model because a drag has to survive the view rebuilding underneath it, and because
  /// anything a SwiftUI view's appearance depends on has to be observable state.
  public var isDropTargeted = false

  /**
   The folder a drag is hovering over, drawn as the target.

   Exactly one of this and `isDropTargeted` is ever set: a drag over a row targets *that*
   folder, and a drag over anything else — empty space under the last row, a top-level file
   whose folder is the root, the "No folder is open" placeholder — targets the whole sidebar,
   because the root has no row of its own to light up.
   */
  public var dropTarget: URL?

  /**
   Where every visible row is, in the sidebar's own coordinate space.

   Written by the view through a `PreferenceKey` and read back here during a drag, which is the
   only way the overlay can answer "which row is under the pointer": it is an `NSView` that
   deliberately fails hit testing, so AppKit will not tell it, and `List` will not either.

   On the model rather than in the view for the reason `drops.md` §5 records — anything a row's
   appearance depends on during a drag has to be observable state, or the highlight never
   redraws.
   */
  public var rowFrames = [URL: CGRect]()

  /// Forget the folder, returning the sidebar to its empty state.
  public func closeFolder() {
    roots.clear()
  }

  /// Start again from the root, collapsed. Watching keeps the tree current on its own, so
  /// this is for the cases watching cannot cover — a new root, or a folder closed.
  public func reload() {
    reset()

    guard let root else {
      state = .noRoot
      return
    }

    state = .loading
    load(root)
  }

  // MARK: - Private

  private enum Constants {
    /// A save, a rename or a Finder copy each land as several vnode events, and a rescan per
    /// event would be several identical listings. Long enough to swallow a burst, short
    /// enough that a file dragged into the folder appears while the user is still looking.
    static let coalescingDelay = Duration.milliseconds(120)
  }

  private weak var host: WorkspaceHost?
  private let fileExtensions: Set<String>
  private let filter: SidebarFilter
  /// Internal rather than private only because `WorkspaceModel+Drops` re-roots from a dropped
  /// folder, and Swift's `private` does not reach across files. Nothing outside the module can
  /// see it either way.
  let roots: BookmarkStore

  /// Read at every scan rather than held, which is what makes a preference change reach a
  /// window that is already open: the old arrangement built this once, in a `lazy var` in the
  /// app target, so a window carried whatever the filter said on the day it was opened.
  private var options: FolderScanner.Options {
    filter.options(fileExtensions: fileExtensions)
  }

  private var isFollowingHost = false
  private var listings = [URL: [FileNode]]()
  private var expanded = Set<URL>()
  private var scanTasks = [URL: Task<Void, Never>]()
  private var watchers = [URL: Task<Void, Never>]()

  /**
   Follow `BookmarkStore.url`.

   `withObservationTracking` fires **once** and has to be re-armed, and it fires *before* the
   new value lands, off any actor. So the reaction hops back to the main actor — where it
   reads the folder that was actually set — and re-arms. Missing the re-arm is the silent
   failure: the first folder change would work and every one after it would be ignored.
   */
  private func observeRoot() {
    withObservationTracking {
      _ = roots.url
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.observeRoot()
        self?.rootDidChange()
      }
    }
  }

  /**
   Follow `SidebarFilter`, for every window the app has open.

   Same re-arm as `observeRoot`, and the same silent failure if it is missed. Each property is
   read in the tracked block because `withObservationTracking` follows the ones it sees read,
   not the object — a filter is three switches and any of them changes what is listed.
   */
  private func observeFilter() {
    withObservationTracking {
      _ = filter.showsAllFiles
      _ = filter.showsHiddenFiles
      _ = filter.hidesAssetsFolders
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.observeFilter()
        self?.filterDidChange()
      }
    }
  }

  /**
   Re-list everything on screen, leaving the shape of the tree alone.

   Deliberately not `reload()`, which resets expansion: changing a preference would then
   collapse the tree back to the root and lose wherever the user had navigated to. A folder
   that the new filter hides is dropped by `apply`, which already prunes a subdirectory that
   has gone — a hidden folder and a deleted one are the same thing to the tree.
   */
  private func filterDidChange() {
    guard let root else {
      return
    }

    for directory in [root] + Array(listings.keys) {
      rescan(directory)
    }
  }

  private func rootDidChange() {
    // A new folder may well contain the file this window is already showing, and if it does
    // that row should be the selected one rather than nothing.
    followHostDocument()
    reload()
  }

  private func reset() {
    for task in Array(scanTasks.values) + Array(watchers.values) {
      task.cancel()
    }

    scanTasks = [:]
    watchers = [:]
    listings = [:]
    expanded = []
  }

  /// List a directory and watch it. Both, always — a listing with no observer goes stale
  /// silently, which is the failure this milestone exists to remove.
  private func load(_ directory: URL) {
    watch(directory)
    rescan(directory)
  }

  private func rescan(_ directory: URL) {
    scanTasks[directory]?.cancel()
    let options = options

    scanTasks[directory] = Task { [weak self] in
      let nodes = try? await FolderScanner.contents(of: directory, options: options)
      guard !Task.isCancelled, let self else {
        return
      }

      apply(nodes, to: directory)
    }
  }

  private func apply(_ nodes: [FileNode]?, to directory: URL) {
    let before = Self.subdirectories(of: listing(of: directory))

    if directory == root {
      state = nodes.map { State.loaded($0) } ?? .unreadable(directory)
    } else {
      // A subfolder that cannot be read lists as empty rather than failing anything; only
      // the root being unreadable is worth telling the user about.
      listings[directory] = nodes ?? []
    }

    // A subfolder that was in this directory and no longer is has been deleted or renamed,
    // so its listing, its observer and its expansion go with it — otherwise the model keeps
    // a descriptor open on a directory nobody can see.
    for url in before.subtracting(Self.subdirectories(of: nodes)) {
      forget(url)
    }
  }

  private func watch(_ directory: URL) {
    watchers[directory]?.cancel()

    watchers[directory] = Task { [weak self] in
      for await _ in await DirectoryObserver.events(for: directory) {
        try? await Task.sleep(for: Constants.coalescingDelay)
        guard !Task.isCancelled else {
          return
        }

        self?.rescan(directory)
      }
    }
  }

  /**
   Drop a directory and everything under it: listings, observers and expansion state.

   It descends through the listings the model already holds rather than matching path
   prefixes, because **two URLs for the same directory do not reliably compare equal here.**
   `FileManager.contentsOfDirectory(at:)` hands back children under `/private/var` when the
   directory it was given is under `/var`, so a child's parent path and its parent's own path
   differ by that prefix — measured, after this pruning silently did nothing. M5 met the same
   disagreement from the other side, where a bookmark resolved to `/private/var` and
   `resolvingSymlinksInPath()` normalised the other way.

   The rule that follows is worth keeping: compare URLs only against URLs of the same
   lineage. Everything reached from here came out of a scan, as did everything it is compared
   with, so the equality holds by construction rather than by canonicalising and hoping.
   */
  private func forget(_ directory: URL) {
    for subdirectory in Self.subdirectories(of: listings[directory]) {
      forget(subdirectory)
    }

    scanTasks.removeValue(forKey: directory)?.cancel()
    watchers.removeValue(forKey: directory)?.cancel()
    listings.removeValue(forKey: directory)
    expanded.remove(directory)
  }

  /// Run a file operation and put whatever it says on screen. The alternative is a menu item
  /// that sometimes does nothing, which is indistinguishable from one that is broken.
  private func attempt(_ operation: () throws -> Void) {
    do {
      try operation()
    } catch {
      failure = error.localizedDescription
    }
  }

  private func open(_ url: URL) {
    // Directories expand and collapse, they don't replace the document. The view doesn't tag
    // them as selectable either; this is the half that doesn't depend on the view getting it
    // right, and it also covers a selection restored before the scan finished.
    guard node(for: url)?.isDirectory == false else {
      return
    }

    host?.openInPlace(url)
  }

  /// Where a "new" thing goes: inside `url` when it is a folder, beside it when it is a file.
  /// One copy, because New File and New Folder must not disagree about it.
  private func directory(for url: URL) -> URL {
    node(for: url)?.isDirectory == true ? url : url.deletingLastPathComponent()
  }

  /// Looked up across every directory currently listed, rather than derived from the URL's
  /// parent path: a bookmark-resolved root carries a trailing slash that a URL built by hand
  /// does not, and matching on the node's own `url` is the comparison that cannot disagree.
  func node(for url: URL) -> FileNode? {
    if case .loaded(let nodes) = state, let match = nodes.first(where: { $0.url == url }) {
      return match
    }

    for nodes in listings.values {
      if let match = nodes.first(where: { $0.url == url }) {
        return match
      }
    }

    return nil
  }

  private static func subdirectories(of nodes: [FileNode]?) -> Set<URL> {
    Set((nodes ?? []).lazy.filter(\.isDirectory).map(\.url))
  }
}

// MARK: - Context menu verbs

/**
 The actions M6's menu did not have, in an extension rather than in the class body.

 Not only for `type_body_length`, though it is what forced the move: everything here is a verb
 the menu calls once and reads nothing back from, while the class body above owns the state —
 the listings, the watchers, the selection. Keeping the two apart makes the class the smaller
 half, which is the half worth reading first.
 */
extension WorkspaceModel {
  public enum Prompt: Equatable {
    case renaming(URL)
    case newFolder(in: URL)
  }

  public func beginRenaming(_ url: URL) {
    prompt = .renaming(url)
    proposedName = url.lastPathComponent
  }

  /**
   Ask for a folder's name. **Nothing is created until the name is confirmed.**

   It used to create "Untitled Folder" and then open the rename alert on it, which read the same
   and was not: Cancel left the folder behind. Asking first is what makes Cancel mean cancel.
   */
  public func beginNewFolder(near url: URL) {
    prompt = .newFolder(in: directory(for: url))
    proposedName = WorkspaceStrings.untitledFolder
  }

  public func cancelPrompt() {
    prompt = nil
  }

  public func commitPrompt() {
    guard let prompt else {
      return
    }

    self.prompt = nil
    let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      return
    }

    switch prompt {
    case .renaming(let url):
      commitRenaming(url, to: name)
    case .newFolder(let directory):
      attempt {
        _ = try FileActions.createFolder(in: directory, named: name)
      }
    }
  }

  private func commitRenaming(_ url: URL, to name: String) {
    guard name != url.lastPathComponent else {
      return
    }

    attempt {
      let renamed = try FileActions.rename(url, to: name)
      // The row the user was looking at, still selected under its new name. The watcher will
      // replace the listing a moment later; setting it here means the selection does not
      // blink through nothing in between.
      if selection == url {
        selection = renamed
      }
    }
  }

  public func openInNewTab(_ url: URL) {
    host?.openInNewTab(url)
  }

  /**
   Whether this window is already showing `url`, in which case opening it elsewhere does nothing:
   `NSDocumentController` finds the document it already has and brings its window forward.

   It compares against `selection`, and that is forced rather than chosen. The honest source for
   "what would actually happen" is the window's document — `WorkspaceHost.currentFileURL` — but
   that is a plain property on an app-target view controller, not `@Observable` state, so a menu
   built from it is never rebuilt when the document changes. **Measured: comparing against the
   host left both items showing for the open file**, with the window's title and the highlighted
   row both saying `alpha.md`. `selection` is observable, so writing it re-renders the row and the
   menu with it.

   The two agree for every route into a window: a click sets `selection` to this URL, and every
   other route goes through `followHostDocument()`, which sets it from the document. They can
   diverge if a switch is cancelled at a save sheet, which leaves the highlight ahead of the
   document — a pre-existing divergence, and in that state these two items go missing for a
   moment. Worth knowing; not worth an unobservable comparison that never updates at all.
   */
  public func isShowing(_ url: URL) -> Bool {
    selection == url
  }

  /// Whether the menu should offer a tab at all. False with no host, which is the state a unit
  /// test builds the model in — a menu item that cannot work should not be drawn.
  public var allowsTabs: Bool {
    host?.allowsTabs ?? false
  }

  /// Duplicate a file or folder beside itself. It is deliberately not opened: a duplicate is
  /// made to be kept or renamed, and replacing the document the user is in would be a surprise.
  public func duplicate(_ url: URL) {
    attempt {
      _ = try FileActions.duplicate(url)
    }
  }

  /**
   Move a file or folder to the Trash.

   Nothing is done about the selection or the document here. The watcher notices the row has
   gone and removes it, and a window whose file was trashed keeps the document it already has in
   memory — which is what AppKit does for any file deleted underneath it, and is recoverable
   from the Trash. Trying to be cleverer than that means deciding what a window should show
   instead, and there is no better answer than what it is showing.
   */
  public func moveToTrash(_ url: URL) {
    attempt {
      try FileActions.moveToTrash(url)
    }
  }

  public func copyPath(_ url: URL) {
    FileActions.copyPath(url)
  }
}
