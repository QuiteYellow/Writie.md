//
//  ProductNameMenu.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit

/*
 Why this sits in the `Workspace` module rather than the app target, when it has nothing to do
 with the sidebar: it needs only AppKit and `Bundle`, and a new *app-target* file costs lines in
 `project.pbxproj` — the worst merge surface in the repository — while a new module file costs
 nothing at all. The module is in practice where the fork's own code lives; the sidebar is
 simply most of it.
 */
/**
 Put the fork's own name in the menu items that spell out the app's.

 AppKit substitutes the **application menu's title** from the bundle — it reads "Writie.md"
 with no help — but it does not touch the item titles, which come from the storyboard as
 literals: "About MarkEdit", "Hide MarkEdit", "Quit MarkEdit", "MarkEdit Help". Measured on
 the renamed build rather than assumed, by reading the live menu bar.

 Done at runtime for the same reason the sidebar's menu item is: those six titles live in
 `Main.storyboard`, which takes **23 upstream commits a year**, and the fork would rather
 spend nothing there.

 **It substitutes rather than replaces**, so the surrounding words survive translation: a
 localised "Acerca de MarkEdit" becomes "Acerca de Writie.md" rather than reverting to
 English. Replacing the titles outright would have quietly un-localised the app menu for
 every language upstream ships.

 What it deliberately leaves alone: the nine strings in `MarkEditMac/Resources/Localizable.xcstrings`
 that name the app — safe mode, the updater's notifications, the extension warnings. That file
 takes **37 commits a year**, the worst in the tree, and those strings are seen rarely or never
 in a fork that has no releases. Fixing them is a string-catalog decision, not a rename one.
 */
@MainActor
public enum ProductNameMenu {
  public static func applyIfNeeded() {
    guard !isApplied, let mainMenu = NSApp.mainMenu else {
      return
    }

    // Nothing to do on a build that has not been renamed, which keeps this inert rather than
    // load-bearing if the product name ever goes back.
    let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    guard let name = displayName ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
          name != Constants.upstreamName else {
      return
    }

    isApplied = true
    rename(mainMenu, from: Constants.upstreamName, to: name)
  }

  // MARK: - Private

  private enum Constants {
    /// Upstream's product name, as the storyboard spells it. Not derived from anything: the
    /// point is to find the literal the fork did not write.
    static let upstreamName = "MarkEdit"
  }

  private static var isApplied = false

  private static func rename(_ menu: NSMenu, from old: String, to new: String) {
    for item in menu.items {
      if item.title.contains(old) {
        item.title = item.title.replacingOccurrences(of: old, with: new)
      }

      if let submenu = item.submenu {
        if submenu.title.contains(old) {
          submenu.title = submenu.title.replacingOccurrences(of: old, with: new)
        }

        rename(submenu, from: old, to: new)
      }
    }
  }
}
