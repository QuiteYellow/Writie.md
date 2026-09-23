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

  static func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
