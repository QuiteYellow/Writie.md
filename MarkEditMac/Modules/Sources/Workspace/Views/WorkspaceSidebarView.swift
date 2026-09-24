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

  var body: some View {
    sidebar
      // Named so that the rows and the drop overlay measure against the same origin. The
      // overlay is an `NSView` and the rows are SwiftUI, and this is the one thing they have
      // to agree about — see `FolderDropCatcher`, which flips itself to match.
      .coordinateSpace(.named(Self.dropSpace))
      .onPreferenceChange(RowFrames.self) { frames in
        // The closure is `@Sendable` and the model is main-actor, so the hop is explicit.
        Task { @MainActor in model.rowFrames = frames }
      }
      // The catcher is invisible to the mouse and still takes drags; the treatment says so.
      // Both cover the whole sidebar, the empty state included — "No folder is open" is
      // exactly where someone drops their first folder.
      .overlay { FolderDropCatcher(model: model) }
      .overlay { targeting }
  }
}

// MARK: - Private

private extension WorkspaceSidebarView {
  @ViewBuilder var sidebar: some View {
    if drawsFooter {
      content.safeAreaInset(edge: .bottom, spacing: 0) {
        footer
      }
    } else {
      content
    }
  }

  /// KoLeaf's own treatment, which is a dashed accent border over a 6% accent fill: enough to
  /// read as a target at a glance, not so much that it hides what is underneath.
  @ViewBuilder var targeting: some View {
    if model.isDropTargeted {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        .background(Color.accentColor.opacity(0.06))
        .padding(4)
        .allowsHitTesting(false)
    }
  }

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
    .alert(promptTitle, isPresented: isPrompting) {
      TextField(text: $model.proposedName) {
        Text("Name", bundle: .module)
      }

      // The confirm button says what it will do. "Rename" over a folder that does not exist yet
      // would be the wrong verb, and "OK" would be no verb at all.
      Button {
        model.commitPrompt()
      } label: {
        promptTitle
      }

      Button(role: .cancel) {
        model.cancelPrompt()
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

  var isPrompting: Binding<Bool> {
    Binding { model.prompt != nil } set: { if !$0 { model.cancelPrompt() } }
  }

  /// Both the alert's title and its confirm button: one word that names the act, so the button is
  /// "Rename" over a file that exists and "New Folder" over one that does not exist yet.
  var promptTitle: Text {
    switch model.prompt {
    case .newFolder:
      Text("New Folder", bundle: .module)
    case .renaming, .none:
      Text("Rename", bundle: .module)
    }
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
  /// The coordinate space rows report their frames in and the drop overlay converts into.
  /// One name, in one place, because the two halves are in different frameworks and a typo
  /// would land every drop in the wrong folder rather than failing.
  static let dropSpace = "workspace.sidebar"

  /// Whichever empty state is showing — no folder, empty folder, or unreadable folder. The
  /// text tells them apart; the identifier only says "the sidebar is not listing files".
  static let placeholderIdentifier = "workspace.placeholder"
}
