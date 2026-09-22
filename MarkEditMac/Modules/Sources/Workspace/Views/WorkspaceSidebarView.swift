//
//  WorkspaceSidebarView.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import SwiftUI

/**
 The file tree.

 `List` + `OutlineGroup` rather than `NSOutlineView`: there is no `NSOutlineViewDiffableDataSource`
 in the macOS 27 SDK, so an outline view means hand-written `reloadItem(_:reloadChildren:)`
 bookkeeping against a tree that changes underneath it — the shape that produces stale rows.
 `.listStyle(.sidebar)` also carries the system's current source-list appearance for free.

 Only files are tagged, so clicking a folder works the disclosure triangle and nothing else.
 */
struct WorkspaceSidebarView: View {
  @Bindable var model: WorkspaceModel

  var body: some View {
    switch model.state {
    case .noRoot:
      message("No folder is open")
    case .loading:
      ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .loaded(let nodes) where nodes.isEmpty:
      message("This folder is empty")
    case .loaded(let nodes):
      tree(nodes)
    case .unreadable(let url):
      message("\(url.lastPathComponent) can’t be read")
    }
  }
}

// MARK: - Private

private extension WorkspaceSidebarView {
  func tree(_ nodes: [FileNode]) -> some View {
    List(selection: $model.selection) {
      OutlineGroup(nodes, children: \.children) { node in
        if node.isDirectory {
          WorkspaceRow(node: node)
        } else {
          WorkspaceRow(node: node).tag(node.url)
        }
      }
    }
    .listStyle(.sidebar)
  }

  /// Fork strings live in the module's own catalog, read through `Bundle.module`.
  /// `MarkEditMac/Resources/Localizable.xcstrings` takes 37 upstream commits a year and is
  /// never touched here.
  func message(_ key: LocalizedStringKey) -> some View {
    Text(key, bundle: .module)
      .font(.callout)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
