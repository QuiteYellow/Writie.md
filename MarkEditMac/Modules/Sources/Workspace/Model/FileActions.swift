//
//  FileActions.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit

/**
 The things the context menu does to files.

 Small, synchronous and on the main actor, unlike the scan: creating one file or moving one
 name is a single syscall, and a menu item that returned before it had happened would leave
 the sidebar deciding when to show the result.

 Errors are thrown rather than beeped away. A rename that silently does nothing is the worst
 available answer — the caller shows what the file system said.
 */
@MainActor
enum FileActions {
  /**
   Rename `url` to `name` in the same directory.

   Coordinated, not a bare `FileManager.moveItem`. `NSDocument` is a file presenter, so a
   coordinated move is what updates the window title and the document's `fileURL` when the
   file being renamed is the one the window is showing; an uncoordinated one moves the file
   out from under a document that goes on believing it lives at the old path.
   */
  static func rename(_ url: URL, to name: String) throws -> URL {
    let target = url.deletingLastPathComponent().appending(path: name)
    guard target != url else {
      return url
    }

    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var moveError: (any Error)?

    coordinator.coordinate(
      writingItemAt: url,
      options: .forMoving,
      writingItemAt: target,
      options: .forReplacing,
      error: &coordinationError
    ) { source, destination in
      coordinator.item(at: source, willMoveTo: destination)
      do {
        try FileManager.default.moveItem(at: source, to: destination)
        coordinator.item(at: source, didMoveTo: destination)
      } catch {
        moveError = error
      }
    }

    if let error = coordinationError ?? moveError {
      throw error
    }

    return target
  }

  /// Create an empty file in `directory`, named so that it does not collide with what is
  /// already there — "Untitled.md", then "Untitled 2.md", the way Finder counts.
  static func createFile(in directory: URL, named base: String, extension ext: String) throws -> URL {
    for suffix in 0... {
      let name = suffix == 0 ? base : "\(base) \(suffix + 1)"
      let url = directory.appending(path: ext.isEmpty ? name : "\(name).\(ext)")

      // `withoutOverwriting` is what makes the loop a loop rather than a race: the check and
      // the create are one operation, so two of these running at once cannot agree on a name.
      do {
        try Data().write(to: url, options: .withoutOverwriting)
        return url
      } catch let error as NSError where error.code == NSFileWriteFileExistsError {
        continue
      }
    }

    // Unreachable: the loop returns or throws anything that is not "a file of that name
    // already exists", and there is no largest integer to run out of.
    throw CocoaError(.fileWriteUnknown)
  }

  /**
   Create a folder called exactly `name` in `directory`.

   No counting up, unlike `createFile`, and the difference is the gesture rather than an
   inconsistency: New File makes something immediately and needs a name nobody chose, while New
   Folder asks first — so this name was typed, and silently making "Untitled Folder 2" out of it
   would be answering a question the user already answered. A collision throws, and the caller
   shows what the file system said.

   `withIntermediateDirectories: false` is what makes that collision an error at all; `true`
   would succeed onto the existing folder and report nothing.
   */
  static func createFolder(in directory: URL, named name: String) throws -> URL {
    let url = directory.appending(path: name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

    return url
  }

  /**
   Copy `url` beside itself, the way Finder names it: "alpha copy.md", then "alpha copy 2.md".

   The extension is preserved rather than appended to, so a duplicate of a Markdown file is
   still a Markdown file — `alpha.md` becomes `alpha copy.md` and not `alpha.md copy`.
   */
  static func duplicate(_ url: URL) throws -> URL {
    let directory = url.deletingLastPathComponent()
    let ext = url.pathExtension
    let base = "\(url.deletingPathExtension().lastPathComponent) \(copySuffix)"

    for suffix in 0... {
      let name = suffix == 0 ? base : "\(base) \(suffix + 1)"
      let target = directory.appending(path: ext.isEmpty ? name : "\(name).\(ext)")

      do {
        try FileManager.default.copyItem(at: url, to: target)
        return target
      } catch let error as NSError where error.code == NSFileWriteFileExistsError {
        continue
      }
    }

    throw CocoaError(.fileWriteUnknown)
  }

  /**
   Move `url` to the Trash.

   Coordinated, and for the same reason `rename` is: `NSDocument` is a file presenter, so a
   coordinated delete is what tells a window its file has gone. It is deliberately allowed on
   the file the window is showing — the alternative is a file that cannot be deleted without
   first opening a different one.

   `FileManager.trashItem` rather than `NSWorkspace.recycle`: it is synchronous, so it keeps
   this the same shape as every other action here, and it reports its own failure rather than
   through a completion handler. The Trash still provides the undo a user expects either way.
   */
  static func moveToTrash(_ url: URL) throws {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var trashError: (any Error)?

    coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
      do {
        try FileManager.default.trashItem(at: target, resultingItemURL: nil)
      } catch {
        trashError = error
      }
    }

    if let error = coordinationError ?? trashError {
      throw error
    }
  }

  /// The file's path, as text. What "Copy Path" means everywhere else, and what ⌥⌘C does in
  /// Finder — a string to paste into a terminal or a link, not a file to paste into a folder.
  static func copyPath(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.path(percentEncoded: false), forType: .string)
  }

  static func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}

// MARK: - Private

private extension FileActions {
  /// Finder's word for a copy, localised with it. Not a file name on its own, so it lives here
  /// rather than in `WorkspaceStrings` with the names that are.
  static var copySuffix: String {
    String(
      localized: "copy",
      bundle: .module,
      comment: "Appended to a duplicated file's name, as Finder does: \"alpha copy.md\"."
    )
  }
}
