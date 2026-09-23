//
//  DirectoryObserver.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import Foundation

/**
 Tells the sidebar when one directory's contents change.

 `DispatchSource.makeFileSystemObjectSource` and the FSEvents C API are still the only
 options — the macOS 27 SDK adds no Swift-native filesystem-event API — and `DispatchSource`
 is the one that suits a lazily expanded tree, because it watches exactly one directory and
 does not recurse. That is the same unit the scanner reads and the model caches, so a row
 that expands gains a listing and an observer together and loses both when it collapses.

 The events arrive as an `AsyncStream` rather than a callback, so the consumer is an ordinary
 `for await` loop in a `Task` it owns and cancels. Cancelling the task ends the stream, which
 runs `onTermination`, which cancels the source and closes the descriptor: one teardown path
 rather than a `stop()` that a caller can forget.

 **The stream yields nothing but "something changed".** A vnode event carries no detail about
 what, so rescanning the directory is the only answer available, and a `Void` element says so
 rather than implying a diff the source cannot supply.
 */
enum DirectoryObserver {
  /**
   Changes to `directory`'s own contents — files added, removed or renamed inside it.

   Finishes, rather than yielding, when the directory itself is deleted, renamed or unmounted:
   there is nothing left to watch, and the parent directory's own observer is what notices the
   node has gone.

   Buffered `.bufferingNewest(1)`, because a consumer that debounces by sleeping will be
   holding events anyway and only ever needs to know that at least one arrived while it slept.

   **`async` so that `open(2)` is never called on the main thread.** The consumer is a `Task`
   owned by `WorkspaceModel`, which is `@MainActor`, so the task body inherits the main actor
   and a synchronous factory would have run the syscall there — and `open` on a directory
   whose volume has gone away blocks until the mount gives up, which is a beachball with a
   folder as its cause. A `nonisolated async` function hops off the main actor first, matching
   `FolderScanner.contents(of:options:)`, the other call here that touches a file system.
   */
  nonisolated static func events(for directory: URL) async -> AsyncStream<Void> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let descriptor = open(directory.path(percentEncoded: false), O_EVTONLY)
      guard descriptor >= 0 else {
        // Unreadable or gone. The scan reports that; there is no second way to say it here.
        return continuation.finish()
      }

      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor,
        eventMask: [.write, .delete, .rename, .revoke],
        queue: .global(qos: .utility)
      )

      source.setEventHandler {
        if source.data.contains(.write) {
          continuation.yield()
        } else {
          continuation.finish()
        }
      }

      // Cancelling the source is what closes the descriptor, and it is the only thing that
      // does — the cancel handler runs after the last event handler, so it cannot close one
      // out from under a firing event.
      source.setCancelHandler {
        close(descriptor)
      }

      continuation.onTermination = { _ in
        source.cancel()
      }

      source.resume()
    }
  }
}
