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

  /// The base name a file created from the sidebar gets. A file name rather than interface
  /// text, and localised for the same reason Finder localises "untitled folder".
  static var untitled: String {
    String(
      localized: "Untitled",
      bundle: .module,
      comment: "Base name for a file created from the sidebar, before any number is appended."
    )
  }
}
