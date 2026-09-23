//
//  SidebarWidth.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 How wide the sidebar is, remembered across launches.

 **Why this exists rather than `NSSplitView.autosaveName`.** AppKit's divider autosave is the
 obvious answer and it was measured before it was rejected: the sidebar already came back at
 `144`, `213.5`, `275.5` and `279.5` across four launches, because window *state restoration*
 was carrying the divider. That route is not dependable — it is tied to
 `NSQuitAlwaysKeepsWindows` and to a window actually being restored, so a window opened any
 other way starts from nothing — and `NSSplitView`'s own autosave stores the item's
 **collapsed state** alongside the width, which would silently overrule the fork's launch rule
 (`WorkspaceSplitViewController.showsSidebarOnLaunch`: show a sidebar when there is a folder
 to show). One width, app-wide, written and read by the fork is the narrower thing that was
 actually asked for.

 The bounds are the point of the type. `minimum` is measured rather than chosen — at `144pt`
 the footer truncates the folder's name to an ellipsis, which is the one thing it exists to
 show — and `maximum` keeps a file list from eating a window. A stored width outside them is
 **reset to `default`, not clamped to the boundary**: a value out of range is a value from a
 build with different bounds, and snapping it to the nearest edge would leave the sidebar at
 an extreme nobody chose.

 One store, app-wide, for the same reason `BookmarkStore` is: a width set in one window is the
 width the next window opens at. Tests make their own against a scratch `UserDefaults`.
 */
@MainActor
public final class SidebarWidth {
  public enum Bounds {
    /// Below this the footer truncates the folder's name. Measured, not chosen.
    public static let minimum: Double = 180

    /// A file list wider than this is taking the window from the editor.
    public static let maximum: Double = 480

    /// What a first launch opens at, and what an out-of-range stored width resets to.
    public static let initial: Double = 240
  }

  /// The one the app uses.
  public static let shared = SidebarWidth(defaults: .standard, key: Constants.defaultsKey)

  public init(defaults: UserDefaults, key: String) {
    self.defaults = defaults
    self.key = key
  }

  /// The width a sidebar should open at. Always inside `Bounds`, whatever is stored.
  public var width: Double {
    Self.inBounds(defaults.object(forKey: key) as? Double) ?? Bounds.initial
  }

  /**
   Remember `width`, if it is a width worth remembering.

   Out-of-range values are **ignored rather than stored**, which is not the same rule the
   getter uses and is deliberate. This is called from the split view's resize notification,
   which fires throughout a collapse animation — so it sees every intermediate width on the
   way down to zero. Writing those would replace a good width with a transient one; reading
   one back later would reset it to `initial`. The getter's reset is for a stale value from a
   build whose bounds were different, and that is the only thing that can produce one now.
   */
  public func record(_ width: Double) {
    guard let width = Self.inBounds(width) else {
      return
    }

    defaults.set(width, forKey: key)
  }

  // MARK: - Private

  private enum Constants {
    static let defaultsKey = "workspace.sidebar-width"
  }

  private let defaults: UserDefaults
  private let key: String

  private static func inBounds(_ width: Double?) -> Double? {
    guard let width, width.isFinite, width >= Bounds.minimum, width <= Bounds.maximum else {
      return nil
    }

    return width
  }
}
