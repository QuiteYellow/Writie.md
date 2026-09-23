//
//  WorkspaceHost.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 What the sidebar needs from the app, so that it can need nothing else.

 The module cannot see `EditorDocument` or `EditorViewController` — those are app-target
 types — and it should not want to. It knows about `URL`, the app conforms to this and does
 the document work. That inversion is why adding sidebar code never touches
 `project.pbxproj`.

 Methods arrive here when they have a caller. Reveal in Finder is not among them: it is
 `NSWorkspace` and a URL, with no document in it, so the module does it directly rather than
 asking the app to.
 */
@MainActor
public protocol WorkspaceHost: AnyObject {
  /// The file the window is currently showing, if it has one.
  var currentFileURL: URL? { get }

  /// The extension a newly created file should get — the app's own preference, so that a file
  /// made from the sidebar matches one made from File ▸ New.
  var newFileExtension: String { get }

  /// Show `url` in this window, replacing what it is showing.
  func openInPlace(_ url: URL)

  /// Show `url` in a window of its own. The escape hatch for having two files at once, in a
  /// fork whose whole point is that clicking a row replaces the document rather than adding to it.
  func openInNewWindow(_ url: URL)
}
