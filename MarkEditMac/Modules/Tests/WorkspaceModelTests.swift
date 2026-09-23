//
//  WorkspaceModelTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation
import Testing
@testable import Workspace

@MainActor
struct WorkspaceModelTests {
  /**
   The sidebar follows the folder, every time it changes.

   The second change is the one worth a test. `withObservationTracking` fires once and then
   stops, so a model that re-arms wrongly follows the first folder and silently ignores every
   one after it — which looks completely correct until someone picks a second folder, and is
   invisible in the case this fork will spend most of its time in, where the folder is
   restored at launch and never changed.
   */
  @Test
  func followsTheFolderEachTimeItChanges() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let first = try scratch.folder(["one.md"])
    let second = try scratch.folder(["three.md", "two.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, options: .markdown, roots: store)

    #expect(model.root == nil)

    store.useWithoutSaving(first)
    try await waitForListing(["one.md"], in: model)
    #expect(model.root == first)

    store.useWithoutSaving(second)
    try await waitForListing(["three.md", "two.md"], in: model)
    #expect(model.root == second)
  }

  @Test
  func closingTheFolderEmptiesTheSidebar() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["one.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, options: .markdown, roots: store)

    store.useWithoutSaving(folder)
    try await waitForListing(["one.md"], in: model)

    model.closeFolder()
    try await waitFor("the sidebar to have no root") {
      if case .noRoot = model.state {
        return model.root == nil
      }

      return false
    }
  }

  /**
   A subfolder is listed when its row is expanded, and forgotten when it collapses.

   This is what M6 buys in exchange for the whole-tree walk M4 used: the work, and the number
   of directories being watched, are bounded by what is on screen rather than by the size of
   the folder. It is also the reason the 4000-node truncation is gone rather than raised.
   */
  @Test
  func listsASubfolderOnlyOnceItIsExpanded() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["sub/inner.md", "top.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, options: .markdown, roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["sub", "top.md"], in: model)

    let sub = try #require(model.listing(of: root)?.first)
    #expect(sub.isDirectory)
    #expect(model.listing(of: sub.url) == nil)

    model.setExpanded(true, for: sub.url)
    try await waitFor("the expanded subfolder to be listed") {
      model.listing(of: sub.url)?.map(\.name) == ["inner.md"]
    }

    model.setExpanded(false, for: sub.url)
    #expect(model.isExpanded(sub.url) == false)
    #expect(model.listing(of: sub.url) == nil)
  }

  /**
   The root's listing follows the folder on disk, with nothing asking it to.

   The milestone's point. A file created by another app — or by Finder, or by a `git pull` —
   appears without a relaunch, a refocus or a Reload menu item, because the directory is
   watched for as long as it is shown.
   */
  @Test
  func noticesAFileAppearingInTheRoot() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["one.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, options: .markdown, roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["one.md"], in: model)

    try Data().write(to: root.appending(path: "two.md"))
    try await waitForListing(["one.md", "two.md"], in: model, timeout: 5)

    try FileManager.default.removeItem(at: root.appending(path: "one.md"))
    try await waitForListing(["two.md"], in: model, timeout: 5)
  }

  /// And so does an expanded subfolder's, which is the half that needs an observer per
  /// directory rather than one on the root.
  @Test
  func noticesAFileAppearingInAnExpandedSubfolder() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["sub/inner.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, options: .markdown, roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["sub"], in: model)

    let sub = try #require(model.listing(of: root)?.first)
    model.setExpanded(true, for: sub.url)
    try await waitFor("the expanded subfolder to be listed") {
      model.listing(of: sub.url)?.map(\.name) == ["inner.md"]
    }

    try Data().write(to: sub.url.appending(path: "added.md"))
    try await waitFor("the subfolder to pick up the new file", timeout: 5) {
      model.listing(of: sub.url)?.map(\.name) == ["added.md", "inner.md"]
    }
  }

  /// A folder deleted while it is expanded takes its listing, its observer and its expansion
  /// with it — otherwise the model keeps watching a descriptor for a directory nobody can see.
  @Test
  func forgetsAnExpandedSubfolderThatIsDeleted() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["sub/inner.md", "top.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, options: .markdown, roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["sub", "top.md"], in: model)

    let sub = try #require(model.listing(of: root)?.first)
    model.setExpanded(true, for: sub.url)
    try await waitFor("the expanded subfolder to be listed") {
      model.listing(of: sub.url)?.map(\.name) == ["inner.md"]
    }

    try FileManager.default.removeItem(at: sub.url)
    try await waitForListing(["top.md"], in: model, timeout: 5)
    #expect(model.isExpanded(sub.url) == false)
    #expect(model.listing(of: sub.url) == nil)
  }

  @Test
  func aFolderThatCannotBeListedReportsItself() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    try FileManager.default.removeItem(at: folder)

    let store = scratch.store()
    let model = WorkspaceModel(host: nil, options: .markdown, roots: store)

    store.useWithoutSaving(folder)
    try await waitFor("the folder to report itself unreadable") {
      if case .unreadable(let url) = model.state {
        return url == folder
      }

      return false
    }
  }
}

