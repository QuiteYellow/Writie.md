//
//  WorkspaceDebugStateTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation
import Testing
@testable import Workspace

/**
 The UI suite's undo, which is the fork's only code that writes over a real person's settings.

 It is tested harder than its size suggests because the failure it replaces was not a crash or
 a wrong pixel: a test run silently deleted the security-scoped bookmark for a folder someone
 was working in, and nothing can recreate one of those.
 */
@MainActor
struct WorkspaceDebugStateTests {
  /// The case that matters most: a launch that took no snapshot must not be restored over.
  /// Every real launch is that case.
  @Test
  func restoringWithoutASnapshotChangesNothing() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    scratch.defaults.set("bookmark-data", forKey: "workspace.root-bookmark")
    WorkspaceDebugState.restore(defaults: scratch.defaults)

    #expect(scratch.defaults.string(forKey: "workspace.root-bookmark") == "bookmark-data")
  }

  /// What a test run does, end to end: snapshot, overwrite, put back. The key the test *added*
  /// has to go as well — restoring only the old values would leave a pin nobody chose.
  @Test
  func restoringPutsBackWhatWasThereAndRemovesWhatWasNot() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let defaults = scratch.defaults
    defaults.set("the-real-folder", forKey: "workspace.root-bookmark")
    defaults.set(false, forKey: "workspace.sidebar-filter.hides-assets-folders")

    WorkspaceDebugState.captureIfNeeded(defaults: defaults)

    // Everything a test launch might do: change a value, add one, remove one
    defaults.set("a-fixture", forKey: "workspace.root-bookmark")
    defaults.set("pinned-fixture", forKey: "workspace.launch-folder.pin-bookmark")
    defaults.removeObject(forKey: "workspace.sidebar-filter.hides-assets-folders")

    WorkspaceDebugState.restore(defaults: defaults)

    #expect(defaults.string(forKey: "workspace.root-bookmark") == "the-real-folder")
    #expect(defaults.object(forKey: "workspace.launch-folder.pin-bookmark") == nil)
    #expect(defaults.object(forKey: "workspace.sidebar-filter.hides-assets-folders") as? Bool == false)
  }

  /// Several test launches run before one reset, and each of them calls `captureIfNeeded`.
  /// What has to come back is the state before the *suite*, not what the last test left.
  @Test
  func aSecondCaptureLeavesTheFirstSnapshotAlone() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let defaults = scratch.defaults
    defaults.set("the-real-folder", forKey: "workspace.root-bookmark")

    WorkspaceDebugState.captureIfNeeded(defaults: defaults)
    defaults.set("first-fixture", forKey: "workspace.root-bookmark")
    WorkspaceDebugState.captureIfNeeded(defaults: defaults)
    defaults.set("second-fixture", forKey: "workspace.root-bookmark")

    WorkspaceDebugState.restore(defaults: defaults)
    #expect(defaults.string(forKey: "workspace.root-bookmark") == "the-real-folder")
  }

  /// A restore leaves nothing of its own behind, so the next suite snapshots a clean state
  /// rather than finding a stale one and refusing to capture.
  @Test
  func restoringClearsTheSnapshot() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let defaults = scratch.defaults
    defaults.set("the-real-folder", forKey: "workspace.root-bookmark")
    WorkspaceDebugState.captureIfNeeded(defaults: defaults)
    WorkspaceDebugState.restore(defaults: defaults)

    defaults.set("a-fixture", forKey: "workspace.root-bookmark")
    WorkspaceDebugState.captureIfNeeded(defaults: defaults)
    defaults.set("another-fixture", forKey: "workspace.root-bookmark")
    WorkspaceDebugState.restore(defaults: defaults)

    #expect(defaults.string(forKey: "workspace.root-bookmark") == "a-fixture")
  }
}
