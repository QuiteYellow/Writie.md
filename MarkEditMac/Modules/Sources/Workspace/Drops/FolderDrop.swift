//
//  FolderDrop.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import SwiftUI

/**
 A folder dropped on the sidebar becomes the folder the sidebar is showing.

 **Why an `NSViewRepresentable` and not `.onDrop`.** SwiftUI's `.onDrop(of: [.fileURL])` reads
 the pasteboard through `loadObject(ofClass: URL.self)`, which returns nil for a **file promise**
 — a drag whose file does not exist yet — so a whole class of drags would be refused with no
 sign of why. That matters less for this gesture than for D11a's file imports, but the surface
 is the same one those will grow on, and building it twice was not worth the saving. Ported from
 `KoLeafApp/Views/FileDropCatcher.swift`, which met the same problem first.

 **The overlay must not steal clicks.** The thing underneath is a `List` of rows whose entire
 job is being clicked, so `hitTest` answers nil: drag destinations are delivered by registered
 type and window geometry, not by hit testing, so a view can be invisible to the mouse and still
 be a drop target. That is the trick this port exists for.

 **Only folders, for now.** A file dropped here is D11a's question — which folder did it land on,
 copy or move — and an early guess at it would be a wrong answer to a different gesture. So a
 drag carrying no folder is refused, and the cursor says so.
 */
struct FolderDropCatcher: NSViewRepresentable {
  let model: WorkspaceModel

  func makeNSView(context: Context) -> NSView {
    let view = DropView()
    view.model = model
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    (view as? DropView)?.model = model
  }
}

/// The pasteboard half, kept apart from the view so that it can be tested without one.
enum FolderDrop {
  /// The first folder in a drag, or nil when it carries none.
  static func folder(in pasteboard: NSPasteboard) -> URL? {
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL]

    return (urls ?? []).first(where: isFolder)
  }

  /// A package — `.textbundle`, an app — is a directory the user means as one thing, and is
  /// deliberately not a folder to open. Same rule the sidebar's own listing uses.
  static func isFolder(_ url: URL) -> Bool {
    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    return values?.isDirectory == true && values?.isPackage != true
  }
}

// MARK: - Private

private final class DropView: NSView {
  weak var model: WorkspaceModel?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([.fileURL])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Created in code, never from a storyboard")
  }

  /// Invisible to the mouse, and still a drop target. See the type's note.
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    operation(for: sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    operation(for: sender)
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    model?.isDropTargeted = false
  }

  override func draggingEnded(_ sender: any NSDraggingInfo) {
    model?.isDropTargeted = false
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let folder = FolderDrop.folder(in: sender.draggingPasteboard) else {
      return false
    }

    model?.openDroppedFolder(folder)
    return true
  }

  // MARK: - Private

  /// `.generic` rather than `.copy`: AppKit draws the green plus for a copy, and nothing is
  /// being copied — the folder stays where it is and the sidebar starts listing it.
  private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
    guard FolderDrop.folder(in: sender.draggingPasteboard) != nil else {
      model?.isDropTargeted = false
      return []
    }

    model?.isDropTargeted = true
    return .generic
  }
}
