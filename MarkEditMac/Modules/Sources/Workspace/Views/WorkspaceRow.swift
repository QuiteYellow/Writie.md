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

 **The row also reports where it is.** The drop overlay is an `NSView` that deliberately fails
 hit testing, so nothing will tell it which row a drag is over — and `List` has no API that
 would. Each row measuring itself into a `PreferenceKey` is what closes that gap, and it is
 measured in the sidebar's own named coordinate space so the answer survives scrolling.
 */
struct WorkspaceRow: View {
  let node: FileNode

  /// Whether a drag is hovering this row's folder right now. Read from the model by the
  /// caller, because `drops.md` §5 is that a row's appearance may only depend on observable
  /// model state — a plain property would leave the highlight never redrawing.
  var isDropTarget = false

  var body: some View {
    Label {
      Text(node.name)
        .lineLimit(1)
        .truncationMode(.middle)
    } icon: {
      Image(systemName: node.isDirectory ? "folder" : "doc.text")
    }
    .accessibilityIdentifier(Self.identifier(for: node))
    .background { frameReporter }
    .overlay { targeting }
  }

  /// Stable across scans, because it is derived from the name rather than from row position.
  static func identifier(for node: FileNode) -> String {
    "workspace.row.\(node.name)"
  }
}

// MARK: - Private

private extension WorkspaceRow {
  var frameReporter: some View {
    GeometryReader { proxy in
      Color.clear.preference(
        key: RowFrames.self,
        value: [node.url: proxy.frame(in: .named(WorkspaceSidebarView.dropSpace))]
      )
    }
  }

  /// The sidebar's own targeting treatment at row scale — the same dashed accent border and 6%
  /// accent fill, so a drag into a folder and a drag onto the sidebar read as one gesture
  /// rather than two. Smaller radius and no inset, because a row is 20 points tall and the
  /// sidebar's 4-point padding would eat most of it.
  @ViewBuilder var targeting: some View {
    if isDropTarget {
      RoundedRectangle(cornerRadius: 5)
        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        .background(Color.accentColor.opacity(0.06))
        .allowsHitTesting(false)
    }
  }
}

/**
 Where every visible row is, collected up the view tree and handed to the model.

 A `PreferenceKey` rather than each row writing to the model directly: a row cannot write to
 observable state during its own `body` without SwiftUI complaining about a mutation mid-update,
 and the preference mechanism exists for exactly this — measure during layout, deliver after.
 */
struct RowFrames: PreferenceKey {
  static let defaultValue = [URL: CGRect]()

  static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
    value.merge(nextValue()) { $1 }
  }
}
