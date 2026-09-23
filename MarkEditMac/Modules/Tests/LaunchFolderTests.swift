//
//  LaunchFolderTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation
import Testing
@testable import Workspace

/**
 Which folder a launch opens with, and — the half that matters more — what it does when that
 folder cannot be opened.

 A relaunch is two `LaunchFolder`s over one `Scratch`: same persisted state, no shared memory.
 That is the only way to test a rule whose entire job happens once, before the first window.
 */
@MainActor
struct LaunchFolderTests {
  @Test
  func lastUsedIsTheDefault() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    #expect(scratch.launchFolder(current: scratch.store()).mode == .lastUsed)
  }

  @Test
  func lastUsedOpensTheFolderThatWasOpenBefore() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    try scratch.store().save(folder)

    let relaunched = scratch.store()
    scratch.launchFolder(current: relaunched).restore()
    try expectSameFolder(relaunched.url, folder)
  }

  @Test
  func theModeSurvivesARelaunch() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    scratch.launchFolder(current: scratch.store()).mode = .custom
    #expect(scratch.launchFolder(current: scratch.store()).mode == .custom)
  }

  /**
   Custom opens the pinned folder, and keeps opening it.

   The point of the mode: the folder opened in between — a session where the user wandered
   somewhere else through the sidebar's footer — does not become the folder the next launch
   comes back to.
   */
  @Test
  func customOpensThePinnedFolderEveryLaunch() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let pinned = try scratch.folder(["pinned.md"])
    let wandered = try scratch.folder(["wandered.md"])

    let first = scratch.store()
    let launch = scratch.launchFolder(current: first)
    launch.pinFolder(pinned)
    #expect(launch.mode == .custom, "Pinning a folder is choosing Custom")
    try expectSameFolder(first.url, pinned, "Pinning opens it now, not just next launch")

    // The session goes somewhere else, the way the sidebar's own footer would take it
    try first.save(wandered)
    try expectSameFolder(first.url, wandered)

    let second = scratch.store()
    scratch.launchFolder(current: second).restore()
    try expectSameFolder(second.url, pinned, "A pin is a pin, whatever was open last")
  }

  /// Switching back to Last Used comes back to where the session actually was, which is what
  /// makes the folder worth recording underneath a pin rather than only instead of one.
  @Test
  func switchingBackToLastUsedOpensTheFolderTheSessionEndedOn() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let pinned = try scratch.folder()
    let wandered = try scratch.folder()

    let first = scratch.store()
    let launch = scratch.launchFolder(current: first)
    launch.pinFolder(pinned)
    try first.save(wandered)

    launch.mode = .lastUsed

    let second = scratch.store()
    scratch.launchFolder(current: second).restore()
    try expectSameFolder(second.url, wandered)
  }

  @Test
  func removingThePinLeavesNothingPinned() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let launch = scratch.launchFolder(current: scratch.store())
    launch.pinFolder(try scratch.folder())
    #expect(launch.hasPinnedFolder)

    launch.clearPinnedFolder()
    #expect(!launch.hasPinnedFolder)
    #expect(launch.pinnedFolderName == nil)
    #expect(!scratch.launchFolder(current: scratch.store()).hasPinnedFolder, "Gone next launch too")
  }

  // MARK: - Failing gracefully

  /**
   Custom mode with nothing pinned falls back rather than opening nothing.

   Reachable in one gesture: choose Custom in Settings and cancel the panel it opens. An empty
   sidebar would be a working app that looks broken, and the mode is still the one the user
   asked for, so the fallback is the last used folder.
   */
  @Test
  func customWithNoPinFallsBackToTheLastUsedFolder() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    try scratch.store().save(folder)

    let relaunched = scratch.store()
    let launch = scratch.launchFolder(current: relaunched)
    launch.mode = .custom
    launch.restore()

    try expectSameFolder(relaunched.url, folder)
  }

  /**
   A pinned folder that has gone opens nothing, and **stays pinned**.

   Both halves are the decision. Nothing opens because quietly opening some *other* folder is
   worse than opening none — the sidebar's empty state says so and offers Choose Folder…. And
   the pin survives, because the usual reason a folder cannot be resolved is a volume that is
   not mounted yet, and discarding the bookmark would lose a folder that is only temporarily
   away.
   */
  @Test
  func aPinnedFolderThatIsGoneOpensNothingAndStaysPinned() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    let launch = scratch.launchFolder(current: scratch.store())
    launch.pinFolder(folder)
    #expect(launch.hasPinnedFolder)

    try FileManager.default.removeItem(at: folder)

    let relaunched = scratch.store()
    let next = scratch.launchFolder(current: relaunched)
    next.restore()

    #expect(relaunched.url == nil, "A folder that is gone opens nothing")
    #expect(next.hasPinnedFolder, "It is still pinned — the volume may come back")
    #expect(next.pinnedFolderName == folder.lastPathComponent, "And it is still named, so the row can say it is unavailable")
  }

  /**
   The name outlives the folder.

   Kept in `UserDefaults` beside the bookmark rather than derived from it, because a bookmark
   that will not resolve has no name to give — and "Archive (unavailable)" is an answer where
   a blank row is not.
   */
  @Test
  func thePinnedFolderIsNamedEvenBeforeItIsResolved() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    scratch.launchFolder(current: scratch.store()).pinFolder(folder)

    #expect(scratch.launchFolder(current: scratch.store()).pinnedFolderName == folder.lastPathComponent)
  }

  /**
   A folder that cannot be bookmarked is reported, not swallowed, and does not become a pin.

   A symlink to a folder is the measured case — `bookmarkData` fails it outright, recorded in
   `BookmarkStoreTests`. A pin that could not be saved would come back as a Custom launch that
   silently opens nothing, every time, so the folder is opened for this session only and the
   Settings row says why.
   */
  @Test
  func aFolderThatCannotBeBookmarkedIsNotPinned() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    let link = folder.deletingLastPathComponent().appending(path: "link-\(UUID().uuidString)")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)

    let current = scratch.store()
    let launch = scratch.launchFolder(current: current)
    launch.pinFolder(link)

    #expect(!launch.hasPinnedFolder, "Nothing was pinned")
    #expect(launch.failure != nil, "And the row can say so")
    #expect(current.url == link, "But the folder is open for this session")
  }

  /**
   `isFolderRooted` answers for a folder that is configured but not open.

   It is what decides whether a launch shows the sidebar and skips the file panel, and asking
   the narrower "is a folder open" would have answered a pin on a disconnected volume with
   upstream's open panel — the one screen that cannot choose a folder.
   */
  @Test
  func aConfiguredFolderCountsEvenWhenItCannotBeOpened() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    #expect(!scratch.launchFolder(current: scratch.store()).isFolderRooted, "A fresh install is not folder-rooted")

    let folder = try scratch.folder()
    scratch.launchFolder(current: scratch.store()).pinFolder(folder)
    try FileManager.default.removeItem(at: folder)

    let relaunched = scratch.store()
    let launch = scratch.launchFolder(current: relaunched)
    launch.restore()

    #expect(relaunched.url == nil, "Nothing could be opened")
    #expect(launch.isFolderRooted, "But this is still a folder-rooted app")
  }

  /**
   A launch does not wait indefinitely for a folder to resolve.

   The requirement is that no folder can hold the app at a blank screen, so the resolve runs
   off the main thread under a deadline. A deadline of zero is the same code path a dead
   network volume takes, and what it must produce is a prompt nil rather than a stall.

   It cannot assert on *how long* a real launch waits — that needs a folder that blocks, which
   means a network mount this suite has no way to create. What it holds is the contract the
   timeout path has to keep: give up, return nothing, leave the bookmark alone.
   */
  @Test
  func aResolveThatMissesItsDeadlineGivesUp() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    try scratch.store().save(folder)

    let store = scratch.store()
    #expect(store.restore(waitingUpTo: .zero) == nil, "Past the deadline, the launch carries on")
    #expect(scratch.store().restore() != nil, "And the folder is still remembered for next time")
  }

  /**
   A resolve that lands after the deadline is still adopted.

   Which is what makes the deadline cost a sidebar that fills in late rather than a folder
   that is lost. Same zero deadline as above; this waits for the late arrival instead of
   asserting on the moment it was missed.
   */
  @Test
  func aLateResolveArrivesAnyway() async throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let folder = try scratch.folder()
    try scratch.store().save(folder)

    let store = scratch.store()
    #expect(store.restore(waitingUpTo: .zero) == nil)

    try await confirmEventually(store.url != nil, "the late resolve to land")
    try expectSameFolder(store.url, folder)
  }
}

// MARK: - Private

private extension LaunchFolderTests {
  /// Same comparison `BookmarkStoreTests` uses, and for the same reason: `/var/…` and
  /// `/private/var/…/` are one directory spelled two ways, and which one arrives depends on
  /// whether the URL was built here or resolved from a bookmark.
  func expectSameFolder(
    _ url: URL?,
    _ expected: URL,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let url = try #require(url, comment ?? "No folder", sourceLocation: sourceLocation)
    #expect(
      try url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
        == expected.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath,
      comment,
      sourceLocation: sourceLocation
    )
  }

  /// Poll until a condition holds, for the one thing here that is genuinely asynchronous —
  /// a bookmark resolving on a background queue after the main-thread waiter gave up.
  func confirmEventually(
    _ condition: @autoclosure () -> Bool,
    _ what: Comment,
    within timeout: Duration = .seconds(2),
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if condition() {
        return
      }

      try await Task.sleep(for: .milliseconds(10))
    }

    Issue.record("Timed out waiting for \(what)", sourceLocation: sourceLocation)
  }
}
