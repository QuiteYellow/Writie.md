//
//  SidebarFilterTests.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation
import Testing
@testable import Workspace

/// The sidebar's own filter preferences. That a change reaches an open window is
/// `WorkspaceModelTests.aFilterChangeReachesAnOpenWindow`, which is the half that needed building.
@MainActor
struct SidebarFilterTests {
  /**
   What a fresh install lists.

   The two defaults that matter are the old Writie app's own answers, kept deliberately: a
   folder of notes lists as notes, and the folder attachments live in stays out of the way.
   `showsHiddenFiles` is off because Finder has it off.
   */
  @Test
  func startsFilteringTheWayTheOldAppDid() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let filter = scratch.filter()
    #expect(filter.showsAllFiles == false)
    #expect(filter.showsHiddenFiles == false)
    #expect(filter.hidesAssetsFolders)
  }

  /**
   A switch turned off stays off across a relaunch.

   The case that a naive `bool(forKey:)` gets wrong is exactly this one: `hidesAssetsFolders`
   defaults to **on**, so "never set" and "set to false" have to be distinguishable or turning
   it off silently does nothing after the next launch.
   */
  @Test
  func remembersEverySwitchIncludingTheOneThatDefaultsToOn() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let filter = scratch.filter()
    filter.showsAllFiles = true
    filter.showsHiddenFiles = true
    filter.hidesAssetsFolders = false

    // A second filter over the same defaults is what a relaunch looks like
    let relaunched = scratch.filter()
    #expect(relaunched.showsAllFiles)
    #expect(relaunched.showsHiddenFiles)
    #expect(relaunched.hidesAssetsFolders == false)
  }

  /// The scan the switches describe, which is the only thing the scanner is ever handed.
  @Test
  func describesTheScanItAsksFor() throws {
    let scratch = try Scratch()
    defer { scratch.tearDown() }

    let filter = scratch.filter()
    filter.showsAllFiles = true
    filter.showsHiddenFiles = true

    let options = filter.options(fileExtensions: ["md"])
    #expect(options.fileExtensions == ["md"])
    #expect(options.showsAllFiles)
    #expect(options.showsHiddenFiles)
    #expect(options.hidesAssetsFolders)
  }
}
