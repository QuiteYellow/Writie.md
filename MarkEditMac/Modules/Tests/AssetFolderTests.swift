//
//  AssetFolderTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation
import Testing
@testable import Workspace

/// Where a dropped file lands. The rules are all in `drops.md` §1, and the ones with teeth are
/// "copy, never move", "never overwrite", and "leave a file that is already here where it is".
@MainActor
struct AssetFolderTests {
  @Test
  func copiesIntoAssetsBesideTheDocument() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let notes = try scratch.folder(["note.md"])
    let elsewhere = try scratch.folder(["photo.png"])
    let source = elsewhere.appending(path: "photo.png")

    let staged = AssetFolder.staged(source, besideDocumentAt: notes.appending(path: "note.md"))
    #expect(staged == notes.appending(path: "assets").appending(path: "photo.png"))
    #expect(FileManager.default.fileExists(atPath: staged.path(percentEncoded: false)))

    // Copy, never move: a drop must not be the reason a file leaves someone's Desktop
    #expect(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
  }

  /// Two screenshots called `photo.png` are two files, not one overwritten one. The suffix is
  /// upstream's `TextBundleAssets` convention, which this deliberately matches.
  @Test
  func neverOverwritesAnExistingAsset() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let notes = try scratch.folder(["note.md"])
    let document = notes.appending(path: "note.md")
    let first = try scratch.folder(["photo.png"]).appending(path: "photo.png")
    let second = try scratch.folder(["photo.png"]).appending(path: "photo.png")

    #expect(AssetFolder.staged(first, besideDocumentAt: document).lastPathComponent == "photo.png")
    #expect(AssetFolder.staged(second, besideDocumentAt: document).lastPathComponent == "photo-1.png")

    let existing = try FileManager.default.contentsOfDirectory(atPath: notes.appending(path: "assets").path(percentEncoded: false))
    #expect(Set(existing) == ["photo.png", "photo-1.png"])
  }

  /// An extension-less file keeps its shape: `README`, then `README-1`, with no trailing dot.
  @Test
  func numbersAnExtensionLessFileWithoutATrailingDot() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let notes = try scratch.folder(["note.md"])
    let document = notes.appending(path: "note.md")
    let first = try scratch.folder(["README"]).appending(path: "README")
    let second = try scratch.folder(["README"]).appending(path: "README")

    #expect(AssetFolder.staged(first, besideDocumentAt: document).lastPathComponent == "README")
    #expect(AssetFolder.staged(second, besideDocumentAt: document).lastPathComponent == "README-1")
  }

  /**
   A file already inside the document's own folder is linked where it lies.

   The spec says `assets` always applies, and this is the case it did not name: copying a file
   that is already in the folder the note lives in would leave two of it behind, and it is
   already exactly as portable as the copy would be — it travels with the same subtree. Decided
   while building D10, and recorded in `AssetFolder` and the tracker rather than inferred.
   */
  @Test
  func leavesAFileThatIsAlreadyBesideTheDocument() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let notes = try scratch.folder(["note.md", "photo.png", "pictures/deeper.png", "assets/old.png"])
    let document = notes.appending(path: "note.md")

    for name in ["photo.png", "pictures/deeper.png", "assets/old.png"] {
      let source = notes.appending(path: name)
      #expect(AssetFolder.staged(source, besideDocumentAt: document) == source, "\(name) was copied")
    }
  }

  /// A `.textbundle` document is a folder, and upstream already copies into the bundle's own
  /// `assets/`. Asked of the file system rather than of the document's type name, because the
  /// question is "is there a folder to put this beside".
  @Test
  func leavesABundleDocumentToUpstream() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder(["doc.textbundle/text.md"])
    let source = try scratch.folder(["photo.png"]).appending(path: "photo.png")

    let bundle = folder.appending(path: "doc.textbundle")
    #expect(AssetFolder.staged(source, besideDocumentAt: bundle) == source)
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "assets").path(percentEncoded: false)))
  }

  /// An untitled document has nowhere to put anything. `EditorDrops` saves it before the drop
  /// is delivered, so reaching here with no URL means there is nothing to be done.
  @Test
  func leavesADropWithNoDocumentAlone() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let source = try scratch.folder(["photo.png"]).appending(path: "photo.png")
    #expect(AssetFolder.staged(source, besideDocumentAt: nil) == source)
  }

  /// Whatever the file system refuses — the likeliest being a sandbox that grants access to a
  /// document but not to the directory holding it — the drop still inserts a link to the file
  /// where it lies, rather than inserting nothing.
  @Test
  func fallsBackToTheFileItselfWhenTheCopyFails() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let notes = try scratch.folder(["note.md"])
    let document = notes.appending(path: "note.md")
    let source = try scratch.folder(["photo.png"]).appending(path: "photo.png")

    // A *file* called `assets` is not a folder, so creating the folder fails the way a
    // permission error would, which is the case that has to stay non-destructive
    try Data().write(to: notes.appending(path: "assets"))
    #expect(AssetFolder.staged(source, besideDocumentAt: document) == source)
  }
}
