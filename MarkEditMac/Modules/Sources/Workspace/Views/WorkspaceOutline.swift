//
//  WorkspaceOutline.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import SwiftUI

/**
 One level of the file tree, and — through `DisclosureGroup` — every level under it.

 `OutlineGroup` was what M4 used, and it is the wrong shape once the tree is read lazily: it
 owns its expansion state privately, so there is no moment at which the model can be told to
 list a directory and start watching it. `DisclosureGroup` takes a binding, which is exactly
 that hook. The view is recursive, which is fine here because the recursion is through the
 *view type* — `DisclosureGroup<WorkspaceRow, WorkspaceOutline>` is a finite type — and not
 through a value that would have to be built eagerly.

 Only files are tagged, so clicking a folder works the disclosure triangle and nothing else.
 */
struct WorkspaceOutline: View {
  let model: WorkspaceModel
  let nodes: [FileNode]

  var body: some View {
    ForEach(nodes) { node in
      if node.isDirectory {
        DisclosureGroup(isExpanded: expansion(of: node.url)) {
          // Nil while the directory is still being listed, which is a blank row for the
          // instant a local folder takes and a visible gap only on something like a network
          // share — either way better than blocking the expansion on the scan.
          Self(model: model, nodes: model.listing(of: node.url) ?? [])
        } label: {
          row(node)
        }
      } else {
        row(node).tag(node.url)
      }
    }
  }
}

// MARK: - Context menu

private extension WorkspaceOutline {
  /**
   A row and the menu that belongs to it.

   `.contextMenu` per row rather than `.contextMenu(forSelectionType:)` on the list: only
   files carry a selection tag, so a selection-typed menu would have nothing to offer on a
   folder — and New File inside a folder, and Reveal in Finder on one, are two of the four
   things this menu is for.
   */
  func row(_ node: FileNode) -> some View {
    WorkspaceRow(node: node).contextMenu {
      if !node.isDirectory {
        Button {
          model.openInNewWindow(node.url)
        } label: {
          Text("Open in New Window", bundle: .module)
        }
        .accessibilityIdentifier(Self.openInNewWindowIdentifier)
      }

      Button {
        model.newFile(near: node.url)
      } label: {
        Text("New File", bundle: .module)
      }
      .accessibilityIdentifier(Self.newFileIdentifier)

      Divider()

      Button {
        model.beginRenaming(node.url)
      } label: {
        Text("Rename…", bundle: .module)
      }
      .accessibilityIdentifier(Self.renameIdentifier)

      Button {
        model.revealInFinder(node.url)
      } label: {
        Text("Reveal in Finder", bundle: .module)
      }
      .accessibilityIdentifier(Self.revealIdentifier)
    }
  }
}

extension WorkspaceOutline {
  /// Identifiers rather than titles, because a title is ambiguous across the whole app — a
  /// query for "Rename…" also finds the main menu's, and XCUITest refuses to click a query
  /// that matches more than one element. They also earn their place for VoiceOver.
  static let openInNewWindowIdentifier = "workspace.menu.openInNewWindow"
  static let newFileIdentifier = "workspace.menu.newFile"
  static let renameIdentifier = "workspace.menu.rename"
  static let revealIdentifier = "workspace.menu.revealInFinder"
}

// MARK: - Private

private extension WorkspaceOutline {
  /// Built here rather than vended by the model: `Binding`'s accessors are not `Sendable`,
  /// and a `View` is already `@MainActor`, so this is the side of the boundary where making
  /// one costs nothing.
  func expansion(of directory: URL) -> Binding<Bool> {
    Binding {
      model.isExpanded(directory)
    } set: {
      model.setExpanded($0, for: directory)
    }
  }
}
