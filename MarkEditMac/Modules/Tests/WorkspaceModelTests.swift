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
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

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
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

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
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

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
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

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
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

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
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

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
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    store.useWithoutSaving(folder)
    try await waitFor("the folder to report itself unreadable") {
      if case .unreadable(let url) = model.state {
        return url == folder
      }

      return false
    }
  }

  /**
   A filter change reaches a window that is already open, and leaves the tree as it was.

   This is the half of group B that had to be built rather than exposed. The scan options used
   to be assembled once, in a `lazy var` in the app target, so a window listed whatever the
   preferences said at the moment it was created — and the *old* rule was worse than stale,
   because the hidden-file half of it came from the save panel's own checkbox.

   Two things are asserted and the second is the one worth a test on its own: the new listing
   arrives, and the expanded subfolder is **still expanded and still listed** afterwards.
   Re-listing through `reload()` would pass the first and fail the second, collapsing the tree
   back to the root every time somebody flipped a switch in Settings.
   */
  @Test
  func aFilterChangeReachesAnOpenWindow() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["assets/photo.png", "sub/inner.md", "sub/inner.png", "note.md", "photo.png"])
    let store = scratch.store()
    let filter = scratch.filter()
    filter.hidesAssetsFolders = true

    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: filter, roots: store)
    store.useWithoutSaving(root)
    try await waitForListing(["sub", "note.md"], in: model)

    let sub = try #require(model.listing(of: root)?.first)
    model.setExpanded(true, for: sub.url)
    try await waitFor("the expanded subfolder to be listed") {
      model.listing(of: sub.url)?.map(\.name) == ["inner.md"]
    }

    filter.showsAllFiles = true
    try await waitForListing(["sub", "note.md", "photo.png"], in: model)
    #expect(model.isExpanded(sub.url), "the tree collapsed when a preference changed")
    try await waitFor("the expanded subfolder to be re-listed") {
      model.listing(of: sub.url)?.map(\.name) == ["inner.md", "inner.png"]
    }

    filter.hidesAssetsFolders = false
    try await waitForListing(["assets", "sub", "note.md", "photo.png"], in: model)
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
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["one.md"], in: model)

    let original = try #require(model.listing(of: root)?.first).url
    model.selection = original
    model.beginRenaming(original)
    #expect(model.proposedName == "one.md")

    model.proposedName = "renamed.md"
    model.commitPrompt()

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
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["one.md", "two.md"], in: model)

    let one = try #require(model.listing(of: root)?.first).url
    model.beginRenaming(one)
    model.proposedName = "two.md"
    model.commitPrompt()

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
    let model = WorkspaceModel(host: host, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

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
    let model = WorkspaceModel(host: host, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

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
    let model = WorkspaceModel(host: host, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["one.md"], in: model)

    let one = try #require(model.listing(of: root)?.first).url
    model.openInNewWindow(one)
    #expect(host.openedInNewWindow == [one])
    #expect(host.openedInPlace.isEmpty)
  }
  /**
   The window's own file gets no "open it elsewhere" items, because they would do nothing.

   Asserted through `isShowing` rather than through the menu, which is a SwiftUI `View` and not
   reachable from a unit test. It reads `selection` rather than the host's document, and that is
   forced: the host's URL is not observable, so a menu built from it is never rebuilt — measured
   against the running app, where both items stayed on offer for the file it was showing.
   */
  @Test
  func doesNotOfferToOpenTheFileTheWindowAlreadyShows() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["alpha.md", "beta.md"])
    let store = scratch.store()
    store.useWithoutSaving(folder)

    let model = WorkspaceModel(host: RecordingHost(), fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    model.selection = folder.appending(path: "alpha.md")
    #expect(model.isShowing(folder.appending(path: "alpha.md")))
    #expect(!model.isShowing(folder.appending(path: "beta.md")))

    // A window with no document offers the items for everything, which is the launch-draft state
    model.selection = nil
    #expect(!model.isShowing(folder.appending(path: "alpha.md")))
  }

  /**
   New Folder asks before it creates, so Cancel leaves nothing behind.

   It used to create "Untitled Folder" and then open the rename alert on it, which looked the same
   and was not: cancelling that alert left the folder on disk. This asserts the order — prompt,
   then create — from both ends.
   */
  @Test
  func newFolderCreatesNothingUntilTheNameIsConfirmed() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["alpha.md"])
    let store = scratch.store()
    store.useWithoutSaving(folder)
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    model.beginNewFolder(near: folder.appending(path: "alpha.md"))
    #expect(model.proposedName == "Untitled Folder")

    // Compared as paths with the trailing slash normalised, not as URLs.
    // `deletingLastPathComponent()` hands back a *directory* URL, whose path keeps a trailing
    // slash that the fixture's own URL does not have — and `URL ==` is string equality, so the
    // two are unequal while naming the same folder. Measured: `path(percentEncoded:)` keeps that
    // slash, where the deprecated `path` used to strip it.
    if case .newFolder(let directory) = model.prompt {
      #expect(folderPath(directory) == folderPath(folder))
    } else {
      Issue.record("New Folder did not ask for a name")
    }
    #expect(try contents(of: folder) == ["alpha.md"], "the folder was created before the name was confirmed")

    model.cancelPrompt()
    #expect(model.prompt == nil)
    #expect(try contents(of: folder) == ["alpha.md"], "cancelling left a folder behind")

    model.beginNewFolder(near: folder.appending(path: "alpha.md"))
    model.proposedName = "Notes"
    model.commitPrompt()
    #expect(try contents(of: folder) == ["Notes", "alpha.md"])

    // A name the user typed that is already taken is an error, not a silent "Notes 2"
    model.beginNewFolder(near: folder.appending(path: "alpha.md"))
    model.proposedName = "Notes"
    model.commitPrompt()
    #expect(model.failure != nil, "a colliding name reported nothing")
    #expect(try contents(of: folder) == ["Notes", "alpha.md"])
  }

  /// A directory's path with any trailing slash removed, so that two spellings of one folder
  /// compare equal. See the comment at the call site for why that is needed at all.
  private func folderPath(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }

  private func contents(of folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
  }
}
