//
//  BookmarkStoreTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation
import Testing
@testable import Workspace

/**
 Swift Testing rather than XCTest: the `Modules` package is already `swift-tools-version: 6.0`,
 the two frameworks coexist in one target, and new fork code should lead rather than follow
 upstream's convention. Upstream's own tests are left alone.
 */
@MainActor
struct BookmarkStoreTests {
  @Test
  func remembersTheFolderAcrossAFreshStore() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    try scratch.store().save(folder)

    // A second store over the same defaults is what the next launch looks like
    let relaunched = scratch.store()
    #expect(relaunched.url == nil, "Nothing is open until restore resolves the bookmark")
    try expectSameFolder(relaunched.restore(), folder)
    try expectSameFolder(relaunched.url, folder)
  }

  /**
   The folder is named identically before and after a relaunch.

   Not pedantry: the sidebar's title, the selection it restores and anything comparing a file
   against its root all key off this URL, so a root reading `/var/…/notes` in one launch and
   `/private/var/…/notes/` in the next is two different roots to every one of them. Both
   differences were real — this is the test that found them.
   */
  @Test
  func namesTheFolderTheSameWayBeforeAndAfterARelaunch() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    let saved = scratch.store()
    try saved.save(folder)

    #expect(scratch.store().restore() == saved.url)
  }

  @Test
  func restoreWithoutASavedFolderOpensNothing() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let store = scratch.store()
    #expect(store.restore() == nil)
    #expect(store.url == nil)
  }

  @Test
  func restoreIsIdempotent() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    try scratch.store().save(folder)

    // Called from launch and again from a window: the second call must not open a second
    // scope, because only one would ever be closed
    let store = scratch.store()
    let first = store.restore()
    #expect(store.restore() == first)
    try expectSameFolder(store.url, folder)
  }

  @Test
  func clearForgetsTheFolder() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    let store = scratch.store()

    try store.save(folder)
    store.clear()
    #expect(store.url == nil)
    #expect(scratch.store().restore() == nil, "Cleared means gone from the next launch too")
  }

  @Test
  func useWithoutSavingIsForgottenByTheNextLaunch() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    let store = scratch.store()

    store.useWithoutSaving(folder)
    #expect(store.url == folder)
    #expect(scratch.store().restore() == nil, "The debug override must not persist")
  }

  @Test
  func savingASecondFolderReplacesTheFirst() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let first = try scratch.folder()
    let second = try scratch.folder()
    let store = scratch.store()

    try store.save(first)
    try store.save(second)
    try expectSameFolder(store.url, second)
    try expectSameFolder(scratch.store().restore(), second)
  }

  /**
   A symlink to a folder cannot be bookmarked at all.

   Measured, not assumed: `bookmarkData` fails it with `NSCocoaErrorDomain` 256, "Could not
   open() the item". Recorded because it is not obvious and it decides the behaviour — the
   store reports `notBookmarkable`, and `WorkspaceModel.chooseFolder` answers that by opening
   the folder for this launch without remembering it, which is the better of the two available
   answers. The open panel resolves symlinks itself, so this is a corner rather than a path
   users walk.
   */
  @Test
  func aSymlinkToAFolderCannotBeRemembered() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    let link = folder.deletingLastPathComponent().appending(path: "link-\(UUID().uuidString)")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)

    let store = scratch.store()
    #expect(throws: BookmarkStore.Failure.notBookmarkable(link)) {
      try store.save(link)
    }
  }

  @Test
  func savingAFolderThatIsGoneThrows() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    try FileManager.default.removeItem(at: folder)

    let store = scratch.store()
    #expect(throws: BookmarkStore.Failure.notBookmarkable(folder)) {
      try store.save(folder)
    }

    #expect(store.url == nil)
    #expect(scratch.store().restore() == nil, "A failed save must not leave a bookmark behind")
  }
}
