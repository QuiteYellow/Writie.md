//
//  WorkspaceFooterView.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import SwiftUI

/**
 The root picker: which folder the sidebar is listing, and how to change it.

 It reads `model.root` rather than taking a `URL` so that it follows the folder when another
 window changes it — `root` reads through to `BookmarkStore`, and `@Observable` tracks that
 across the computed property.

 `.menuStyle(.button)` with `.buttonStyle(.accessoryBar)` rather than the `.borderlessButton`
 menu style, which the macOS 27 SDK deprecates in favour of exactly that pair.
 */
struct WorkspaceFooterView: View {
  let model: WorkspaceModel

  @ViewBuilder var body: some View {
    if let root = model.root {
      Menu {
        Button {
          model.chooseFolder()
        } label: {
          Text("Choose Folder…", bundle: .module)
        }

        Button {
          model.closeFolder()
        } label: {
          Text("Close Folder", bundle: .module)
        }
      } label: {
        Label {
          Text(root.lastPathComponent)
            .lineLimit(1)
            .truncationMode(.middle)
        } icon: {
          Image(systemName: "folder")
        }
      }
      .menuStyle(.button)
      .buttonStyle(.accessoryBar)
      .accessibilityIdentifier(Self.rootIdentifier)
    } else {
      Button {
        model.chooseFolder()
      } label: {
        Label {
          Text("Choose Folder…", bundle: .module)
        } icon: {
          Image(systemName: "folder.badge.plus")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.accessoryBar)
      .accessibilityIdentifier(Self.chooseIdentifier)
    }
  }

  /// The control naming the open folder. Reading this is how a test answers "which folder?",
  /// which previously meant counting rows and disclosure triangles in an lldb view dump.
  static let rootIdentifier = "workspace.footer.root"
  static let chooseIdentifier = "workspace.footer.choose"
}