/// The context menu's four verbs, which are the other half of M6.
@MainActor
struct WorkspaceFileActionTests {
  @Test
  func renamingAFileMovesItAndFollowsTheSelection() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["one.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, options: .markdown, roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["one.md"], in: model)

    let original = try #require(model.listing(of: root)?.first).url
    model.selection = original
    model.beginRenaming(original)
    #expect(model.proposedName == "one.md")

    model.proposedName = "renamed.md"
    model.commitRenaming()

    #expect(model.selection?.lastPathComponent == "renamed.md")
    #expect(model.failure == nil)
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "renamed.md").path))

    // And the watcher brings the row itself along, with nothing asking it to
    try await waitForListing(["renamed.md"], in: model, timeout: 5)
  }

  /// A rename that the file system refuses says so. A menu item that silently does nothing
  /// is indistinguishable from one that is broken.
  @Test
  func aRenameThatCollidesReportsWhatTheFileSystemSaid() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["one.md", "two.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, options: .markdown, roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["one.md", "two.md"], in: model)

    let one = try #require(model.listing(of: root)?.first).url
    model.beginRenaming(one)
    model.proposedName = "two.md"
    model.commitRenaming()

    #expect(model.failure?.isEmpty == false)
    #expect(FileManager.default.fileExists(atPath: one.path))
  }

  @Test
  func newFileCreatesAnUnusedNameAndOpensIt() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["Untitled.md"])
    let store = scratch.store()
    let host = RecordingHost()
    let model = WorkspaceModel(host: host, options: .markdown, roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["Untitled.md"], in: model)

    let existing = try #require(model.listing(of: root)?.first).url
    model.newFile(near: existing)

    // Counted the way Finder counts, rather than overwriting what is already there
    #expect(model.failure == nil)
    #expect(host.openedInPlace.map(\.lastPathComponent) == ["Untitled 2.md"])
    // "Untitled 2.md" before "Untitled.md": a space sorts ahead of a dot, which is what
    // `localizedStandardCompare` does and what Finder shows
    try await waitForListing(["Untitled 2.md", "Untitled.md"], in: model, timeout: 5)
  }

  /// A folder's New File lands inside it; a file's lands beside it.
  @Test
  func newFileLandsInsideAFolderAndBesideAFile() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["sub/inner.md"])
    let store = scratch.store()
    let host = RecordingHost()
    let model = WorkspaceModel(host: host, options: .markdown, roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["sub"], in: model)

    let sub = try #require(model.listing(of: root)?.first)
    model.newFile(near: sub.url)
    #expect(host.openedInPlace.last?.deletingLastPathComponent().lastPathComponent == "sub")

    model.setExpanded(true, for: sub.url)
    try await waitFor("the subfolder to list both files", timeout: 5) {
      model.listing(of: sub.url)?.map(\.name) == ["inner.md", "Untitled.md"]
    }

    let inner = try #require(model.listing(of: sub.url)?.last)
    model.newFile(near: inner.url)
    #expect(host.openedInPlace.last?.deletingLastPathComponent().lastPathComponent == "sub")
  }

  @Test
  func openInNewWindowGoesToTheHost() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["one.md"])
    let store = scratch.store()
    let host = RecordingHost()
    let model = WorkspaceModel(host: host, options: .markdown, roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["one.md"], in: model)

    let one = try #require(model.listing(of: root)?.first).url
    model.openInNewWindow(one)
    #expect(host.openedInNewWindow == [one])
    #expect(host.openedInPlace.isEmpty)
  }
}

// MARK: - Private

private protocol WaitsForTheSidebar {}

extension WorkspaceModelTests: WaitsForTheSidebar {}
extension WorkspaceFileActionTests: WaitsForTheSidebar {}

@MainActor
private extension WaitsForTheSidebar {
  func waitForListing(
    _ names: [String],
    in model: WorkspaceModel,
    timeout: TimeInterval = 2,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    try await waitFor("the sidebar to list \(names)", timeout: timeout, sourceLocation: sourceLocation) {
      guard case .loaded(let nodes) = model.state else {
        return false
      }

      return nodes.map(\.name) == names
    }
  }

  /// Observation hops to the main actor and the scan runs in a task of its own, so the answer
  /// arrives a turn or two later rather than synchronously. A change that has to travel
  /// through a vnode event and the model's coalescing delay takes longer again, which is what
  /// the larger `timeout` on those tests is for.
  func waitFor(
    _ description: String,
    timeout: TimeInterval = 2,
    sourceLocation: SourceLocation = #_sourceLocation,
    condition: () -> Bool
  ) async throws {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while Date() < deadline {
      if condition() {
        return
      }

      try await Task.sleep(for: .milliseconds(5))
    }

    Issue.record("Timed out waiting for \(description)", sourceLocation: sourceLocation)
  }
}

private extension FolderScanner.Options {
  static let markdown = Self(fileExtensions: ["md", "markdown", "txt"], showsHiddenFiles: false)
}
