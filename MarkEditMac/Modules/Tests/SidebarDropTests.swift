//
//  SidebarDropTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit
import Testing
@testable import Workspace

/**
 Files dropped into the sidebar — which folder they land in, and whether that is a copy or a
 move. `drops.md` §3.1–3.3.

 Every rule is exercised as a function rather than through a drag, because a drag cannot be
 synthesized on this machine at all. That is a real limit and it is worth naming: what these
 tests cannot see is the geometry — whether the frames the rows report line up with the point
 AppKit hands the overlay. `WorkspaceUITests` covers that half through the debug hook.
 */
@MainActor
struct SidebarDropTests {
  // MARK: - Copy against move

  /// The default, and the one that matters most: a drop must never be the reason a file
  /// leaves someone's Desktop.
  @Test
  func copiesByDefaultFromOutside() {
    #expect(SidebarDrop.operation(from: .outside, modifiers: [], allowedBy: .every) == .copy)
  }

  /// ⌘, not ⌥. Finder's set is ⌘ force move and ⌥ force copy, so the key that is easy to
  /// misremember as "the modify key" is the exact opposite of what is wanted here.
  @Test
  func commandMovesFromOutside() {
    #expect(SidebarDrop.operation(from: .outside, modifiers: .command, allowedBy: .every) == .move)
    #expect(SidebarDrop.operation(from: .outside, modifiers: .option, allowedBy: .every) == .copy)
  }

  /// The other direction defaults the other way: a drag within the tree is a reorganise, and
  /// copying would leave a duplicate behind every time someone tidied a folder.
  @Test
  func movesByDefaultWithinTheSidebar() {
    #expect(SidebarDrop.operation(from: .sidebar, modifiers: [], allowedBy: .every) == .move)
  }

  @Test
  func optionCopiesWithinTheSidebar() {
    #expect(SidebarDrop.operation(from: .sidebar, modifiers: .option, allowedBy: .every) == .copy)
  }

  /**
   A source that will not be moved from is not a reason to delete someone's file.

   `draggingSourceOperationMask` is the source's permission and an operation outside it is
   refused with no explanation, so something has to give when ⌘ asks for a move a source does
   not offer. The fallback is copy — never the other way round, which is the case below.
   */
  @Test
  func neverFallsBackToAMoveTheSourceDidNotOffer() {
    #expect(SidebarDrop.operation(from: .outside, modifiers: .command, allowedBy: .copy) == .copy)
    #expect(SidebarDrop.operation(from: .sidebar, modifiers: [], allowedBy: .copy) == .copy)
  }

  @Test
  func refusesADragWhoseSourceWillNeitherCopyNorMove() {
    #expect(SidebarDrop.operation(from: .outside, modifiers: [], allowedBy: .link).isEmpty)
  }

  // MARK: - Which folder

  @Test
  func aFolderRowTakesTheDropItself() {
    let folder = URL(filePath: "/tmp/notes/sub")
    let node = FileNode(url: folder, isDirectory: true)

    #expect(SidebarDrop.destination(landingOn: node, root: URL(filePath: "/tmp/notes")) == folder)
  }

  /**
   Beside the file, not inside it. The same rule New File and New Folder use — two answers to
   "where does a thing go" would be a bug the day somebody noticed them disagreeing.

   Asserted through `isSameDirectory` rather than `==`, and deliberately: what comes back is
   `…/sub/` with a trailing slash, because that is what `deletingLastPathComponent()` produces,
   and the same spelling difference is what made a file dropped into its own folder duplicate
   itself. The comparison the code uses is the comparison this asserts on.
   */
  @Test
  func aFileRowSendsTheDropToItsFolder() throws {
    let node = FileNode(url: URL(filePath: "/tmp/notes/sub/a.md"), isDirectory: false)
    let destination = try #require(SidebarDrop.destination(landingOn: node, root: URL(filePath: "/tmp/notes")))

    #expect(AssetFolder.isSameDirectory(destination, URL(filePath: "/tmp/notes/sub")))
  }

  /// Empty space under the last row is still a drop, and it means the folder being shown.
  @Test
  func emptySpaceSendsTheDropToTheRoot() {
    let root = URL(filePath: "/tmp/notes")

    #expect(SidebarDrop.destination(landingOn: nil, root: root) == root)
    #expect(SidebarDrop.destination(landingOn: nil, root: nil) == nil)
  }

