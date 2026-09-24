//
//  WorkspaceSidebarController.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit
import SwiftUI

/**
 Hosts the file tree, so the app can put it in an `NSSplitViewItem` without importing SwiftUI.

 SwiftUI inside an SPM module hosted by AppKit is already how `Statistics`, `SettingsUI`,
 `TextCompletion` and `SharedUI` work in this tree; this is the same shape.

 There is no `setRoot` any more. The folder belongs to `BookmarkStore`, one for the whole app,
 and the model observes it — so a window shows whatever folder is open rather than whichever
 one it was handed when it was built.
 */
@MainActor
public final class WorkspaceSidebarController: NSViewController {
  /// `fileExtensions` are the types the app declares as its own; what else the sidebar lists
  /// is `SidebarFilter.shared`, which the model follows for as long as this window is open.
  public init(host: WorkspaceHost, fileExtensions: Set<String>) {
    self.model = WorkspaceModel(host: host, fileExtensions: fileExtensions)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Created in code, never from a storyboard")
  }

  override public func loadView() {
    view = NSHostingView(rootView: WorkspaceSidebarView(model: model, drawsFooter: !Self.usesAccessoryFooter))
  }

  /// The window is showing a different file now; move the highlight to it. The app calls
  /// this, because the module cannot see a document and should not want to.
  public func hostDocumentDidChange() {
    model.followHostDocument()
  }

  /**
   The root picker, to pin to the bottom of the sidebar's split view item.

   The caller attaches it, because the split view item is the app's. macOS 26 and later only:
   below that `NSSplitViewItemAccessoryViewController` does not exist, and the sidebar view
   draws the picker itself instead.
   */
  @available(macOS 26.0, *)
  public func makeFooterAccessory() -> NSSplitViewItemAccessoryViewController {
    WorkspaceFooterAccessory(model: model)
  }

  /**
   Drop `files` on the row called `rowName`, without a drag — the sidebar's half of the debug
   hook `DEBUG_WORKSPACE_DROP_PATHS` is for the editor.

   It goes through `targetDrop(at:)` and `importDroppedFiles` exactly as `performDragOperation`
   does, taking its point from the frame **the live view reported** for that row. So what it
   proves that a module test cannot is that the rows report their frames at all, and that a
   point inside one resolves to the folder it names.

   **What it still does not prove is the geometry across the two frameworks**: whether the point
   AppKit hands a drag destination lands inside those same frames. That needs a real cross-app
   drag, which cannot be synthesized on this machine, and it stays a manual check.

   Returns false when the row reported no frame, rather than falling back to a point that would
   quietly succeed against the root — a hook that cannot fail is a hook that proves nothing.
   */
  public func debugDrop(_ files: [URL], onRowNamed rowName: String?, moving: Bool) -> Bool {
    guard let point = model.debugDropPoint(row: rowName), let destination = model.targetDrop(at: point) else {
      return false
    }

    model.importDroppedFiles(files, into: destination, moving: moving)
    return true
  }

  // MARK: - Private

  private let model: WorkspaceModel

  /// One rule, read by both the view and the accessory, so the picker can never be drawn
  /// twice or not at all.
  private static var usesAccessoryFooter: Bool {
    if #available(macOS 26.0, *) {
      return true
    }

    return false
  }
}

// MARK: - Accessory

/**
 The root picker as a split view item accessory.

 `automaticallyAppliesContentInsets` defaults to true, so AppKit gives the footer the standard
 sidebar margins and the separator that goes with them — which is the whole reason to prefer
 this over a view pinned inside the sidebar by hand.
 */
@available(macOS 26.0, *)
private final class WorkspaceFooterAccessory: NSSplitViewItemAccessoryViewController {
  init(model: WorkspaceModel) {
    self.model = model
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Created in code, never from a storyboard")
  }

  override func loadView() {
    let hostingView = NSHostingView(rootView: WorkspaceFooterView(model: model))
    // The accessory is laid out to the height its view asks for, and a hosting view only
    // asks for one when it is told to measure its content.
    hostingView.sizingOptions = [.intrinsicContentSize]
    view = hostingView
  }

  // MARK: - Private

  private let model: WorkspaceModel
}
