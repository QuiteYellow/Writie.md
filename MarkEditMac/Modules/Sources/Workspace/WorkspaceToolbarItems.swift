//
//  WorkspaceToolbarItems.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit

/**
 The sidebar's button, at the leading edge of the titlebar where every document app puts it.

 M6 shipped View ▸ Show Sidebar and deliberately did **not** ship a toolbar item. Both reasons
 it gave have since expired, and they are worth naming rather than quietly reversing:

 - *"A toolbar is customisable, so removing the item would leave no way to bring the sidebar
   back."* That was true when the toolbar item was the only affordance being considered. The
   menu item exists now and is not removable, so the button is an accelerator for something
   that always has another way in — ⌃⌘S included.
 - *"Without `NSTrackingSeparatorToolbarItem` it would sit among the formatting buttons on the
   far side of the titlebar."* So the separator goes in with it. `.sidebarTrackingSeparator`
   pins the toolbar's division to the split view's divider, which is what puts the toggle over
   the sidebar rather than over the editor.

 Both identifiers are AppKit's own: already localised, already wired to
 `NSSplitViewController.toggleSidebar(_:)`, and normally built by `NSToolbar` itself without
 the delegate being asked. `item(for:in:)` is a fallback for the case where it does ask — it
 costs four lines and the alternative to having it is an item silently missing.

 **The one thing that is not free is an existing install.** `EditorViewController+UI.swift`
 sets `autosavesConfiguration = true`, and a saved toolbar configuration wins over the
 delegate's default identifiers — so a window that has ever shown this toolbar would come back
 without the new items no matter what `toolbarDefaultItemIdentifiers` returns. That is what
 `installIfNeeded(in:)` is for: once, per install, it inserts them into a toolbar that predates
 them. The flag is what keeps it from being a fight — remove the button afterwards and it
 stays removed.
 */
@MainActor
public enum WorkspaceToolbarItems {
  /**
   The sidebar's share of the toolbar, in order. Prepended to the editor's own.

   The flexible space is what right-aligns the toggle inside the sidebar's section, against
   the divider, where Finder, Mail and Notes all put it — rather than hard against the traffic
   lights, which is where it lands without one.
   */
  public static let identifiers: [NSToolbarItem.Identifier] = [.flexibleSpace, .toggleSidebar, .sidebarTrackingSeparator]

  /// Build one, for the case where `NSToolbar` asks rather than making it itself.
  public static func item(for identifier: NSToolbarItem.Identifier, in window: NSWindow?) -> NSToolbarItem? {
    switch identifier {
    case .toggleSidebar:
      let item = NSToolbarItem(itemIdentifier: .toggleSidebar)
      item.label = WorkspaceStrings.showSidebar
      item.toolTip = "\(WorkspaceStrings.showSidebar) (⌃ ⌘ S)"
      // The literal rather than a line in upstream's `Icons`: this path exists only if AppKit
      // stops supplying the item, and it should not leave anything behind if it never runs.
      item.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: item.label)
      // No target, so the responder chain finds the window's own split view controller —
      // the same arrangement the menu item uses
      item.action = #selector(NSSplitViewController.toggleSidebar(_:))
      item.isBordered = true
      return item

    case .sidebarTrackingSeparator:
      // `NSSplitViewController` rather than the app's own container: what this needs is a
      // split view with a divider at index 0, which is the contract the separator itself
      // states. Naming the app type would also be the one thing keeping this file in the app
      // target, for no gain.
      guard let splitView = (window?.contentViewController as? NSSplitViewController)?.splitView else {
        return nil
      }

      return NSTrackingSeparatorToolbarItem(
        identifier: .sidebarTrackingSeparator,
        splitView: splitView,
        dividerIndex: 0
      )

    default:
      return nil
    }
  }

  /**
   Lay the sidebar's items into a toolbar whose saved configuration predates them.

   **Versioned rather than a bare "done" flag, because the arrangement changed once already**
   — the toggle went from hard against the traffic lights to right-aligned in the sidebar's
   section, which is one more item than the first version wrote. A boolean would have recorded
   "installed" and left the old arrangement in place forever, since a saved toolbar
   configuration wins over `toolbarDefaultItemIdentifiers` and nothing else was ever going to
   rewrite it.

   Runs once per version and then leaves the toolbar alone, so a button removed by hand stays
   removed until the arrangement itself changes again. It strips only what it owns: the toggle,
   the tracking separator, and a flexible space if one is leading — never a flexible space the
   user put somewhere else.
   */
  public static func installIfNeeded(in window: NSWindow?) {
    let defaults = UserDefaults.standard
    guard defaults.integer(forKey: Constants.versionKey) < Constants.version, let toolbar = window?.toolbar else {
      return
    }

    defaults.set(Constants.version, forKey: Constants.versionKey)

    // Reversed, so removing one does not renumber the ones still to be looked at
    for (index, item) in toolbar.items.enumerated().reversed() where Constants.ownedIdentifiers.contains(item.itemIdentifier) {
      toolbar.removeItem(at: index)
    }

    if toolbar.items.first?.itemIdentifier == .flexibleSpace {
      toolbar.removeItem(at: 0)
    }

    for (index, identifier) in identifiers.enumerated() {
      toolbar.insertItem(withItemIdentifier: identifier, at: index)
    }
  }

  // MARK: - Private

  private enum Constants {
    static let versionKey = "workspace.toolbar.sidebar-items-version"

    /// Bump when `identifiers` changes, so existing toolbars are rearranged once.
    static let version = 2

    /// What a re-install is allowed to take out, which is only what it put in.
    static let ownedIdentifiers: Set<NSToolbarItem.Identifier> = [.toggleSidebar, .sidebarTrackingSeparator]
  }
}
