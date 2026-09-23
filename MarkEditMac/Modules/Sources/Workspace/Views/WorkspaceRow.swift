//
//  WorkspaceRow.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import SwiftUI

/**
 One row of the file tree.

 SF Symbols rather than `NSWorkspace.icon(forFile:)`: the icon service hits the disk per row
 and returns something sized for the Finder, and a sidebar wants the same weight and tint
 treatment as every other source list in the system.

 The accessibility identifier is what a UI test finds the row by. It earns its place twice:
 it is also what lets someone driving the sidebar with VoiceOver tell one row from another.
 */
struct WorkspaceRow: View {
  let node: FileNode

  var body: some View {
    Label {
      Text(node.name)
        .lineLimit(1)
        .truncationMode(.middle)
    } icon: {
      Image(systemName: node.isDirectory ? "folder" : "doc.text")
    }
    .accessibilityIdentifier(Self.identifier(for: node))
  }

  /// Stable across scans, because it is derived from the name rather than from row position.
  static func identifier(for node: FileNode) -> String {
    "workspace.row.\(node.name)"
  }
}
