//
//  FolderScannerTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation
import Testing
@testable import Workspace

/// Swift Testing, like the rest of the fork's own tests. Upstream's XCTest suites are
/// untouched and the two run side by side in `ModulesTests`.
@MainActor
struct FolderScannerTests {
  @Test
  func ordersFoldersFirstThenNaturally() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["9.md", "10.md", "Notes/inner.md", "archive/old.md"])
    let nodes = try await FolderScanner.contents(of: root, options: .markdown)

    // Case-insensitive like Finder, so "archive" sorts before "Notes", and 9 before 10
    #expect(nodes.map(\.name) == ["archive", "Notes", "9.md", "10.md"])
    #expect(nodes.map(\.isDirectory) == [true, true, false, false])
  }

  @Test
  func keepsKnownExtensionsAndExtensionLessFiles() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder([
      "keep.md",
      "keep.markdown",
      "keep.txt",
      "Upper.MD",
      "README",
      "drop.png",
      "drop.pdf",
    ])

    let nodes = try await FolderScanner.contents(of: root, options: .markdown)
    #expect(Set(nodes.map(\.name)) == ["keep.md", "keep.markdown", "keep.txt", "Upper.MD", "README"])
  }

  /**
   One directory, and no further.

   This is the change M6 makes: the scanner used to walk the whole tree in one pass, which is
   what forced a 4000-node stop and the silent truncation that came with it. A subfolder is
   now a node with `isDirectory` set and nothing else, and the sidebar asks for its contents
   when the row is expanded.
   */
  @Test
  func listsOneDirectoryAndDoesNotDescend() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["top/middle/bottom.md"])
    let top = try #require(try await FolderScanner.contents(of: root, options: .markdown).first)
    #expect(top.name == "top")
    #expect(top.isDirectory)

    let middle = try #require(try await FolderScanner.contents(of: top.url, options: .markdown).first)
    #expect(middle.name == "middle")

    let bottom = try await FolderScanner.contents(of: middle.url, options: .markdown)
    #expect(bottom.map(\.name) == ["bottom.md"])
  }

  @Test
  func hidesDotFilesUnlessAsked() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder([".hidden.md", "shown.md"])

    let hiding = try await FolderScanner.contents(of: root, options: .markdown)
    #expect(hiding.map(\.name) == ["shown.md"])

    let showing = try await FolderScanner.contents(of: root, options: .markdownShowingHidden)
    #expect(showing.map(\.name) == [".hidden.md", "shown.md"])
  }

  /// The filter is about file *types*, so a dotfile stays hidden until asked for separately —
  /// the same two axes Finder has, and the reason the settings pane carries two switches.
  @Test
  func showsEveryExtensionWhenAskedAndStillHidesDotFiles() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder([".hidden.md", "notes.md", "photo.png", "paper.pdf", "README"])
    let nodes = try await FolderScanner.contents(of: root, options: .everyFile)

    #expect(Set(nodes.map(\.name)) == ["notes.md", "photo.png", "paper.pdf", "README"])
  }

  /**
   The assets folder, hidden by its name and by nothing else.

   Matched lowercased, which is what the old app did and what makes `Assets` and `assets` the
   same folder to this rule. The fixture is spelled `Assets` for exactly that reason — and it
   cannot also hold an `assets`, because the volume this runs on is case-insensitive and the
   two would be one directory.

   `assets-and-more` and the *file* `assets.md` are the cases a sloppier rule gets wrong:
   matching a prefix would hide the first, and not asking whether the thing is a directory
   would hide the second.
   */
  @Test
  func hidesAssetsFoldersByNameWhenAsked() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder([
      "Assets/paper.pdf",
      "assets-and-more/note.md",
      "assets.md",
      "notes.md",
    ])

    let hiding = try await FolderScanner.contents(of: root, options: .hidingAssets)
    #expect(hiding.map(\.name) == ["assets-and-more", "assets.md", "notes.md"])

    let showing = try await FolderScanner.contents(of: root, options: .markdown)
    #expect(showing.map(\.name) == ["Assets", "assets-and-more", "assets.md", "notes.md"])
  }

  @Test
  func treatsAPackageAsAFile() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let root = try scratch.folder(["bundle.textbundle/text.md"])
    let nodes = try await FolderScanner.contents(of: root, options: .textBundle)

    #expect(nodes.map(\.name) == ["bundle.textbundle"])
    #expect(try #require(nodes.first).isDirectory == false)
  }

  @Test
  func anUnreadableDirectoryThrows() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let missing = try scratch.folder()
    try FileManager.default.removeItem(at: missing)

    await #expect(throws: FolderScanner.Failure.unreadable(missing)) {
      try await FolderScanner.contents(of: missing, options: .markdown)
    }
  }
}

// MARK: - Private

private extension FolderScanner.Options {
  static let markdown = Self(
    fileExtensions: ["md", "markdown", "txt"],
    showsAllFiles: false,
    showsHiddenFiles: false,
    hidesAssetsFolders: false
  )

  static let markdownShowingHidden = Self(
    fileExtensions: ["md", "markdown", "txt"],
    showsAllFiles: false,
    showsHiddenFiles: true,
    hidesAssetsFolders: false
  )

  static let everyFile = Self(
    fileExtensions: ["md", "markdown", "txt"],
    showsAllFiles: true,
    showsHiddenFiles: false,
    hidesAssetsFolders: false
  )

  static let hidingAssets = Self(
    fileExtensions: ["md", "markdown", "txt"],
    showsAllFiles: false,
    showsHiddenFiles: false,
    hidesAssetsFolders: true
  )

  static let textBundle = Self(
    fileExtensions: ["textbundle"],
    showsAllFiles: false,
    showsHiddenFiles: false,
    hidesAssetsFolders: false
  )
}
