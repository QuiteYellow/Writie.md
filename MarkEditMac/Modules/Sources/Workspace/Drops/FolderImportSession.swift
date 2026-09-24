//
//  FolderImportSession.swift
//
//  Fork addition (Writie.md), not present upstream.
//

import AppKit

/**
 One promise drag dropped on the sidebar, from the moment it is taken over to the moment its
 files are in the folder it landed on — `drops.md` §3.3.

 **Two-step, and the second step is the point.** Files are received into a temporary directory
 and copied into the destination afterwards, never written straight there. Receiving in place
 would be fewer steps and the wrong trade twice over: `DirectoryObserver` fires while the file
 is still being written and `WorkspaceModel` coalesces those events over 120 ms — a window
 tuned for a save burst, not a multi-second SFTP fetch — so the tree would show a half-written
 file; and a fetch that failed halfway would leave debris inside someone's notes folder. What
 lands here is copied on once it is whole, which is one appearance in the tree and nothing to
 clean up after a failure.

 **A received file is always copied in, never moved.** The temporary copies are deliberately
 left behind for the system to reclaim, which is the rule D10 arrived at, and a move would make
 the import's success depend on a second file system operation that has nothing to recover to.
 ⌘ is not consulted for the same reason: there is no original anywhere to move.

 An object rather than a chain of closures because something has to outlive the drag:
 `NSFilePromiseReceiver` calls back per file on a queue of its own, and `active` is what keeps
 the session alive until the last of those has arrived.
 */
@MainActor
final class FolderImportSession: NSObject, PromiseReceiving {
  init(destination: URL, model: WorkspaceModel) {
    self.destination = destination
    self.model = model
    super.init()

    Self.active.insert(self)
  }

  /// Ask each promise for its files, into a folder of our own. See the type's note.
  func receive(_ receivers: [NSFilePromiseReceiver]) {
    guard let directory = Self.temporaryDirectory() else {
      return finish(with: [])
    }

    // `fileNames` is the source's own promise of what it will produce; a source that names
    // nothing still delivers one callback, so one is the floor rather than zero
    awaitFiles(expecting: receivers.reduce(0) { $0 + max($1.fileNames.count, 1) }, buckets: receivers.count)

    let queue = OperationQueue()
    for (index, receiver) in receivers.enumerated() {
      receiver.receivePromisedFiles(
        atDestination: directory,
        options: [:],
        operationQueue: queue,
        reader: PromiseReader.reader(for: self, at: index)
      )
    }
  }

  /// How many callbacks to expect, and how many sources they will arrive from. Split out of
  /// `receive` for the same reason the editor's session splits it: `NSFilePromiseReceiver`
  /// cannot be constructed by hand, so this is the only way a test can drive the rest.
  func awaitFiles(expecting count: Int, buckets: Int) {
    expected = count
    received = Array(repeating: [], count: max(buckets, 1))
  }

  func didReceive(_ url: URL, failed: Bool, from index: Int) {
    // A failed promise still calls back, with a URL for a file that was never written
    if !failed, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
      received[index].append(url)
    }

    expected -= 1
    guard expected <= 0 else {
      return
    }

    // Flattened in the order the pasteboard listed the promises, so that dropping three files
    // lands three files in the order they were dragged rather than the order they arrived
    finish(with: received.flatMap { $0 })
  }

  // MARK: - Private

  private static var active = Set<FolderImportSession>()

  private let destination: URL
  private weak var model: WorkspaceModel?

  private var expected = 0
  private var received = [[URL]]()

  /// A source that produces more files than it promised would otherwise finish twice, and
  /// import the same drop again.
  private var hasFinished = false

  private func finish(with fileURLs: [URL]) {
    guard !hasFinished else {
      return
    }

    hasFinished = true
    defer { Self.active.remove(self) }

    guard !fileURLs.isEmpty else {
      // Nothing arrived: every promise failed, or the source produced no files at all. The
      // highlight has to come off either way, which `importDroppedFiles` would have done.
      return model?.endDrop() ?? ()
    }

    model?.importDroppedFiles(fileURLs, into: destination, moving: false)
  }

  private static func temporaryDirectory() -> URL? {
    try? FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(filePath: NSTemporaryDirectory()),
      create: true
    )
  }
}