  @Test
  func readsEveryFileInTheDragRatherThanTheFirst() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["a.md", "b.png"])
    let pasteboard = NSPasteboard(name: .init("writie.tests.\(UUID().uuidString)"))
    pasteboard.clearContents()
    pasteboard.writeObjects([folder.appending(path: "a.md") as NSURL, folder.appending(path: "b.png") as NSURL])

    #expect(SidebarDrop.files(in: pasteboard).map(\.lastPathComponent) == ["a.md", "b.png"])
  }

  // MARK: - The model's targeting

  /// Exactly one highlight at a time: a row, or the whole sidebar, never both.
  @Test
  func aDragOverAFolderRowHighlightsThatRowAlone() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["sub/inner.md", "top.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["sub", "top.md"], in: model)

    // The node's own URL, which is what the view reports: a scanned directory can spell itself
    // differently from one built with `appending(path:)`, and the row's highlight compares
    // with `==` on every redraw.
    let folder = try #require(nodes(of: model).first { $0.isDirectory }).url
    model.rowFrames = [folder: CGRect(x: 0, y: 0, width: 200, height: 20)]

    #expect(model.targetDrop(at: CGPoint(x: 10, y: 10)) == folder)
    #expect(model.dropTarget == folder)
    #expect(model.isDropTargeted == false)
  }

  /// A file at the top level belongs to the root, which has no row of its own — so the whole
  /// sidebar lights up instead, which is also what a drop on empty space gets.
  @Test
  func aDragOverATopLevelFileHighlightsTheWholeSidebar() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["top.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["top.md"], in: model)

    let file = try #require(nodes(of: model).first).url
    model.rowFrames = [file: CGRect(x: 0, y: 0, width: 200, height: 20)]

    #expect(model.targetDrop(at: CGPoint(x: 10, y: 10)) != nil)
    #expect(model.dropTarget == nil)
    #expect(model.isDropTargeted)

    model.endDrop()
    #expect(model.isDropTargeted == false)
  }

  // MARK: - Landing the files

  @Test
  func importsADroppedFileIntoTheFolderItLandedOn() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["sub/inner.md"])
    let elsewhere = try scratch.folder(["photo.png"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    store.useWithoutSaving(root)
    try await waitForListing(["sub"], in: model)

    let destination = root.appending(path: "sub")
    model.importDroppedFiles([elsewhere.appending(path: "photo.png")], into: destination, moving: false)

    #expect(FileManager.default.fileExists(atPath: destination.appending(path: "photo.png").path))
    #expect(FileManager.default.fileExists(atPath: elsewhere.appending(path: "photo.png").path), "a copy leaves the original alone")
    #expect(model.failure == nil)
  }

  @Test
  func aMoveTakesTheFileOutOfWhereItWas() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder([])
    let elsewhere = try scratch.folder(["photo.png"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    store.useWithoutSaving(root)
    model.importDroppedFiles([elsewhere.appending(path: "photo.png")], into: root, moving: true)

    #expect(FileManager.default.fileExists(atPath: root.appending(path: "photo.png").path))
    #expect(FileManager.default.fileExists(atPath: elsewhere.appending(path: "photo.png").path) == false)
  }

  /// The same rule the editor's `assets/` staging uses, which is why they share one
  /// implementation: a second `photo.png` becomes `photo-1.png` rather than replacing the
  /// first. An import that overwrote would be a drop that destroyed something.
  @Test
  func neverOverwritesAFileOfTheSameName() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let destination = try scratch.folder(["photo.png"])
    let elsewhere = try scratch.folder(["photo.png"])
    let landed = try FileActions.importItem(elsewhere.appending(path: "photo.png"), into: destination, moving: false)

    #expect(landed.lastPathComponent == "photo-1.png")
    #expect(FileManager.default.fileExists(atPath: destination.appending(path: "photo.png").path))
  }

  /// A wobble over the wrong row should not leave litter behind. Duplicating in place is what
  /// the context menu's Duplicate is for.
  @Test
  func droppingAFileIntoItsOwnFolderDoesNothing() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["photo.png"])
    let source = folder.appending(path: "photo.png")

    #expect(try FileActions.importItem(source, into: folder, moving: false) == source)
    #expect(try contents(of: folder) == ["photo.png"])
  }

  /// Twelve files into a folder that refuses all of them is one alert, not twelve — and the
  /// files that could land still land.
  @Test
  func reportsOneFailureAndImportsWhatItCan() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder([])
    let elsewhere = try scratch.folder(["photo.png"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    store.useWithoutSaving(root)
    model.importDroppedFiles(
      [
        elsewhere.appending(path: "missing-a.png"),
        elsewhere.appending(path: "photo.png"),
        elsewhere.appending(path: "missing-b.png"),
      ],
      into: root,
      moving: false
    )

    #expect(model.failure != nil)
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "photo.png").path))
  }

  // MARK: - Promises

  /**
   A promised file is imported once it has actually landed — `drops.md` §3.3.

   Driven through `awaitFiles` and `PromiseReader` rather than an `NSFilePromiseReceiver`,
   which cannot be constructed by hand. That is the same seam the editor's session is tested
   through, and it exercises the real off-main callback: the reader hops to the main actor,
   which is the shape a crash was fixed into and must stay in.
   */
  @Test
  func aPromisedFileIsImportedOnceItLands() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder([])
    let temporary = try scratch.folder(["received.png"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    store.useWithoutSaving(root)

    let session = FolderImportSession(destination: root, model: model)
    session.awaitFiles(expecting: 1, buckets: 1)
    PromiseReader.reader(for: session, at: 0)(temporary.appending(path: "received.png"), nil)

    try await waitFor("the received file to be imported") {
      FileManager.default.fileExists(atPath: root.appending(path: "received.png").path)
    }
  }

  /// A promise that fails still calls back, with a URL for a file that was never written.
  /// Importing it would copy nothing and report a file-system error for a file the user never
  /// saw; what it must do is leave the folder alone and take the highlight off.
  @Test
  func aPromiseThatNeverLandsImportsNothing() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder([])
    let temporary = try scratch.folder([])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    store.useWithoutSaving(root)
    model.isDropTargeted = true

    let session = FolderImportSession(destination: root, model: model)
    session.awaitFiles(expecting: 1, buckets: 1)
    PromiseReader.reader(for: session, at: 0)(temporary.appending(path: "never-written.png"), nil)

    try await waitFor("the session to give up") { model.isDropTargeted == false }
    #expect(try contents(of: root).isEmpty)
    #expect(model.failure == nil)
  }

  // MARK: - Private

  private func contents(of folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
  }

  /// The root's listing as the view sees it. Tests take row URLs from here rather than
  /// building them, because the view reports `node.url` and nothing else.
  private func nodes(of model: WorkspaceModel) -> [FileNode] {
    guard case .loaded(let nodes) = model.state else {
      return []
    }

    return nodes
  }
}
