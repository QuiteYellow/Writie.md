//
//  WorkspaceSidebarMenu.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit

/*
 In the module rather than the app target for `ProductNameMenu`'s reason: it needs only AppKit
 and the module's own strings, a new app-target file costs lines in `project.pbxproj`, and a
 module file costs none. It moved here on 2026-09-24 because `WorkspaceSplitViewController.swift`
 reached SwiftLint's 1000-line limit, which is a build failure rather than a warning — the split
 the tracker said should be planned rather than forced.
 */
/**
 View ▸ Show Sidebar, added to a menu bar the fork does not own a line of.

 `Main.storyboard` takes **23 upstream commits a year** — as expensive as `EditorDocument.swift`
 — so the item is inserted at runtime instead. The alternative considered was a toolbar item:
 AppKit ships `NSToolbarItem.Identifier.toggleSidebar`, already localised and already wired to
 the same action, and it is cheap in merge surface (`EditorToolbarItems.swift` takes 6 commits
 a year). It was not taken as the *primary* affordance because a toolbar is customisable —
 someone who removes the item would be left with no way to bring the sidebar back — and because
 without `NSTrackingSeparatorToolbarItem` it would sit among the formatting buttons on the far
 side of the titlebar rather than above the sidebar it toggles. That belongs with the titlebar
 pass the fork already owes, and this item is what the toolbar item would invoke anyway.
 */
@MainActor
public enum WorkspaceSidebarMenu {
  public static func installIfNeeded() {
    guard !isInstalled, let mainMenu = NSApp.mainMenu else {
      return
    }

    guard let viewMenu = mainMenu.viewMenu else {
      // Reached only if upstream restructures its menu bar, and then it is worth knowing
      // about at the sync rather than by noticing the item is missing. `assertionFailure`
      // rather than upstream's `Logger.assertFail`, which the module cannot see: both stop a
      // DEBUG build, and what is lost is a line in the release log for a case that has never
      // happened outside a sync.
      return assertionFailure("Missing a View menu to add the sidebar toggle to")
    }

    isInstalled = true

    // No target: `NSSplitViewController` implements and validates `toggleSidebar(_:)`, and
    // the responder chain finds whichever window's split view controller is in front.
    let item = NSMenuItem(
      title: WorkspaceStrings.showSidebar,
      action: #selector(NSSplitViewController.toggleSidebar(_:)),
      keyEquivalent: "s"
    )

    item.keyEquivalentModifierMask = [.command, .control]
    item.setAccessibilityIdentifier(Constants.menuItemIdentifier)

    // The top of View, where every other macOS app puts it
    viewMenu.insertItem(item, at: 0)
    viewMenu.insertItem(.separator(), at: 1)
  }

  public enum Constants {
    public static let menuItemIdentifier = "workspace.menu.toggleSidebar"
  }

  // MARK: - Private

  private static var isInstalled = false
}

private extension NSMenu {
  /**
   The View menu.

   Found by an item AppKit's own menu template puts in it, not by the title "View", which is
   right in exactly one localisation.
   */
  var viewMenu: NSMenu? {
    items.compactMap(\.submenu).first { submenu in
      submenu.items.contains { $0.action == #selector(NSWindow.toggleFullScreen(_:)) }
    }
  }
}
