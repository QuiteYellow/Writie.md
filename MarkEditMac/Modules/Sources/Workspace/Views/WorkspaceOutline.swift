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

   `.contextMenu` per row rather than `.contextMenu(forSelectionType:)` on the list: only files
   carry a selection tag, so a selection-typed menu would have nothing to offer on a folder — and
   New File inside a folder, New Folder, Duplicate, Move to Trash and Reveal in Finder all mean
   something on one.

   Split into four groups because `@ViewBuilder` closures take at most ten views, and because the
   dividers are the grouping: open it elsewhere, make something new, change this one, find it.
   */
  func row(_ node: FileNode) -> some View {
    WorkspaceRow(node: node).contextMenu {
      openItems(node)
      Divider()
      newItems(node)
      Divider()
      editItems(node)
      Divider()
      locationItems(node)
    }
  }

  /// Opening a file somewhere else. Left out entirely for a folder — it expands in place, and a
  /// folder in a window of its own is not a thing this app has — and for the file this window is
  /// already showing, where both items would find the open document and just re-front it.
  @ViewBuilder
  func openItems(_ node: FileNode) -> some View {
    if !node.isDirectory, !model.isShowing(node.url) {
      // Left out rather than disabled when tabs are off, so it is not an item that looks broken.
      // Forcing tabbing from here would override the Tabbing Mode the user chose.
      if model.allowsTabs {
        Button {
          model.openInNewTab(node.url)
        } label: {
          Text("Open in New Tab", bundle: .module)
        }
        .accessibilityIdentifier(Self.openInNewTabIdentifier)
      }

      Button {
        model.openInNewWindow(node.url)
      } label: {
        Text("Open in New Window", bundle: .module)
      }
      .accessibilityIdentifier(Self.openInNewWindowIdentifier)
    }
  }

  /// Both land inside a folder and beside a file, which `WorkspaceModel.directory(for:)` decides
  /// once for the two of them.
  @ViewBuilder
  func newItems(_ node: FileNode) -> some View {
    Button {
      model.newFile(near: node.url)
    } label: {
      Text("New File", bundle: .module)
    }
    .accessibilityIdentifier(Self.newFileIdentifier)

    Button {
      model.beginNewFolder(near: node.url)
    } label: {
      Text("New Folder", bundle: .module)
    }
    .accessibilityIdentifier(Self.newFolderIdentifier)
  }

  @ViewBuilder
  func editItems(_ node: FileNode) -> some View {
    Button {
      model.beginRenaming(node.url)
    } label: {
      Text("Rename…", bundle: .module)
    }
    .accessibilityIdentifier(Self.renameIdentifier)

    Button {
      model.duplicate(node.url)
    } label: {
      Text("Duplicate", bundle: .module)
    }
    .accessibilityIdentifier(Self.duplicateIdentifier)

    // Not `role: .destructive`: the Trash is recoverable, and a red menu item claims otherwise.
    Button {
      model.moveToTrash(node.url)
    } label: {
      Text("Move to Trash", bundle: .module)
    }
    .accessibilityIdentifier(Self.moveToTrashIdentifier)
  }

  /// Where the thing is, rather than what it is — the two that hand it to something else.
  @ViewBuilder
  func locationItems(_ node: FileNode) -> some View {
    Button {
      model.copyPath(node.url)
    } label: {
      Text("Copy Path", bundle: .module)
    }
    .accessibilityIdentifier(Self.copyPathIdentifier)

    Button {
      model.revealInFinder(node.url)
    } label: {
      Text("Reveal in Finder", bundle: .module)
    }
    .accessibilityIdentifier(Self.revealIdentifier)
  }
}

extension WorkspaceOutline {
  /// Identifiers rather than titles, because a title is ambiguous across the whole app — a
  /// query for "Rename…" also finds the main menu's, and XCUITest refuses to click a query
  /// that matches more than one element. They also earn their place for VoiceOver.
  static let openInNewTabIdentifier = "workspace.menu.openInNewTab"
  static let openInNewWindowIdentifier = "workspace.menu.openInNewWindow"
  static let newFileIdentifier = "workspace.menu.newFile"
  static let newFolderIdentifier = "workspace.menu.newFolder"
  static let renameIdentifier = "workspace.menu.rename"
  static let duplicateIdentifier = "workspace.menu.duplicate"
  static let moveToTrashIdentifier = "workspace.menu.moveToTrash"
  static let copyPathIdentifier = "workspace.menu.copyPath"
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
