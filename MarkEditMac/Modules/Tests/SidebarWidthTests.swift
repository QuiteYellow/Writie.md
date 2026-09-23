//
//  SidebarWidthTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation
import Testing
@testable import Workspace

/**
 The bounds are the whole reason `SidebarWidth` is a type rather than two calls to
 `UserDefaults`, so they are what these test — including the asymmetry between reading and
 writing, which looks like an inconsistency until the collapse animation explains it.
 */
@MainActor
struct SidebarWidthTests {
  @Test
  func withoutAStoredWidthItOpensAtTheInitialOne() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    #expect(scratch.sidebarWidth().width == SidebarWidth.Bounds.initial)
  }

  @Test
  func aRememberedWidthSurvivesARelaunch() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    scratch.sidebarWidth().record(321)

    // A second store over the same defaults is what the next launch looks like
    #expect(scratch.sidebarWidth().width == 321)
  }

  /**
   A width from a build whose bounds were different resets, rather than clamping to the edge.

   Clamping would leave the sidebar at an extreme nobody chose — 180pt because a previous
   build allowed 120, say — and it would look like the app had decided to pick a side.
   */
  @Test(arguments: [
    SidebarWidth.Bounds.minimum - 1,
    SidebarWidth.Bounds.maximum + 1,
    0,
    .infinity,
  ])
  func aStoredWidthOutsideTheBoundsResetsToTheInitialOne(stored: Double) throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    scratch.defaults.set(stored, forKey: Scratch.sidebarWidthKey)
    #expect(scratch.sidebarWidth().width == SidebarWidth.Bounds.initial)
  }

  /**
   Recording refuses an out-of-range width instead of resetting to the initial one.

   Deliberately not the rule the getter uses. This is called from every frame of the collapse
   animation, so it sees the sidebar on its way down through 120, 60, 0 — and storing the
   initial width from one of those would replace a width the user chose with one they did not,
   at the moment they asked for the sidebar to go away.
   */
  @Test
  func recordingAWidthOutsideTheBoundsKeepsTheLastGoodOne() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let store = scratch.sidebarWidth()
    store.record(300)

    for collapsing in [120.0, 60, 0] {
      store.record(collapsing)
    }

    #expect(store.width == 300)
  }

  @Test
  func theBoundsAreOrdered() {
    #expect(SidebarWidth.Bounds.minimum < SidebarWidth.Bounds.initial)
    #expect(SidebarWidth.Bounds.initial < SidebarWidth.Bounds.maximum)
  }
}
