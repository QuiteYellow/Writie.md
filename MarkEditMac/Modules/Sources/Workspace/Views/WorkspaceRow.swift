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
  }
}
