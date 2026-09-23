//
//  WorkspaceSidebarView.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import SwiftUI

/**
 The file tree.

 `List` rather than `NSOutlineView`: there is no `NSOutlineViewDiffableDataSource` in the
 macOS 27 SDK, so an outline view means hand-written `reloadItem(_:reloadChildren:)`
 bookkeeping against a tree that changes underneath it — the shape that produces stale rows,
 and this milestone makes the tree change underneath it on purpose. `.listStyle(.sidebar)`
 also carries the system's current source-list appearance for free.

 The rows themselves are `WorkspaceOutline`, which recurses.
 */
struct WorkspaceSidebarView: View {
  @Bindable var model: WorkspaceModel

  /**
   Whether this view draws the root picker itself.

   It shouldn't on macOS 26 and later, where the picker is a `NSSplitViewItemAccessoryViewController`
   pinned to the split view item — the sanctioned way to put a footer in a sidebar, and the
   one that gets the system's own footer treatment. Below 26 that class does not exist, so the
   picker rides along the bottom of this view instead.
   */
  let drawsFooter: Bool

  @ViewBuilder var body: some View {
    if drawsFooter {
      content.safeAreaInset(edge: .bottom, spacing: 0) {
        footer
      }
    } else {
      content
    }
  }
}

// MARK: - Private

private extension WorkspaceSidebarView {
  @ViewBuilder var content: some View {
    switch model.state {
    case .noRoot:
      placeholder("No folder is open", offersChoosing: true)
    case .loading:
      ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .loaded(let nodes) where nodes.isEmpty:
      placeholder("This folder is empty")
    case .loaded(let nodes):
      tree(nodes)
    case .unreadable(let url):
      placeholder("\(url.lastPathComponent) can’t be read", offersChoosing: true)
    }
  }

  var footer: some View {
    VStack(spacing: 0) {
      Divider()
      WorkspaceFooterView(model: model)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
  }

  func tree(_ nodes: [FileNode]) -> some View {
    List(selection: $model.selection) {
      WorkspaceOutline(model: model, nodes: nodes)
    }
    .listStyle(.sidebar)
    .alert(Text("Rename", bundle: .module), isPresented: isRenaming) {
      TextField(text: $model.proposedName) {
        Text("Name", bundle: .module)
      }

      Button {
        model.commitRenaming()
      } label: {
        Text("Rename", bundle: .module)
      }

      Button(role: .cancel) {
        model.cancelRenaming()
      } label: {
        Text("Cancel", bundle: .module)
      }
    }
    .alert(Text(verbatim: model.failure ?? ""), isPresented: hasFailed) {
      Button {
        model.failure = nil
      } label: {
        Text("OK", bundle: .module)
      }
    }
  }

  /// The file system's own sentence is the alert's title, with nothing of ours above it —
  /// "The file “a.md” couldn’t be moved because a file with the same name already exists"
  /// says more than any heading the fork could put over it.
  var hasFailed: Binding<Bool> {
    Binding { model.failure != nil } set: { if !$0 { model.failure = nil } }
  }

  var isRenaming: Binding<Bool> {
    Binding { model.renaming != nil } set: { if !$0 { model.cancelRenaming() } }
  }

  /// Fork strings live in the module's own catalog, read through `Bundle.module`.
  /// `MarkEditMac/Resources/Localizable.xcstrings` takes 37 upstream commits a year and is
  /// never touched here.
  func placeholder(_ key: LocalizedStringKey, offersChoosing: Bool = false) -> some View {
    VStack(spacing: 10) {
      Text(key, bundle: .module)
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      // The footer carries the same action, but a sidebar with nothing in it is where
      // someone looks first, so the empty states answer it where they are read.
      if offersChoosing {
        Button {
          model.chooseFolder()
        } label: {
          Text("Choose Folder…", bundle: .module)
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityIdentifier(Self.placeholderIdentifier)
  }
}

extension WorkspaceSidebarView {
  /// Whichever empty state is showing — no folder, empty folder, or unreadable folder. The
  /// text tells them apart; the identifier only says "the sidebar is not listing files".
  static let placeholderIdentifier = "workspace.placeholder"
}
