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

 Methods arrive here when they have a caller: the context menu (Open in New Window, Reveal
 in Finder) is M6's, and adding it then is a cleaner diff than declaring it now.
 */
@MainActor
public protocol WorkspaceHost: AnyObject {
  /// The file the window is currently showing, if it has one.
  var currentFileURL: URL? { get }

  /// Show `url` in this window, replacing what it is showing.
  func openInPlace(_ url: URL)
}
