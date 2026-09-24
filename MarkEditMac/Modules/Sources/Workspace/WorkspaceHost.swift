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

  /// Show `url` as a tab of this window. The other escape hatch, and the one upstream's
  /// maintainer pointed at when declining a folder view — so it should be at least as good here.
  func openInNewTab(_ url: URL)

  /// Whether the app can open `url` as a document — which decides what a drop does with it.
  /// A Markdown or text file dropped on the editor is a file you want to *read*, so it opens;
  /// a PNG is an attachment, so it is copied into `assets/` and linked. The app answers because
  /// the list of types lives in its `Info.plist`, and asking `NSDocumentController` is the only
  /// way to get the real answer rather than a hardcoded copy of it that drifts.
  func canOpen(_ url: URL) -> Bool

  /**
   Ask for access to `folder`, and say whether it was given.

   The sandbox grants a document's *file*, not the directory holding it, so a note opened from
   outside the workspace folder has nowhere to put an attachment — measured, from a real drag:
   *"couldn’t be copied because you don’t have permission to access “assets”"*. macOS's answer
   to that is a folder the user picks in a panel, which is upstream's own File ▸ Grant Folder
   Access…; the app reuses that machinery so the grant is remembered at every later launch.
   */
  func grantAccess(to folder: URL) async -> Bool

  /// Whether this window may have tabs at all, which is the app's Tabbing Mode preference.
  /// The menu asks so that it can leave the tab item out rather than override the setting.
  var allowsTabs: Bool { get }
}
