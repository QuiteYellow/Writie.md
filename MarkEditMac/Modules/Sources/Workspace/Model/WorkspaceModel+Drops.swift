//
//  WorkspaceModel+Drops.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 What the sidebar does with something dropped on it.

 Split out of `WorkspaceModel.swift` rather than living there, and the reason is mechanical:
 the class body passed SwiftLint's 250-line limit the moment D11a landed. An extension is the
 cheaper half of that trade — the three stored properties a drag needs stay on the class,
 because `@Observable` can only see them there, and everything that reads them lives here.

 The rules themselves are `SidebarDrop`'s. This is where they meet the tree.
 */
extension WorkspaceModel {
  /**
   Open a folder dropped on the sidebar, making it this workspace's root.

   The gesture people try first, and until now the sidebar simply refused it: the only way to
   change folders was the footer's menu. Dropping a folder on a file tree means "show me this
   one" in every app that has one.

   Only a folder, and that stayed true once files could be dropped too: a file lands in the
   folder it was dropped on, and a folder re-roots wherever it lands. `SidebarDrop` records why
   the second half is the spec read literally rather than a decision taken while building it.
   */
  public func openDroppedFolder(_ url: URL) {
    endDrop()
    guard FolderDrop.isFolder(url) else {
      return
    }

    roots.open(url)
  }

  /**
   Which folder a drop at `point` would land in, and light that target up on the way past.

   Returns nil only when there is nothing to drop into at all, which is a sidebar with no
   folder open.
   */
  public func targetDrop(at point: CGPoint) -> URL? {
    let destination = SidebarDrop.destination(landingOn: row(at: point), root: root)
    guard let destination else {
      endDrop()
      return nil
    }

    // The root is the destination whenever the pointer is over no row, or over a file that
    // sits at the top level. It has no row, so the whole sidebar is the highlight.
    let isRoot = root.map { AssetFolder.isSameDirectory(destination, $0) } ?? false

    // Snapped onto the node's own URL where there is one. A row compares `dropTarget` with
    // `==` on every redraw, which is too hot for a canonicalisation, and a URL built by
    // deleting a path component can disagree with a scanned one over a trailing slash.
    dropTarget = isRoot ? nil : (node(for: destination)?.url ?? destination)
    isDropTargeted = isRoot

    return destination
  }

  /**
   Where a drop on the row called `name` would land, as the **view** reported it.

   The debug seam for the sidebar's drops, and the one thing the module's own tests cannot
   reach: they plant `rowFrames` themselves, so they prove the arithmetic and prove nothing
   about whether the live view ever fills it in. A UI test driving this against the running app
   does — and gets nil, rather than a plausible-looking fallback, when it does not.

   Nil `name` means the sidebar itself: a point below every row, which is what dropping on the
   empty space under the tree means and resolves to the root.
   */
  public func debugDropPoint(row name: String?) -> CGPoint? {
    guard let name else {
      return CGPoint(x: 1, y: (rowFrames.values.map(\.maxY).max() ?? 0) + 1)
    }

    guard let frame = rowFrames.first(where: { $0.key.lastPathComponent == name })?.value else {
      return nil
    }

    return CGPoint(x: frame.midX, y: frame.midY)
  }

  /// Put the sidebar back to not-being-dropped-on. Called when a drag leaves, when it ends,
  /// and before anything a drop does, so no path can leave a highlight behind.
  public func endDrop() {
    isDropTargeted = false
    dropTarget = nil
  }

  /**
   Bring dropped files into `directory` — `drops.md` §3.1.

   Every file is attempted, and the **first** failure is the one reported: a drag of twelve
   files into a folder that refuses all of them should produce one alert, not twelve, and the
   first refusal says the same thing the twelfth would.

   The destination is expanded afterwards so the files can be seen arriving. Expanding is also
   what starts watching the directory, so the rows appear on the observer's own event rather
   than on a reload this would otherwise have to ask for.

   **No Grant Access… offer here, unlike the editor's drops.** Everything the sidebar can
   target lives under the root, and the root is open through a security-scoped bookmark, so a
   sandbox refusal is not the expected failure the way it is for a document opened from
   somewhere else. A refusal here is reported as whatever the file system said.
   */
  public func importDroppedFiles(_ urls: [URL], into directory: URL, moving: Bool) {
    endDrop()

    var firstFailure: String?
    for url in urls {
      do {
        _ = try FileActions.importItem(url, into: directory, moving: moving)
      } catch {
        WorkspaceLog.drops.error("Could not import \(url.path(percentEncoded: false), privacy: .public) into \(directory.path(percentEncoded: false), privacy: .public): \(error.localizedDescription, privacy: .public)")
        firstFailure = firstFailure ?? error.localizedDescription
      }
    }

    if let root, !AssetFolder.isSameDirectory(directory, root) {
      setExpanded(true, for: directory)
    }

    if let firstFailure {
      failure = firstFailure
    }
  }

  // MARK: - Private

  /// The row under a point, in the coordinate space `rowFrames` was measured in. Nil for a
  /// point that is over no row, which is both empty space and the footer.
  private func row(at point: CGPoint) -> FileNode? {
    guard let url = rowFrames.first(where: { $0.value.contains(point) })?.key else {
      return nil
    }

    return node(for: url)
  }
}
