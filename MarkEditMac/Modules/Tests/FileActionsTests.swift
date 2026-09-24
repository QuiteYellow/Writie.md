//
//  FileActionsTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit
import Foundation
import Testing
@testable import Workspace

/**
 The verbs the sidebar's context menu performs on files.

 `rename` and `createFile` came with M6 and are covered by `WorkspaceModelTests` through the
 model; these are the four added afterwards, tested at this level because the interesting part
 of each is its **naming**, not its plumbing. A `copyItem` either works or throws; picking
 "alpha copy 2.md" over "alpha copy.md copy" is a decision that can be wrong quietly.
 */
@MainActor
struct FileActionsTests {
  @Test
  func createsAFolderAndRefusesToReuseATakenName() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    let created = try FileActions.createFolder(in: folder, named: "Notes")
    #expect(created.lastPathComponent == "Notes")
    #expect(isDirectory(created))

    // Not "Notes 2", and not a silent success onto the existing folder either — the name was
    // typed, so a collision is the user's to resolve. `withIntermediateDirectories: true` would
    // have returned happily and reported nothing.
    #expect(throws: (any Error).self) {
      _ = try FileActions.createFolder(in: folder, named: "Notes")
    }
  }

  @Test
  func duplicatesAFileKeepingItsExtension() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["alpha.md"])
    let original = folder.appending(path: "alpha.md")
    try "hello".write(to: original, atomically: true, encoding: .utf8)

    // "alpha copy.md", not "alpha.md copy": a duplicate of a Markdown file is still one, which
    // is the whole reason the extension is split off before the suffix is added.
    let copy = try FileActions.duplicate(original)
    #expect(copy.lastPathComponent == "alpha copy.md")
    #expect(try String(contentsOf: copy, encoding: .utf8) == "hello")

    let second = try FileActions.duplicate(original)
    #expect(second.lastPathComponent == "alpha copy 2.md")
  }

  @Test
  func duplicatesAnExtensionlessFileAndAFolder() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    // Notes folders are full of extension-less files — the scanner lists them deliberately, so
    // duplicating one must not produce a trailing dot.
    let folder = try scratch.folder(["README"])
    let copy = try FileActions.duplicate(folder.appending(path: "README"))
    #expect(copy.lastPathComponent == "README copy")

    let nested = try FileActions.createFolder(in: folder, named: "notes")
    let folderCopy = try FileActions.duplicate(nested)
    #expect(folderCopy.lastPathComponent == "notes copy")
    #expect(isDirectory(folderCopy))
  }

  /**
   Trashing removes the file from its folder.

   It really does trash it, so the test takes the trashed copy back out again — a suite that
   leaves a file in someone's Trash on every run is a suite that litters. The fixture name
   carries a UUID, so the cleanup cannot match anything the person put there themselves.
   */
  @Test
  func movesAFileToTheTrash() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let name = "trash-me-\(UUID().uuidString).md"
    let folder = try scratch.folder([name])
    let url = folder.appending(path: name)
    #expect(FileManager.default.fileExists(atPath: url.path))

    try FileActions.moveToTrash(url)
    #expect(!FileManager.default.fileExists(atPath: url.path))

    let trash = try? FileManager.default.url(
      for: .trashDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: false
    )

    if let trashed = trash?.appending(path: name), FileManager.default.fileExists(atPath: trashed.path) {
      try? FileManager.default.removeItem(at: trashed)
    }
  }

  @Test
  func copiesThePathAsPlainText() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    // A path with a space in it, because the percent-encoded spelling is the plausible mistake
    // here and it is the one that would paste into a terminal as %20.
    let folder = try scratch.folder(["my notes.md"])
    let url = folder.appending(path: "my notes.md")

    FileActions.copyPath(url)
    #expect(NSPasteboard.general.string(forType: .string) == url.path(percentEncoded: false))
  }
}

// MARK: - Private

private extension FileActionsTests {
  func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
  }
}
