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
    view = NSHostingView(rootView: WorkspaceSidebarView(model: model))
  }

  /// The folder the tree lists. Hardcoded at M4; M5 resolves it from a security-scoped bookmark.
  public func setRoot(_ url: URL?) {
    model.setRoot(url)
  }

  // MARK: - Private

  private let model: WorkspaceModel
}
