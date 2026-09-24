//
//  NSWindow+Workspace.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit

/*
 In the module rather than the app target, and asked of `NSSplitViewController` rather than of
 the fork's own subclass, for `WorkspaceToolbarItems`' reason: the question is about a split
 view item's behavior, which is AppKit's, and a module file costs no `project.pbxproj` lines
 where an app-target one does. It moved here on 2026-09-24, when the app file hit SwiftLint's
 1000-line limit for the second time in a day.
 */
public extension NSWindow {
  /**
   Whether this window has a workspace sidebar at all, collapsed or not.

   AppKit stops providing `NSTitlebarBackgroundView` as soon as a split view item with
   `.sidebar` behavior is visible: on macOS 26 and later the titlebar area is drawn by the
   scroll pocket instead, which lives beside the content view rather than under
   `NSTitlebarContainerView`. Verified by dumping that subtree with the sidebar collapsed
   (`NSTitlebarBackgroundView` present, and hidden by `modernTitleBar` anyway) and expanded
   (absent, with an `NSScrollPocket` backdrop view added next to the content view).

   `allowsFullHeightLayout = false` does not bring it back; a visible sidebar is enough.

   **This asks whether the window has a sidebar, not whether one is showing, and the
   difference is a crash.** M2 wrote the narrower question, because the only case it had seen
   was launching with the sidebar already open. Adding the toggle produced the other one:
   `NSSplitViewController` lays the window out from inside `_collapse:splitViewItem:`, at a
   moment when the item is already collapsed and AppKit has not yet put the titlebar
   background view back, so the narrower question answered "not showing" and
   `Logger.assertFail` — fatal in DEBUG — took the app down. Measured from the crash report,
   not inferred: `EditorWindow.updateTitleBarAppearance` under `-[NSSplitViewItem
   _setCollapsed:animated:]`.

   What widening costs is smaller than the crash but is not nothing, and is worth naming: in
   the one window state M2 dumped — collapsed, not fullscreen — the view was present, so the
   assert was not firing there and nothing is lost. The state that was never dumped is
   fullscreen with the toolbar hidden, the one case `updateTitleBarAppearance` actually uses
   this view for. If it were missing there with the sidebar collapsed, this would now be
   silent where it used to shout. That case is still unverified, and it is on the fork's open
   list for exactly this reason.

   Code that customises the titlebar background uses this to tell that expected absence
   from a real one.
   */
  var hasWorkspaceSidebar: Bool {
    guard let controller = contentViewController as? NSSplitViewController else {
      return false
    }

    return controller.splitViewItems.contains { $0.behavior == .sidebar }
  }
}
