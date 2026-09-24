//
//  FolderDrop.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import SwiftUI

/**
 The sidebar's drop surface: a folder dropped on it becomes the folder the sidebar is showing,
 and a file dropped on it lands in the folder it was dropped on.

 **Why an `NSViewRepresentable` and not `.onDrop`.** SwiftUI's `.onDrop(of: [.fileURL])` reads
 the pasteboard through `loadObject(ofClass: URL.self)`, which returns nil for a **file promise**
 — a drag whose file does not exist yet — so a whole class of drags would be refused with no
 sign of why. It also has no way to answer "copy or move" per modifier, and no way to see a ⌘
 pressed while the pointer is still. Ported from `KoLeafApp/Views/FileDropCatcher.swift`, which
 met the first of those problems; the rest is new code, because KoLeaf is an importer with one
 whole-pane drop zone and never has to ask *where*.

 **The overlay must not steal clicks.** The thing underneath is a `List` of rows whose entire
 job is being clicked, so `hitTest` answers nil: drag destinations are delivered by registered
 type and window geometry, not by hit testing, so a view can be invisible to the mouse and still
 be a drop target. That is the trick this port exists for — and it is also why the view has to
 work out which row a drag is over by measuring, since nothing will tell it.

 **A folder still re-roots, wherever it lands.** See `SidebarDrop`, which records why that is
 the spec read literally rather than a decision taken while building this.
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
    // `NSFilePromiseReceiver.readableDraggedTypes` rather than `.filePromise`, which has been
    // deprecated since 10.14: the receiver names the types it can actually read, and a drag
    // registered for the old one is a drag the receiver may not be able to answer.
    registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Created in code, never from a storyboard")
  }

  /// Top-left origin, to match the SwiftUI coordinate space the rows measure themselves into.
  /// Converting between the two by hand would work equally well and would be one subtraction
  /// nobody remembers is there; a view that draws nothing loses nothing by being flipped.
  override var isFlipped: Bool {
    true
  }

  /// Invisible to the mouse, and still a drop target. See the type's note.
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  /**
   Keep asking even while the pointer is still.

   AppKit calls `draggingUpdated` on mouse movement, so someone who stops over a folder and
   *then* decides to hold ⌘ — which is exactly when a person decides — would get no callback
   and a badge still saying copy. This is what makes the modifier work at the moment it is
   actually used.
   */
  override func wantsPeriodicDraggingUpdates() -> Bool {
    true
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    operation(for: sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    operation(for: sender)
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    model?.endDrop()
  }

  override func draggingEnded(_ sender: any NSDraggingInfo) {
    model?.endDrop()
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let model else {
      return false
    }

    let pasteboard = sender.draggingPasteboard
    if let folder = FolderDrop.folder(in: pasteboard) {
      model.openDroppedFolder(folder)
      return true
    }

    guard let destination = model.targetDrop(at: location(of: sender)) else {
      model.endDrop()
      return false
    }

    // Promises first: their placeholder URLs name nothing, so reading files would find a drag
    // that looks empty. The session takes it from here, off the main thread and back again.
    let receivers = SidebarDrop.promises(in: pasteboard)
    guard receivers.isEmpty else {
      FolderImportSession(destination: destination, model: model).receive(receivers)
      return true
    }

    let files = SidebarDrop.files(in: pasteboard)
    guard !files.isEmpty else {
      model.endDrop()
      return false
    }

    model.importDroppedFiles(files, into: destination, moving: isMoving(sender))
    return true
  }

  // MARK: - Private

  /// Where the pointer is, in the coordinate space the rows measured themselves into. The view
  /// is flipped and covers exactly the view that names the space, so this is a conversion out
  /// of window coordinates and nothing more.
  private func location(of sender: any NSDraggingInfo) -> CGPoint {
    convert(sender.draggingLocation, from: nil)
  }

  private func isMoving(_ sender: any NSDraggingInfo) -> Bool {
    SidebarDrop.operation(
      from: .outside,
      modifiers: NSEvent.modifierFlags,
      allowedBy: sender.draggingSourceOperationMask
    ) == .move
  }

  /**
   What this drag would do, and the highlight that says so.

   A folder takes the `.generic` answer the re-root gesture has always had: AppKit draws the
   green plus for `.copy`, and nothing is being copied — the folder stays where it is and the
   sidebar starts listing it.
   */
  private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
    guard let model else {
      return []
    }

    let pasteboard = sender.draggingPasteboard
    guard FolderDrop.folder(in: pasteboard) == nil else {
      model.isDropTargeted = true
      model.dropTarget = nil
      return .generic
    }

    // A promise has no file behind it yet, so its presence is all there is to go on
    let hasContent = !SidebarDrop.promises(in: pasteboard).isEmpty || !SidebarDrop.files(in: pasteboard).isEmpty
    guard hasContent, model.targetDrop(at: location(of: sender)) != nil else {
      model.endDrop()
      return []
    }

    return SidebarDrop.operation(
      from: .outside,
      modifiers: NSEvent.modifierFlags,
      allowedBy: sender.draggingSourceOperationMask
    )
  }
}
