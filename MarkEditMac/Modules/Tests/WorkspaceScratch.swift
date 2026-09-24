//
//  WorkspaceScratch.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation
import Testing
@testable import Workspace

/**
 A throwaway folder tree and `UserDefaults` suite for one test.

 Swift Testing has no `addTeardownBlock`, and a `deinit` cannot reach `@MainActor` state, so
 cleanup is explicit: every test pairs `Scratch()` with `defer { scratch.tearDown() }`. That
 reads more plainly than the XCTest version did anyway — the cleanup sits next to the setup
 instead of at the bottom of the file.

 A suite per test matters more than it looks. `BookmarkStore` writes real bookmark data, and
 sharing `UserDefaults.standard` would let one test decide what the next one restores.
 */
@MainActor
struct Scratch {
  struct Failure: Error {
    let reason: String
  }

  let defaults: UserDefaults

  init() throws {
    let suite = "com.quiteyellow.writie-md.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
      throw Failure(reason: "Could not create a defaults suite named \(suite)")
    }

    self.suite = suite
    self.defaults = defaults
    self.root = URL(filePath: NSTemporaryDirectory())
      .appending(path: "WritieWorkspaceTests-\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  /// A fresh folder inside this test's scratch tree, holding `files`. A path with a slash in
  /// it makes the folders it needs, so `"notes/nested.md"` produces a subfolder.
  func folder(_ files: [String] = []) throws -> URL {
    let folder = root.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    for file in files {
      let url = folder.appending(path: file)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: url)
    }

    return folder
  }

  /// A store over this test's defaults. Two stores over one `Scratch` are what a relaunch
  /// looks like: same persisted state, no shared memory.
  func store() -> BookmarkStore {
    BookmarkStore(defaults: defaults, key: "test.root-bookmark")
  }

  /// The key a `SidebarWidth` over this scratch writes to. Exposed so a test can plant a
  /// stored value that no `record` call would have allowed.
  static let sidebarWidthKey = "test.sidebar-width"

  /// A width store over this test's defaults, same relaunch trick as `store()`.
  func sidebarWidth() -> SidebarWidth {
    SidebarWidth(defaults: defaults, key: Self.sidebarWidthKey)
  }

  /**
   A launch-folder rule over this test's defaults.

   `current` is the live folder it reads and writes, so a test passes the same `BookmarkStore`
   it is asserting on. Two `LaunchFolder`s over one `Scratch` and one `current` are what a
   relaunch looks like — which is the only way to test a rule whose whole job happens once,
   before anything else.
   */
  func launchFolder(current: BookmarkStore) -> LaunchFolder {
    LaunchFolder(defaults: defaults, prefix: "test.launch-folder", current: current)
  }

  /// A filter over this test's defaults, so that what a test lists never depends on the
  /// switches whoever is running it has set in their own copy of the app.
  func filter() -> SidebarFilter {
    SidebarFilter(defaults: defaults, prefix: "test.sidebar-filter")
  }

  func tearDown() {
    UserDefaults.standard.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: root)
  }

  // MARK: - Private

  private let suite: String
  private let root: URL
}

/**
 A `WorkspaceHost` that records rather than opens.

 The real host is the app target's `WorkspaceSplitViewController`, which the module cannot
 see and the tests do not want — what they need to know is which URL the sidebar asked for,
 not what a window did with it.
 */
@MainActor
final class RecordingHost: WorkspaceHost {
  var currentFileURL: URL?
  var newFileExtension = "md"

  /// What the real host reads from `AppPreferences.Window.tabbingMode`. Settable so a test can
  /// ask what the menu does when the user has turned tabs off.
  var allowsTabs = true

  /// What the real host asks `NSDocumentController`, which knows the app's declared types and
  /// is not available to a test. An extension list is the same answer in the cases that matter.
  var openableExtensions: Set<String> = ["md", "markdown", "txt"]

  func canOpen(_ url: URL) -> Bool {
    openableExtensions.contains(url.pathExtension.lowercased())
  }

  /// What the real host answers with a panel. A test says yes or no up front instead.
  var grantsAccess = false
  private(set) var accessAskedFor = [URL]()

  func grantAccess(to folder: URL) async -> Bool {
    accessAskedFor.append(folder)
    return grantsAccess
  }

  private(set) var openedInPlace = [URL]()
  private(set) var openedInNewWindow = [URL]()
  private(set) var openedInNewTab = [URL]()

  func openInPlace(_ url: URL) {
    openedInPlace.append(url)
  }

  func openInNewWindow(_ url: URL) {
    openedInNewWindow.append(url)
  }

  func openInNewTab(_ url: URL) {
    openedInNewTab.append(url)
  }
}

extension Set<String> {
  /// The extensions the app declares as its own, which is what the real sidebar is built with.
  /// Shared by every suite that makes a `WorkspaceModel`.
  static let markdown: Self = ["md", "markdown", "txt"]
}

/**
 Compare two URLs by the folder they name rather than by how they spell it.

 `/var/…` and `/private/var/…` are the same directory, and which spelling comes back depends on
 whether the URL was built here or resolved from a bookmark — so any test that asserts on a
 folder a `BookmarkStore` handed back has to ask this rather than `==`. One copy, shared: two
 would drift, and the one that drifted would be the one nobody ran that day.
 */
@MainActor
func expectSameFolder(_ url: URL?, _ expected: URL, sourceLocation: SourceLocation = #_sourceLocation) throws {
  let url = try #require(url, "No folder", sourceLocation: sourceLocation)
  #expect(try canonicalPath(of: url) == canonicalPath(of: expected), sourceLocation: sourceLocation)
}

@MainActor
func canonicalPath(of url: URL) throws -> String {
  try #require(url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath)
}
