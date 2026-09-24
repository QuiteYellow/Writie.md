//
//  FolderDropTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit
import Testing
@testable import Workspace

/// Dropping a folder on the sidebar, which is the gesture people try first and which the
/// sidebar used to refuse outright — the footer's menu was the only way to change folders.
@MainActor
struct FolderDropTests {
  @Test
  func picksTheFolderOutOfADragThatAlsoCarriesFiles() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["note.md"])
    let pasteboard = NSPasteboard(name: .init("writie.tests.\(UUID().uuidString)"))
    pasteboard.clearContents()
    pasteboard.writeObjects([folder.appending(path: "note.md") as NSURL, folder as NSURL])

    #expect(FolderDrop.folder(in: pasteboard) == folder)
  }

  @Test
  func refusesADragWithNoFolderInIt() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["note.md"])
    let pasteboard = NSPasteboard(name: .init("writie.tests.\(UUID().uuidString)"))
    pasteboard.clearContents()
    pasteboard.writeObjects([folder.appending(path: "note.md") as NSURL])

    #expect(FolderDrop.folder(in: pasteboard) == nil)
  }

  /// A `.textbundle` is a directory the user means as one thing, and dropping one should open
  /// the document rather than list its insides. Same rule the sidebar's own listing uses.
  @Test
  func doesNotTreatAPackageAsAFolder() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["doc.textbundle/text.md"])
    #expect(FolderDrop.isFolder(folder.appending(path: "doc.textbundle")) == false)
    #expect(FolderDrop.isFolder(folder))
  }

  /// The model's half: the drop lands, the sidebar lists the folder, and the targeting
  /// highlight goes away with it.
  @Test
  func aDroppedFolderBecomesTheSidebarsRoot() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["dropped.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    model.isDropTargeted = true
    model.openDroppedFolder(folder)

    #expect(model.isDropTargeted == false)
    try expectSameFolder(model.root, folder)
  }

  /// A *file* dropped on the sidebar is D11a's question — which folder did it land on, copy or
  /// move — and changing the root would be a confident wrong answer to a different gesture.
  @Test
  func aDroppedFileDoesNotChangeTheRoot() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["note.md"])
    let store = scratch.store()
    let model = WorkspaceModel(host: nil, fileExtensions: .markdown, filter: scratch.filter(), roots: store)

    model.openDroppedFolder(folder.appending(path: "note.md"))
    #expect(model.root == nil)
  }
}
