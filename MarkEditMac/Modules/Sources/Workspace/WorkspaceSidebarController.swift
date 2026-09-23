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
  public init(host: WorkspaceHost, options: FolderScanner.Options) {
    self.model = WorkspaceModel(host: host, options: options)
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
