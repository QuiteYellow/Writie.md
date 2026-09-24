//
//  WorkspaceStrings.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 Fork strings the app target needs, read from the module's own catalog.

 The views take their strings inline with `Text(_:bundle:)`, so only the ones that have to
 cross into the app target live here — today, the titles of the sidebar's menu item.

 They are in `Modules/Sources/Workspace/Resources/Localizable.xcstrings` rather than
 `MarkEditMac/Resources/Localizable.xcstrings`, which takes 37 upstream commits a year and is
 the single worst file in the fork's merge surface to put a line in.
 */
public enum WorkspaceStrings {
  public static var showSidebar: String {
    String(
      localized: "Show Sidebar",
      bundle: .module,
      comment: "Menu item that reveals the folder sidebar. Shown while it is hidden."
    )
  }

  public static var hideSidebar: String {
    String(
      localized: "Hide Sidebar",
      bundle: .module,
      comment: "Menu item that hides the folder sidebar. Shown while it is visible."
    )
  }

  /// Shown when a file dropped on the editor could not be copied in beside the document. The
  /// file system's own message goes underneath it.
  static var dropFailed: String {
    String(
      localized: "The file couldn’t be added to this note",
      bundle: .module,
      comment: "Alert title when a dropped file could not be copied into the note's assets folder."
    )
  }

  /// The button that opens the panel granting access to the folder a drop could not write to.
  /// Worded as upstream words its own File ▸ Grant Folder Access…, because it *is* that.
  static var grantAccess: String {
    String(
      localized: "Grant Access…",
      bundle: .module,
      comment: "Alert button that opens a panel to grant the app access to a folder."
    )
  }

  /// Dismisses an alert without doing what it offered.
  static var cancel: String {
    String(
      localized: "Cancel",
      bundle: .module,
      comment: "Dismisses the rename alert without renaming anything."
    )
  }

  /// The base name a file created from the sidebar gets. A file name rather than interface
  /// text, and localised for the same reason Finder localises "untitled folder".
  static var untitled: String {
    String(
      localized: "Untitled",
      bundle: .module,
      comment: "Base name for a file created from the sidebar, before any number is appended."
    )
  }

  static var untitledFolder: String {
    String(
      localized: "Untitled Folder",
      bundle: .module,
      comment: "Base name for a folder created from the sidebar, before any number is appended."
    )
  }
}
